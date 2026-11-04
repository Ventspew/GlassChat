package wa

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
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
		state:   "disconnected",
	}
}

func (c *Client) Status() (state, label, detail string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.state, c.label, ""
}

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
		c.sink("session.pair.success", map[string]any{
			"jid":          client.Store.ID.String(),
			"accountLabel": displayLabel(client),
		})
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
				c.sink("session.pair.qr", map[string]any{"code": item.Code})
			case "success":
				c.setState("connected", displayLabel(client))
				jid := ""
				if client.Store.ID != nil {
					jid = client.Store.ID.String()
				}
				c.sink("session.pair.success", map[string]any{
					"jid":          jid,
					"accountLabel": displayLabel(client),
				})
			case "timeout":
				c.setState("disconnected", "")
				c.sink("session.pair.timeout", map[string]any{"detail": "QR code expired"})
			default:
				if item.Error != nil {
					c.setState("error", "")
					c.sink("session.pair.error", map[string]any{"detail": item.Error.Error()})
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
		return nil
	}
	c.setState("connecting", displayLabel(client))
	if err := client.Connect(); err != nil {
		c.setState("error", "")
		return err
	}
	c.setState("connected", displayLabel(client))
	return nil
}

func (c *Client) Logout(ctx context.Context) error {
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()
	if client == nil {
		c.setState("disconnected", "")
		return nil
	}
	if client.IsLoggedIn() {
		err := client.Logout(ctx)
		c.mu.Lock()
		c.client = nil
		c.mu.Unlock()
		c.setState("disconnected", "")
		return err
	}
	client.Disconnect()
	c.mu.Lock()
	c.client = nil
	c.mu.Unlock()
	// Wipe store file so a fresh QR can be generated.
	_ = os.Remove(filepath.Join(c.dataDir, "whatsmeow.db"))
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
	return resp.ID, nil
}

func (c *Client) handleEvent(evt any) {
	switch v := evt.(type) {
	case *events.Message:
		text := ""
		if v.Message != nil {
			text = v.Message.GetConversation()
			if text == "" && v.Message.GetExtendedTextMessage() != nil {
				text = v.Message.GetExtendedTextMessage().GetText()
			}
		}
		if text == "" {
			return
		}
		sender := v.Info.PushName
		if sender == "" {
			sender = v.Info.Sender.User
		}
		c.sink("messages.event", map[string]any{
			"id":         v.Info.ID,
			"chatId":     v.Info.Chat.String(),
			"senderName": sender,
			"text":       text,
			"timestamp":  v.Info.Timestamp.Unix(),
			"fromMe":     v.Info.IsFromMe,
		})
	case *events.Connected:
		c.mu.Lock()
		client := c.client
		c.mu.Unlock()
		c.setState("connected", displayLabel(client))
	case *events.Disconnected:
		c.setState("disconnected", "")
	case *events.LoggedOut:
		c.setState("disconnected", "")
		c.sink("session.pair.error", map[string]any{"detail": "Logged out from phone"})
	}
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

// KeepAlive helps the process stay responsive while waiting for QR scans.
func KeepAlive() { time.Sleep(time.Millisecond) }
