package wa

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/appstate"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"

	"go.mau.fi/whatsmeow/proto/waE2E"

	_ "modernc.org/sqlite"
)

type EventSink func(method string, payload any)

type Client struct {
	dataDir string
	log     waLog.Logger
	sink    EventSink
	store   *MemoryStore

	mu     sync.Mutex
	client *whatsmeow.Client
	state  string
	label  string
}

func New(dataDir string, sink EventSink) *Client {
	return &Client{
		dataDir: dataDir,
		log:     waLog.Stdout("GlassChatWA", "INFO", true),
		sink:    sink,
		store:   NewMemoryStore(),
		state:   "disconnected",
	}
}

func (c *Client) Status() (state, label, detail string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.state, c.label, ""
}

func (c *Client) Store() *MemoryStore { return c.store }

func (c *Client) setState(state, label string) {
	c.mu.Lock()
	c.state = state
	if label != "" {
		c.label = label
	}
	payloadState := c.state
	payloadLabel := c.label
	c.mu.Unlock()
	c.sink("session.status", map[string]any{
		"state":        payloadState,
		"accountLabel": payloadLabel,
		"protocol":     "whatsapp",
	})
}

func (c *Client) EnsureStarted(ctx context.Context) error {
	c.mu.Lock()
	existing := c.client
	c.mu.Unlock()
	if existing != nil {
		return nil
	}
	return c.start(ctx)
}

func (c *Client) start(ctx context.Context) error {
	if err := os.MkdirAll(c.dataDir, 0o700); err != nil {
		return err
	}
	dbPath := filepath.Join(c.dataDir, "whatsmeow.db")
	dsn := fmt.Sprintf("file:%s?_pragma=foreign_keys(1)", dbPath)

	container, err := sqlstore.New(ctx, "sqlite", dsn, c.log.Sub("DB"))
	if err != nil {
		return fmt.Errorf("open sqlstore: %w", err)
	}
	device, err := container.GetFirstDevice(ctx)
	if err != nil {
		return fmt.Errorf("get device: %w", err)
	}

	client := whatsmeow.NewClient(device, c.log.Sub("Client"))
	applyCompanionFingerprint(client)
	client.AddEventHandler(c.handleEvent)

	c.mu.Lock()
	c.client = client
	c.mu.Unlock()

	if client.Store.ID != nil {
		c.setState("connecting", client.Store.ID.User)
		if err := client.Connect(); err != nil {
			c.setState("error", "")
			return err
		}
		c.setState("connected", displayLabel(client))
		_ = client.SendPresence(context.Background(), types.PresenceAvailable)
		go c.refreshDirectory(context.Background())
		go c.fetchAppState(context.Background())
		return nil
	}

	c.setState("disconnected", "")
	return nil
}

func (c *Client) StartPairing(ctx context.Context) error {
	if err := c.EnsureStarted(ctx); err != nil {
		return err
	}

	c.mu.Lock()
	client := c.client
	c.mu.Unlock()
	if client == nil {
		return fmt.Errorf("client not initialized")
	}

	if client.Store.ID != nil {
		if !client.IsConnected() {
			c.setState("connecting", displayLabel(client))
			if err := client.Connect(); err != nil {
				c.setState("error", "")
				return err
			}
		}
		c.setState("connected", displayLabel(client))
		_ = client.SendPresence(ctx, types.PresenceAvailable)
		c.sink("session.pair.success", map[string]any{
			"jid":          client.Store.ID.String(),
			"accountLabel": displayLabel(client),
			"protocol":     "whatsapp",
		})
		go c.refreshDirectory(context.Background())
		go c.fetchAppState(context.Background())
		return nil
	}

	if client.IsConnected() {
		client.Disconnect()
	}

	qrChan, err := client.GetQRChannel(ctx)
	if err != nil {
		return fmt.Errorf("qr channel: %w", err)
	}

	c.setState("awaiting_pairing", "")
	if err := client.Connect(); err != nil {
		c.setState("error", "")
		return fmt.Errorf("connect: %w", err)
	}

	go func() {
		for item := range qrChan {
			switch item.Event {
			case "code":
				c.sink("session.pair.qr", map[string]any{"code": item.Code, "protocol": "whatsapp"})
			case "success":
				c.setState("connected", displayLabel(client))
				jid := ""
				if client.Store.ID != nil {
					jid = client.Store.ID.String()
				}
				c.sink("session.pair.success", map[string]any{
					"jid":          jid,
					"accountLabel": displayLabel(client),
					"protocol":     "whatsapp",
				})
				_ = client.SendPresence(context.Background(), types.PresenceAvailable)
				go c.refreshDirectory(context.Background())
				go c.fetchAppState(context.Background())
			case "timeout":
				c.setState("disconnected", "")
				c.sink("session.pair.timeout", map[string]any{"detail": "QR code expired", "protocol": "whatsapp"})
			default:
				if item.Error != nil {
					c.setState("error", "")
					c.sink("session.pair.error", map[string]any{"detail": item.Error.Error(), "protocol": "whatsapp"})
				}
			}
		}
	}()

	return nil
}

