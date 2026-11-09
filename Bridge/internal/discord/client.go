package discord

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"github.com/bwmarrin/discordgo"
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

// Client uses discordgo. Prefer a BOT token (Discord ToS). User tokens are
// optional and explicitly risky.
type Client struct {
	dataDir string
	sink    EventSink

	mu      sync.Mutex
	token   string
	isBot   bool
	state   string
	label   string
	session *discordgo.Session
	chats   []ChatRecord
	msgs    map[string][]MessageRecord
}

func New(dataDir string, sink EventSink) *Client {
	return &Client{
		dataDir: dataDir,
		sink:    sink,
		state:   "disconnected",
		msgs:    map[string][]MessageRecord{},
	}
}

func (c *Client) Status() (string, string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.state, c.label
}

func (c *Client) SetToken(token string, bot bool) {
	c.mu.Lock()
	c.token = token
	c.isBot = bot
	c.mu.Unlock()
	_ = os.MkdirAll(c.dataDir, 0o700)
	_ = os.WriteFile(filepath.Join(c.dataDir, "token.flag"), []byte(fmt.Sprintf("bot=%v", bot)), 0o600)
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
		"state": st, "accountLabel": lb, "protocol": "discord",
	})
}

func (c *Client) Connect(ctxToken string, asBot bool) error {
	token := ctxToken
	if token == "" {
		token = os.Getenv("GLASSCHAT_DISCORD_TOKEN")
	}
	if token == "" {
		c.mu.Lock()
		token = c.token
		asBot = c.isBot
		c.mu.Unlock()
	}
	if token == "" {
		return fmt.Errorf("Discord token missing — paste a bot token in Settings (recommended) or set GLASSCHAT_DISCORD_TOKEN")
	}

	c.setState("connecting", "")
	// Android mods (Aliucord / Vendetta / Revenge) patch the official Discord app
	// and keep a normal user session. For a standalone API client the closest
	// equivalent is a raw user token (no "Bot " prefix). That violates Discord
	// ToS — only enable when the user explicitly turns bot-mode off.
	prefix := token
	if asBot {
		if len(token) < 4 || token[:4] != "Bot " {
			prefix = "Bot " + token
		}
	} else {
		// Strip accidental Bot prefix for user-token mode.
		if len(token) > 4 && token[:4] == "Bot " {
			prefix = token[4:]
		}
	}

	session, err := discordgo.New(prefix)
	if err != nil {
		c.setState("error", "")
		return err
	}
	session.Identify.Intents = discordgo.IntentsGuilds | discordgo.IntentsGuildMessages | discordgo.IntentsMessageContent | discordgo.IntentsDirectMessages

	session.AddHandler(func(s *discordgo.Session, r *discordgo.Ready) {
		label := r.User.Username
		c.setState("connected", label)
		c.sink("session.pair.success", map[string]any{
			"jid": r.User.ID, "accountLabel": label, "protocol": "discord",
		})
		c.refreshGuilds(s)
	})
	session.AddHandler(func(s *discordgo.Session, m *discordgo.MessageCreate) {
		if m.Author == nil {
			return
		}
		chatID := "dc:" + m.ChannelID
		rec := MessageRecord{
			ID: m.ID, ChatID: chatID, SenderName: m.Author.Username,
			Text: m.Content, FromMe: m.Author.ID == s.State.User.ID,
		}
		c.mu.Lock()
		c.msgs[chatID] = append(c.msgs[chatID], rec)
		c.mu.Unlock()
		c.sink("messages.event", map[string]any{
			"id": rec.ID, "chatId": chatID, "senderName": rec.SenderName,
			"text": rec.Text, "fromMe": rec.FromMe, "protocol": "discord",
		})
	})

	if err := session.Open(); err != nil {
		c.setState("error", "")
		return err
	}

	c.mu.Lock()
	c.session = session
	c.token = token
	c.isBot = asBot
	c.mu.Unlock()
	return nil
}

func (c *Client) refreshGuilds(s *discordgo.Session) {
	var chats []ChatRecord
	for _, g := range s.State.Guilds {
		channels, err := s.GuildChannels(g.ID)
		if err != nil {
			continue
		}
		for _, ch := range channels {
			if ch.Type != discordgo.ChannelTypeGuildText {
				continue
			}
			chats = append(chats, ChatRecord{
				ID:       "dc:" + ch.ID,
				Title:    fmt.Sprintf("#%s · %s", ch.Name, g.Name),
				Kind:     "group",
				Protocol: "discord",
			})
		}
	}
	c.mu.Lock()
	c.chats = chats
	c.mu.Unlock()
	c.sink("chats.updated", map[string]any{"protocol": "discord", "chats": chats})
}

func (c *Client) Logout() error {
	c.mu.Lock()
	sess := c.session
	c.session = nil
	c.chats = nil
	c.msgs = map[string][]MessageRecord{}
	c.mu.Unlock()
	if sess != nil {
		_ = sess.Close()
	}
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

func (c *Client) SendText(chatID, text string) (string, error) {
	c.mu.Lock()
	sess := c.session
	c.mu.Unlock()
	if sess == nil {
		return "", fmt.Errorf("discord not connected")
	}
	id := chatID
	if len(id) > 3 && id[:3] == "dc:" {
		id = id[3:]
	}
	msg, err := sess.ChannelMessageSend(id, text)
	if err != nil {
		return "", err
	}
	return msg.ID, nil
}
