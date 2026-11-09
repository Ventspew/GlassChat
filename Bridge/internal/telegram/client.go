package telegram

import (
	"context"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gotd/td/session"
	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/auth/qrlogin"
	"github.com/gotd/td/tg"
)

type EventSink func(method string, payload any)

type ChatRecord struct {
	ID           string `json:"id"`
	Title        string `json:"title"`
	Kind         string `json:"kind"`
	LastPreview  string `json:"lastPreview"`
	LastActivity int64  `json:"lastActivity"`
	UnreadCount  int    `json:"unreadCount"`
	IsPinned     bool   `json:"isPinned"`
	Protocol     string `json:"protocol"`
}

type MessageRecord struct {
	ID         string `json:"id"`
	ChatID     string `json:"chatId"`
	SenderName string `json:"senderName"`
	Text       string `json:"text"`
	Timestamp  int64  `json:"timestamp"`
	FromMe     bool   `json:"fromMe"`
}

type peerRef struct {
	peer tg.InputPeerClass
}

// Client is a gotd-backed Telegram adapter. Requires api_id + api_hash.
type Client struct {
	dataDir string
	sink    EventSink

	mu      sync.Mutex
	apiID   int
	apiHash string
	state   string
	label   string
	chats   []ChatRecord
	msgs    map[string][]MessageRecord
	peers   map[string]peerRef
	api     *tg.Client
	running bool
	cancel  context.CancelFunc
	ready   chan struct{}
}

func New(dataDir string, sink EventSink) *Client {
	return &Client{
		dataDir: dataDir,
		sink:    sink,
		state:   "disconnected",
		msgs:    map[string][]MessageRecord{},
		peers:   map[string]peerRef{},
		ready:   make(chan struct{}),
	}
}

func (c *Client) Status() (state, label string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.state, c.label
}

func (c *Client) SetCredentials(apiID int, apiHash string) {
	c.mu.Lock()
	c.apiID = apiID
	c.apiHash = apiHash
	c.mu.Unlock()
	_ = os.MkdirAll(c.dataDir, 0o700)
	_ = os.WriteFile(filepath.Join(c.dataDir, "credentials.env"), []byte(fmt.Sprintf("%d\n%s\n", apiID, apiHash)), 0o600)
}

func (c *Client) HasCredentials() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.apiID != 0 && c.apiHash != "" {
		return true
	}
	if id := os.Getenv("GLASSCHAT_TELEGRAM_API_ID"); id != "" {
		if n, err := strconv.Atoi(id); err == nil {
			c.apiID = n
		}
	}
	if h := os.Getenv("GLASSCHAT_TELEGRAM_API_HASH"); h != "" {
		c.apiHash = h
	}
	if c.apiID != 0 && c.apiHash != "" {
		return true
	}
	// Load last saved credentials.
	data, err := os.ReadFile(filepath.Join(c.dataDir, "credentials.env"))
	if err == nil {
		lines := strings.Split(string(data), "\n")
		if len(lines) >= 2 {
			if n, err := strconv.Atoi(strings.TrimSpace(lines[0])); err == nil {
				c.apiID = n
			}
			c.apiHash = strings.TrimSpace(lines[1])
		}
	}
	return c.apiID != 0 && c.apiHash != ""
}

func (c *Client) setState(state, label string) {
	c.mu.Lock()
	c.state = state
	if label != "" {
		c.label = label
	}
	st, lb := c.state, c.label
	c.mu.Unlock()
	c.sink("session.status", map[string]any{
		"state": st, "accountLabel": lb, "protocol": "telegram",
	})
}