func (c *Client) ConnectExisting(ctx context.Context) error {
	if err := c.EnsureStarted(ctx); err != nil {
		return err
	}
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()
	if client == nil {
		return fmt.Errorf("client not initialized")
	}
	if client.Store.ID == nil {
		return fmt.Errorf("not paired yet — start QR pairing first")
	}
	if client.IsConnected() {
		c.setState("connected", displayLabel(client))
		go c.refreshDirectory(ctx)
		return nil
	}
	c.setState("connecting", displayLabel(client))
	if err := client.Connect(); err != nil {
		c.setState("error", "")
		return err
	}
	c.setState("connected", displayLabel(client))
	_ = client.SendPresence(ctx, types.PresenceAvailable)
	go c.refreshDirectory(ctx)
	go c.fetchAppState(ctx)
	return nil
}

func (c *Client) Logout(ctx context.Context) error {
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()
	if client == nil {
		c.store.Clear()
		c.setState("disconnected", "")
		return nil
	}
	if client.IsLoggedIn() {
		err := client.Logout(ctx)
		c.mu.Lock()
		c.client = nil
		c.mu.Unlock()
		c.store.Clear()
		c.setState("disconnected", "")
		return err
	}
	client.Disconnect()
	c.mu.Lock()
	c.client = nil
	c.mu.Unlock()
	_ = os.Remove(filepath.Join(c.dataDir, "whatsmeow.db"))
	c.store.Clear()
	c.setState("disconnected", "")
	return nil
}

func (c *Client) SendText(ctx context.Context, chatID, text string) (string, error) {
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()
	if client == nil || !client.IsLoggedIn() {
		return "", fmt.Errorf("not connected")
	}
	jid, err := types.ParseJID(chatID)
	if err != nil {
		return "", fmt.Errorf("invalid chat id: %w", err)
	}
	msg := &waE2E.Message{Conversation: proto.String(text)}
	resp, err := client.SendMessage(ctx, jid, msg)
	if err != nil {
		return "", err
	}
	rec := MessageRecord{
		ID:         resp.ID,
		ChatID:     chatID,
		SenderName: "You",
		Text:       text,
		Timestamp:  nowUnix(),
		FromMe:     true,
	}
	c.store.AppendMessage(rec)
	c.sink("messages.event", map[string]any{
		"id":         rec.ID,
		"chatId":     rec.ChatID,
		"senderName": rec.SenderName,
		"text":       rec.Text,
		"timestamp":  rec.Timestamp,
		"fromMe":     true,
		"protocol":   "whatsapp",
	})
	return resp.ID, nil
}

func (c *Client) ListChats() []ChatRecord {
	return c.store.ListChats()
}

func (c *Client) ListMessages(chatID string, limit int) []MessageRecord {
	return c.store.ListMessages(chatID, limit)
}

