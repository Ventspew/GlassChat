package telegram

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"sync"

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
	running bool
	cancel  context.CancelFunc
}

func New(dataDir string, sink EventSink) *Client {
	return &Client{
		dataDir: dataDir,
		sink:    sink,
		state:   "disconnected",
		msgs:    map[string][]MessageRecord{},
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
}

func (c *Client) HasCredentials() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.apiID != 0 && c.apiHash != "" {
		return true
	}
	// Fall back to environment (my.telegram.org credentials).
	if id := os.Getenv("GLASSCHAT_TELEGRAM_API_ID"); id != "" {
		if n, err := strconv.Atoi(id); err == nil {
			c.apiID = n
		}
	}
	if h := os.Getenv("GLASSCHAT_TELEGRAM_API_HASH"); h != "" {
		c.apiHash = h
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
		return fmt.Errorf("Telegram api_id/api_hash missing — set in Settings or GLASSCHAT_TELEGRAM_API_ID/HASH (from my.telegram.org)")
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
				auth, err := client.QR().Auth(ctx, loggedIn, func(ctx context.Context, token qrlogin.Token) error {
					// Telegram QR payload is a tg:// URL shown as QR.
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
				_ = auth
			}

			self, err := client.Self(ctx)
			if err != nil {
				return err
			}
			label := self.Username
			if label == "" {
				label = stringsJoin(self.FirstName, self.LastName)
			}
			c.setState("connected", label)
			c.sink("session.pair.success", map[string]any{
				"jid":          strconv.FormatInt(self.ID, 10),
				"accountLabel": label,
				"protocol":     "telegram",
			})

			api := client.API()
			dialogs, err := api.MessagesGetDialogs(ctx, &tg.MessagesGetDialogsRequest{
				OffsetPeer: &tg.InputPeerEmpty{},
				Limit:      40,
			})
			if err == nil {
				c.ingestDialogs(dialogs)
			}

			dispatcher.OnNewMessage(func(ctx context.Context, e tg.Entities, u *tg.UpdateNewMessage) error {
				c.ingestUpdateMessage(e, u.Message)
				return nil
			})

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
	c.chats = nil
	c.msgs = map[string][]MessageRecord{}
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
	defer c.mu.Unlock()
	return append([]MessageRecord{}, c.msgs[chatID]...)
}

func (c *Client) SendText(ctx context.Context, chatID, text string) (string, error) {
	return "", fmt.Errorf("telegram send requires an active gotd session — reconnect after pairing")
}

func (c *Client) ingestDialogs(raw tg.MessagesDialogsClass) {
	var chats []ChatRecord
	switch d := raw.(type) {
	case *tg.MessagesDialogs:
		users := map[int64]*tg.User{}
		for _, u := range d.Users {
			if user, ok := u.(*tg.User); ok {
				users[user.ID] = user
			}
		}
		chatMap := map[int64]tg.ChatClass{}
		for _, ch := range d.Chats {
			switch t := ch.(type) {
			case *tg.Chat:
				chatMap[t.ID] = t
			case *tg.Channel:
				chatMap[t.ID] = t
			}
		}
		for _, dlg := range d.Dialogs {
			dialog, ok := dlg.(*tg.Dialog)
			if !ok {
				continue
			}
			id, title, kind := peerMeta(dialog.Peer, users, chatMap)
			if id == "" {
				continue
			}
			chats = append(chats, ChatRecord{
				ID: id, Title: title, Kind: kind, Protocol: "telegram",
			})
		}
	case *tg.MessagesDialogsSlice:
		users := map[int64]*tg.User{}
		for _, u := range d.Users {
			if user, ok := u.(*tg.User); ok {
				users[user.ID] = user
			}
		}
		chatMap := map[int64]tg.ChatClass{}
		for _, ch := range d.Chats {
			switch t := ch.(type) {
			case *tg.Chat:
				chatMap[t.ID] = t
			case *tg.Channel:
				chatMap[t.ID] = t
			}
		}
		for _, dlg := range d.Dialogs {
			dialog, ok := dlg.(*tg.Dialog)
			if !ok {
				continue
			}
			id, title, kind := peerMeta(dialog.Peer, users, chatMap)
			if id == "" {
				continue
			}
			chats = append(chats, ChatRecord{
				ID: id, Title: title, Kind: kind, Protocol: "telegram",
			})
		}
	}
	c.mu.Lock()
	c.chats = chats
	c.mu.Unlock()
	c.sink("chats.updated", map[string]any{"protocol": "telegram", "chats": chats})
}

func (c *Client) ingestUpdateMessage(e tg.Entities, msg tg.MessageClass) {
	m, ok := msg.(*tg.Message)
	if !ok || m.Message == "" {
		return
	}
	chatID := fmt.Sprintf("%d", m.PeerID)
	// Prefer concrete peer ids when available.
	switch p := m.PeerID.(type) {
	case *tg.PeerUser:
		chatID = fmt.Sprintf("tg:user:%d", p.UserID)
	case *tg.PeerChat:
		chatID = fmt.Sprintf("tg:chat:%d", p.ChatID)
	case *tg.PeerChannel:
		chatID = fmt.Sprintf("tg:channel:%d", p.ChannelID)
	}
	rec := MessageRecord{
		ID:         strconv.Itoa(m.ID),
		ChatID:     chatID,
		SenderName: "Telegram",
		Text:       m.Message,
		Timestamp:  int64(m.Date),
		FromMe:     m.Out,
	}
	c.mu.Lock()
	c.msgs[chatID] = append(c.msgs[chatID], rec)
	c.mu.Unlock()
	c.sink("messages.event", map[string]any{
		"id": rec.ID, "chatId": rec.ChatID, "senderName": rec.SenderName,
		"text": rec.Text, "timestamp": rec.Timestamp, "fromMe": rec.FromMe, "protocol": "telegram",
	})
}

func peerMeta(peer tg.PeerClass, users map[int64]*tg.User, chats map[int64]tg.ChatClass) (id, title, kind string) {
	switch p := peer.(type) {
	case *tg.PeerUser:
		id = fmt.Sprintf("tg:user:%d", p.UserID)
		kind = "individual"
		if u := users[p.UserID]; u != nil {
			title = stringsJoin(u.FirstName, u.LastName)
			if title == "" {
				title = u.Username
			}
		}
	case *tg.PeerChat:
		id = fmt.Sprintf("tg:chat:%d", p.ChatID)
		kind = "group"
		if ch, ok := chats[p.ChatID].(*tg.Chat); ok {
			title = ch.Title
		}
	case *tg.PeerChannel:
		id = fmt.Sprintf("tg:channel:%d", p.ChannelID)
		kind = "group"
		if ch, ok := chats[p.ChannelID].(*tg.Channel); ok {
			title = ch.Title
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