func (c *Client) StartPairing(ctx context.Context) error {
	if !c.HasCredentials() {
		return fmt.Errorf("Telegram api_id/api_hash missing — create an app at https://my.telegram.org and paste both values in Settings")
	}
	c.mu.Lock()
	apiID, apiHash := c.apiID, c.apiHash
	c.mu.Unlock()

	if err := os.MkdirAll(c.dataDir, 0o700); err != nil {
		return err
	}
	sessionPath := filepath.Join(c.dataDir, "telegram.session")

	c.setState("awaiting_pairing", "")

	runCtx, cancel := context.WithCancel(context.Background())
	c.mu.Lock()
	if c.cancel != nil {
		c.cancel()
	}
	c.cancel = cancel
	c.running = true
	c.ready = make(chan struct{})
	c.mu.Unlock()

	go func() {
		dispatcher := tg.NewUpdateDispatcher()
		client := telegram.NewClient(apiID, apiHash, telegram.Options{
			SessionStorage: &session.FileStorage{Path: sessionPath},
			UpdateHandler:  dispatcher,
		})

		err := client.Run(runCtx, func(ctx context.Context) error {
			status, err := client.Auth().Status(ctx)
			if err != nil {
				return err
			}
			if !status.Authorized {
				loggedIn := qrlogin.OnLoginToken(dispatcher)
				_, err := client.QR().Auth(ctx, loggedIn, func(ctx context.Context, token qrlogin.Token) error {
					c.sink("session.pair.qr", map[string]any{
						"code":     token.URL(),
						"protocol": "telegram",
					})
					return nil
				})
				if err != nil {
					c.setState("error", "")
					c.sink("session.pair.error", map[string]any{"detail": err.Error(), "protocol": "telegram"})
					return err
				}
			}

			self, err := client.Self(ctx)
			if err != nil {
				return err
			}
			label := self.Username
			if label == "" {
				label = stringsJoin(self.FirstName, self.LastName)
			}
			api := client.API()
			c.mu.Lock()
			c.api = api
			c.mu.Unlock()
			c.setState("connected", label)
			c.sink("session.pair.success", map[string]any{
				"jid":          strconv.FormatInt(self.ID, 10),
				"accountLabel": label,
				"protocol":     "telegram",
			})

			dialogs, err := api.MessagesGetDialogs(ctx, &tg.MessagesGetDialogsRequest{
				OffsetPeer: &tg.InputPeerEmpty{},
				Limit:      50,
			})
			if err == nil {
				c.ingestDialogs(dialogs)
			}

			dispatcher.OnNewMessage(func(ctx context.Context, e tg.Entities, u *tg.UpdateNewMessage) error {
				c.ingestUpdateMessage(e, u.Message)
				return nil
			})
			dispatcher.OnNewChannelMessage(func(ctx context.Context, e tg.Entities, u *tg.UpdateNewChannelMessage) error {
				c.ingestUpdateMessage(e, u.Message)
				return nil
			})

			select {
			case <-c.ready:
			default:
				close(c.ready)
			}

			<-ctx.Done()
			return ctx.Err()
		})
		if err != nil && runCtx.Err() == nil {
			c.setState("error", "")
			c.sink("session.pair.error", map[string]any{"detail": err.Error(), "protocol": "telegram"})
		}
	}()

	return nil
}

func (c *Client) Logout(ctx context.Context) error {
	c.mu.Lock()
	if c.cancel != nil {
		c.cancel()
		c.cancel = nil
	}
	c.running = false
	c.api = nil
	c.chats = nil
	c.msgs = map[string][]MessageRecord{}
	c.peers = map[string]peerRef{}
	c.mu.Unlock()
	_ = os.Remove(filepath.Join(c.dataDir, "telegram.session"))
	c.setState("disconnected", "")
	return nil
}

func (c *Client) ListChats() []ChatRecord {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]ChatRecord, len(c.chats))
	copy(out, c.chats)
	return out
}