func (c *Client) MarkRead(ctx context.Context, chatID string, messageIDs []string) error {
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()
	if client == nil || !client.IsLoggedIn() {
		return fmt.Errorf("not connected")
	}
	jid, err := types.ParseJID(chatID)
	if err != nil {
		return err
	}
	ids := make([]types.MessageID, 0, len(messageIDs))
	for _, id := range messageIDs {
		ids = append(ids, types.MessageID(id))
	}
	if len(ids) == 0 {
		// Mark latest known message if caller didn't pass ids.
		msgs := c.store.ListMessages(chatID, 1)
		if len(msgs) == 0 {
			return nil
		}
		ids = append(ids, types.MessageID(msgs[len(msgs)-1].ID))
	}
	return client.MarkRead(ctx, ids, time.Now(), jid, jid)
}

func (c *Client) fetchAppState(ctx context.Context) {
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()
	if client == nil || !client.IsLoggedIn() {
		return
	}
	// Pull contact/pin/mute patches when available — best-effort.
	_ = client.FetchAppState(ctx, appstate.WAPatchRegular, false, false)
	_ = client.FetchAppState(ctx, appstate.WAPatchRegularHigh, false, false)
	c.refreshDirectory(ctx)
}

func (c *Client) refreshDirectory(ctx context.Context) {
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()
	if client == nil || !client.IsLoggedIn() {
		return
	}

	if client.Store != nil && client.Store.Contacts != nil {
		contacts, err := client.Store.Contacts.GetAllContacts(ctx)
		if err == nil {
			for jid, info := range contacts {
				name := firstNonEmpty(info.FullName, info.PushName, info.BusinessName)
				if name == "" {
					continue
				}
				c.store.SetName(jid.String(), name)
				c.store.UpsertChat(ChatRecord{
					ID:       jid.String(),
					Title:    name,
					Kind:     "individual",
					Protocol: "whatsapp",
				})
			}
		}
	}

	groups, err := client.GetJoinedGroups(ctx)
	if err == nil {
		for _, g := range groups {
			title := g.Name
			if title == "" {
				title = g.JID.String()
			}
			c.store.SetName(g.JID.String(), title)
			c.store.UpsertChat(ChatRecord{
				ID:       g.JID.String(),
				Title:    title,
				Kind:     "group",
				Protocol: "whatsapp",
			})
		}
	}

	c.sink("chats.updated", map[string]any{
		"protocol": "whatsapp",
		"chats":    c.store.ListChats(),
	})
}

func (c *Client) handleEvent(evt any) {
	switch v := evt.(type) {
	case *events.Message:
		text := messageText(v)
		if text == "" {
			return
		}
		sender := v.Info.PushName
		if sender == "" {
			sender = c.store.Name(v.Info.Sender.String())
		}
		if sender == "" {
			sender = v.Info.Sender.User
		}
		chatID := v.Info.Chat.String()
		if name := c.store.Name(chatID); name == "" && !v.Info.IsGroup {
			c.store.SetName(chatID, sender)
		}
		rec := MessageRecord{
			ID:         v.Info.ID,
			ChatID:     chatID,
			SenderName: sender,
			Text:       text,
			Timestamp:  v.Info.Timestamp.Unix(),
			FromMe:     v.Info.IsFromMe,
		}
		c.store.AppendMessage(rec)
		kind := "individual"
		if v.Info.IsGroup {
			kind = "group"
		}
		title := c.store.Name(chatID)
		if title == "" {
			title = sender
		}
		c.store.UpsertChat(ChatRecord{
			ID:           chatID,
			Title:        title,
			Kind:         kind,
			LastPreview:  text,
			LastActivity: rec.Timestamp,
			Protocol:     "whatsapp",
		})
		c.sink("messages.event", map[string]any{
			"id":         rec.ID,
			"chatId":     rec.ChatID,
			"senderName": rec.SenderName,
			"text":       rec.Text,
			"timestamp":  rec.Timestamp,
			"fromMe":     rec.FromMe,
			"protocol":   "whatsapp",
		})

	case *events.HistorySync:
		c.applyHistorySync(v)
		c.sink("chats.updated", map[string]any{
			"protocol": "whatsapp",
			"chats":    c.store.ListChats(),
		})

	case *events.Connected:
		c.mu.Lock()
		client := c.client
		c.mu.Unlock()
		c.setState("connected", displayLabel(client))
		go c.refreshDirectory(context.Background())

	case *events.Disconnected:
		c.setState("disconnected", "")

	case *events.LoggedOut:
		c.setState("disconnected", "")
		c.sink("session.pair.error", map[string]any{"detail": "Logged out from phone", "protocol": "whatsapp"})
	}
}