func (c *Client) ListMessages(chatID string) []MessageRecord {
	c.mu.Lock()
	api := c.api
	ref, ok := c.peers[chatID]
	cached := append([]MessageRecord{}, c.msgs[chatID]...)
	c.mu.Unlock()

	if api == nil || !ok || ref.peer == nil {
		return cached
	}

	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	history, err := api.MessagesGetHistory(ctx, &tg.MessagesGetHistoryRequest{
		Peer:  ref.peer,
		Limit: 50,
	})
	if err != nil {
		return cached
	}

	var messages []tg.MessageClass
	switch h := history.(type) {
	case *tg.MessagesMessages:
		messages = h.Messages
	case *tg.MessagesMessagesSlice:
		messages = h.Messages
	case *tg.MessagesChannelMessages:
		messages = h.Messages
	default:
		return cached
	}

	out := make([]MessageRecord, 0, len(messages))
	// API returns newest-first; reverse for chronological UI.
	for i := len(messages) - 1; i >= 0; i-- {
		m, ok := messages[i].(*tg.Message)
		if !ok || m.Message == "" {
			continue
		}
		sender := "Telegram"
		if m.Out {
			sender = "You"
		}
		out = append(out, MessageRecord{
			ID: strconv.Itoa(m.ID), ChatID: chatID, SenderName: sender,
			Text: m.Message, Timestamp: int64(m.Date), FromMe: m.Out,
		})
	}
	if len(out) == 0 {
		return cached
	}
	c.mu.Lock()
	c.msgs[chatID] = out
	c.mu.Unlock()
	return out
}

func (c *Client) SendText(ctx context.Context, chatID, text string) (string, error) {
	c.mu.Lock()
	api := c.api
	ref, ok := c.peers[chatID]
	c.mu.Unlock()
	if api == nil {
		return "", fmt.Errorf("telegram not connected — scan the QR code first")
	}
	if !ok || ref.peer == nil {
		return "", fmt.Errorf("unknown telegram chat %s — open it from the synced chat list", chatID)
	}

	randomID := rand.New(rand.NewSource(time.Now().UnixNano())).Int63()
	updates, err := api.MessagesSendMessage(ctx, &tg.MessagesSendMessageRequest{
		Peer:     ref.peer,
		Message:  text,
		RandomID: randomID,
	})
	if err != nil {
		return "", err
	}

	id := fmt.Sprintf("%d", randomID)
	switch u := updates.(type) {
	case *tg.Updates:
		for _, up := range u.Updates {
			if m, ok := up.(*tg.UpdateMessageID); ok {
				id = strconv.Itoa(m.ID)
			}
		}
	case *tg.UpdateShortSentMessage:
		id = strconv.Itoa(u.ID)
	}

	rec := MessageRecord{
		ID: id, ChatID: chatID, SenderName: "You", Text: text,
		Timestamp: time.Now().Unix(), FromMe: true,
	}
	c.mu.Lock()
	c.msgs[chatID] = append(c.msgs[chatID], rec)
	c.mu.Unlock()
	c.sink("messages.event", map[string]any{
		"id": rec.ID, "chatId": chatID, "senderName": "You",
		"text": text, "timestamp": rec.Timestamp, "fromMe": true, "protocol": "telegram",
	})
	return id, nil
}

func (c *Client) ingestDialogs(raw tg.MessagesDialogsClass) {
	var chats []ChatRecord
	peers := map[string]peerRef{}

	handle := func(dialogs []tg.DialogClass, users map[int64]*tg.User, chatMap map[int64]tg.ChatClass) {
		for _, dlg := range dialogs {
			dialog, ok := dlg.(*tg.Dialog)
			if !ok {
				continue
			}
			id, title, kind, peer := peerMeta(dialog.Peer, users, chatMap)
			if id == "" || peer == nil {
				continue
			}
			peers[id] = peerRef{peer: peer}
			chats = append(chats, ChatRecord{
				ID: id, Title: title, Kind: kind, Protocol: "telegram",
			})
		}
	}

	switch d := raw.(type) {
	case *tg.MessagesDialogs:
		users, chatMap := indexEntities(d.Users, d.Chats)
		handle(d.Dialogs, users, chatMap)
	case *tg.MessagesDialogsSlice:
		users, chatMap := indexEntities(d.Users, d.Chats)
		handle(d.Dialogs, users, chatMap)
	}

	c.mu.Lock()
	c.chats = chats
	for k, v := range peers {
		c.peers[k] = v
	}
	c.mu.Unlock()
	c.sink("chats.updated", map[string]any{"protocol": "telegram", "chats": chats})
}