func (c *Client) applyHistorySync(evt *events.HistorySync) {
	if evt == nil || evt.Data == nil {
		return
	}
	for _, pn := range evt.Data.GetPushnames() {
		c.store.SetName(pn.GetID(), pn.GetPushname())
	}
	for _, conv := range evt.Data.GetConversations() {
		chatID := conv.GetID()
		if chatID == "" {
			continue
		}
		title := c.store.Name(chatID)
		if title == "" {
			title = chatID
		}
		kind := "individual"
		if strings.HasSuffix(chatID, "@g.us") {
			kind = "group"
			if n := conv.GetName(); n != "" {
				title = n
				c.store.SetName(chatID, n)
			}
		}
		var lastPreview string
		var lastTS int64
		for _, wrapped := range conv.GetMessages() {
			wm := wrapped.GetMessage()
			if wm == nil {
				continue
			}
			key := wm.GetKey()
			if key == nil {
				continue
			}
			text := webMessageText(wm)
			if text == "" {
				continue
			}
			fromMe := key.GetFromMe()
			sender := "Contact"
			if fromMe {
				sender = "You"
			} else if p := key.GetParticipant(); p != "" {
				sender = c.store.Name(p)
				if sender == "" {
					sender = p
				}
			} else if !strings.HasSuffix(chatID, "@g.us") {
				sender = firstNonEmpty(c.store.Name(chatID), chatID)
			}
			ts := int64(wm.GetMessageTimestamp())
			rec := MessageRecord{
				ID:         key.GetID(),
				ChatID:     chatID,
				SenderName: sender,
				Text:       text,
				Timestamp:  ts,
				FromMe:     fromMe,
			}
			c.store.AppendMessage(rec)
			lastPreview = text
			if ts > lastTS {
				lastTS = ts
			}
		}
		c.store.UpsertChat(ChatRecord{
			ID:           chatID,
			Title:        title,
			Kind:         kind,
			LastPreview:  lastPreview,
			LastActivity: lastTS,
			Protocol:     "whatsapp",
		})
	}
}

func messageText(v *events.Message) string {
	if v.Message == nil {
		return ""
	}
	if t := v.Message.GetConversation(); t != "" {
		return t
	}
	if ext := v.Message.GetExtendedTextMessage(); ext != nil {
		return ext.GetText()
	}
	if img := v.Message.GetImageMessage(); img != nil {
		if cap := img.GetCaption(); cap != "" {
			return cap
		}
		return "[Image]"
	}
	if doc := v.Message.GetDocumentMessage(); doc != nil {
		if cap := doc.GetCaption(); cap != "" {
			return cap
		}
		return "[Document] " + doc.GetFileName()
	}
	if v.Message.GetAudioMessage() != nil {
		return "[Voice message]"
	}
	return ""
}

func webMessageText(wm interface{ GetMessage() *waE2E.Message }) string {
	msg := wm.GetMessage()
	if msg == nil {
		return ""
	}
	if t := msg.GetConversation(); t != "" {
		return t
	}
	if ext := msg.GetExtendedTextMessage(); ext != nil {
		return ext.GetText()
	}
	if img := msg.GetImageMessage(); img != nil {
		if cap := img.GetCaption(); cap != "" {
			return cap
		}
		return "[Image]"
	}
	return ""
}

func displayLabel(client *whatsmeow.Client) string {
	if client == nil || client.Store == nil || client.Store.ID == nil {
		return ""
	}
	if client.Store.PushName != "" {
		return client.Store.PushName
	}
	return "+" + client.Store.ID.User
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}