func indexEntities(usersIn []tg.UserClass, chatsIn []tg.ChatClass) (map[int64]*tg.User, map[int64]tg.ChatClass) {
	users := map[int64]*tg.User{}
	for _, u := range usersIn {
		if user, ok := u.(*tg.User); ok {
			users[user.ID] = user
		}
	}
	chatMap := map[int64]tg.ChatClass{}
	for _, ch := range chatsIn {
		switch t := ch.(type) {
		case *tg.Chat:
			chatMap[t.ID] = t
		case *tg.Channel:
			chatMap[t.ID] = t
		}
	}
	return users, chatMap
}

func (c *Client) ingestUpdateMessage(e tg.Entities, msg tg.MessageClass) {
	m, ok := msg.(*tg.Message)
	if !ok || m.Message == "" {
		return
	}
	chatID := ""
	switch p := m.PeerID.(type) {
	case *tg.PeerUser:
		chatID = fmt.Sprintf("tg:user:%d", p.UserID)
		if u, ok := e.Users[p.UserID]; ok {
			c.mu.Lock()
			c.peers[chatID] = peerRef{peer: &tg.InputPeerUser{UserID: u.ID, AccessHash: u.AccessHash}}
			c.mu.Unlock()
		}
	case *tg.PeerChat:
		chatID = fmt.Sprintf("tg:chat:%d", p.ChatID)
		c.mu.Lock()
		c.peers[chatID] = peerRef{peer: &tg.InputPeerChat{ChatID: p.ChatID}}
		c.mu.Unlock()
	case *tg.PeerChannel:
		chatID = fmt.Sprintf("tg:channel:%d", p.ChannelID)
		if ch, ok := e.Channels[p.ChannelID]; ok {
			c.mu.Lock()
			c.peers[chatID] = peerRef{peer: &tg.InputPeerChannel{ChannelID: ch.ID, AccessHash: ch.AccessHash}}
			c.mu.Unlock()
		}
	}
	if chatID == "" {
		return
	}
	sender := "Telegram"
	if m.Out {
		sender = "You"
	}
	rec := MessageRecord{
		ID: strconv.Itoa(m.ID), ChatID: chatID, SenderName: sender,
		Text: m.Message, Timestamp: int64(m.Date), FromMe: m.Out,
	}
	c.mu.Lock()
	c.msgs[chatID] = append(c.msgs[chatID], rec)
	c.mu.Unlock()
	c.sink("messages.event", map[string]any{
		"id": rec.ID, "chatId": chatID, "senderName": sender,
		"text": rec.Text, "timestamp": rec.Timestamp, "fromMe": m.Out, "protocol": "telegram",
	})
}

func peerMeta(peer tg.PeerClass, users map[int64]*tg.User, chats map[int64]tg.ChatClass) (id, title, kind string, input tg.InputPeerClass) {
	switch p := peer.(type) {
	case *tg.PeerUser:
		id = fmt.Sprintf("tg:user:%d", p.UserID)
		kind = "individual"
		if u := users[p.UserID]; u != nil {
			title = stringsJoin(u.FirstName, u.LastName)
			if title == "" {
				title = u.Username
			}
			input = &tg.InputPeerUser{UserID: u.ID, AccessHash: u.AccessHash}
		}
	case *tg.PeerChat:
		id = fmt.Sprintf("tg:chat:%d", p.ChatID)
		kind = "group"
		input = &tg.InputPeerChat{ChatID: p.ChatID}
		if ch, ok := chats[p.ChatID].(*tg.Chat); ok {
			title = ch.Title
		}
	case *tg.PeerChannel:
		id = fmt.Sprintf("tg:channel:%d", p.ChannelID)
		kind = "group"
		if ch, ok := chats[p.ChannelID].(*tg.Channel); ok {
			title = ch.Title
			input = &tg.InputPeerChannel{ChannelID: ch.ID, AccessHash: ch.AccessHash}
		}
	}
	if title == "" {
		title = id
	}
	return
}

func stringsJoin(a, b string) string {
	if a == "" {
		return b
	}
	if b == "" {
		return a
	}
	return a + " " + b
}
