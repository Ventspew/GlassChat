package discord

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

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

// Client uses discordgo.
// Full personal login = user token (same idea as Aliucord/Vendetta session), ToS-risky.
// Bot token remains available for compliant bots.
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
	token = strings.TrimSpace(token)
	c.mu.Lock()
	c.token = token
	c.isBot = bot
	c.mu.Unlock()
	_ = os.MkdirAll(c.dataDir, 0o700)
	mode := "user"
	if bot {
		mode = "bot"
	}
	_ = os.WriteFile(filepath.Join(c.dataDir, "token.txt"), []byte(token), 0o600)
	_ = os.WriteFile(filepath.Join(c.dataDir, "mode.txt"), []byte(mode), 0o600)
}

func (c *Client) loadSavedToken() (token string, bot bool) {
	c.mu.Lock()
	token = c.token
	bot = c.isBot
	c.mu.Unlock()
	if token != "" {
		return token, bot
	}
	if env := os.Getenv("GLASSCHAT_DISCORD_TOKEN"); env != "" {
		return env, os.Getenv("GLASSCHAT_DISCORD_BOT") != "0"
	}
	b, err := os.ReadFile(filepath.Join(c.dataDir, "token.txt"))
	if err != nil {
		return "", true
	}
	mode, _ := os.ReadFile(filepath.Join(c.dataDir, "mode.txt"))
	return strings.TrimSpace(string(b)), strings.TrimSpace(string(mode)) != "user"
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
	token := strings.TrimSpace(ctxToken)
	if token == "" {
		var savedBot bool
		token, savedBot = c.loadSavedToken()
		if ctxToken == "" && token != "" {
			asBot = savedBot
		}
	}
	if token == "" {
		return fmt.Errorf("Discord token missing — paste your account token in Settings → Connection (user login) or a bot token")
	}

	c.SetToken(token, asBot)
	c.setState("connecting", "")

	prefix := token
	if asBot {
		if !strings.HasPrefix(token, "Bot ") {
			prefix = "Bot " + token
		}
	} else if strings.HasPrefix(token, "Bot ") {
		prefix = strings.TrimPrefix(token, "Bot ")
	}

	session, err := discordgo.New(prefix)
	if err != nil {
		c.setState("error", "")
		return err
	}

	// User accounts: don't force privileged bot intents.
	if asBot {
		session.Identify.Intents = discordgo.IntentsGuilds |
			discordgo.IntentsGuildMessages |
			discordgo.IntentsMessageContent |
			discordgo.IntentsDirectMessages
	} else {
		session.Identify.Intents = discordgo.IntentsAllWithoutPrivileged |
			discordgo.IntentDirectMessages |
			discordgo.IntentGuildMessages |
			discordgo.IntentMessageContent
	}

	session.AddHandler(func(s *discordgo.Session, r *discordgo.Ready) {
		label := r.User.Username
		if r.User.Discriminator != "" && r.User.Discriminator != "0" {
			label = r.User.Username + "#" + r.User.Discriminator
		}
		c.setState("connected", label)
		c.sink("session.pair.success", map[string]any{
			"jid": r.User.ID, "accountLabel": label, "protocol": "discord",
		})
		c.refreshChats(s, asBot)
	})
	session.AddHandler(func(s *discordgo.Session, m *discordgo.MessageCreate) {
		if m.Author == nil || m.Content == "" {
			return
		}
		chatID := "dc:" + m.ChannelID
		fromMe := s.State != nil && s.State.User != nil && m.Author.ID == s.State.User.ID
		rec := MessageRecord{
			ID: m.ID, ChatID: chatID, SenderName: m.Author.Username,
			Text: m.Content, Timestamp: time.Now().Unix(), FromMe: fromMe,
		}
		c.mu.Lock()
		c.msgs[chatID] = append(c.msgs[chatID], rec)
		c.mu.Unlock()
		c.sink("messages.event", map[string]any{
			"id": rec.ID, "chatId": chatID, "senderName": rec.SenderName,
			"text": rec.Text, "timestamp": rec.Timestamp, "fromMe": fromMe, "protocol": "discord",
		})
	})

	if err := session.Open(); err != nil {
		c.setState("error", "")
		return fmt.Errorf("discord gateway open failed: %w", err)
	}

	c.mu.Lock()
	c.session = session
	c.mu.Unlock()
	return nil
}

func (c *Client) refreshChats(s *discordgo.Session, asBot bool) {
	var chats []ChatRecord

	// DMs / group DMs from gateway state — essential for full personal login.
	if s.State != nil {
		for _, ch := range s.State.PrivateChannels {
			title := "Direct Message"
			kind := "individual"
			switch ch.Type {
			case discordgo.ChannelTypeDM:
				if len(ch.Recipients) > 0 {
					title = ch.Recipients[0].Username
				}
			case discordgo.ChannelTypeGroupDM:
				kind = "group"
				names := make([]string, 0, len(ch.Recipients))
				for _, r := range ch.Recipients {
					names = append(names, r.Username)
				}
				if len(names) > 0 {
					title = strings.Join(names, ", ")
				} else if ch.Name != "" {
					title = ch.Name
				} else {
					title = "Group DM"
				}
			default:
				continue
			}
			chats = append(chats, ChatRecord{
				ID: "dc:" + ch.ID, Title: title, Kind: kind, Protocol: "discord",
			})
		}
	}

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
	_ = os.Remove(filepath.Join(c.dataDir, "token.txt"))
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
	id := strings.TrimPrefix(chatID, "dc:")
	c.mu.Lock()
	sess := c.session
	cached := append([]MessageRecord{}, c.msgs[chatID]...)
	c.mu.Unlock()

	if sess == nil {
		return cached
	}
	raw, err := sess.ChannelMessages(id, 50, "", "", "")
	if err != nil {
		return cached
	}
	out := make([]MessageRecord, 0, len(raw))
	selfID := ""
	if sess.State != nil && sess.State.User != nil {
		selfID = sess.State.User.ID
	}
	// API returns newest-first; reverse for chronological UI.
	for i := len(raw) - 1; i >= 0; i-- {
		m := raw[i]
		if m.Content == "" {
			continue
		}
		name := "User"
		fromMe := false
		if m.Author != nil {
			name = m.Author.Username
			fromMe = m.Author.ID == selfID
		}
		ts := time.Now().Unix()
		if !m.Timestamp.IsZero() {
			ts = m.Timestamp.Unix()
		} else if t, err := discordgo.SnowflakeTimestamp(m.ID); err == nil {
			ts = t.Unix()
		}
		out = append(out, MessageRecord{
			ID: m.ID, ChatID: chatID, SenderName: name,
			Text: m.Content, Timestamp: ts, FromMe: fromMe,
		})
	}
	c.mu.Lock()
	c.msgs[chatID] = out
	c.mu.Unlock()
	return out
}

func (c *Client) SendText(chatID, text string) (string, error) {
	c.mu.Lock()
	sess := c.session
	c.mu.Unlock()
	if sess == nil {
		return "", fmt.Errorf("discord not connected — log in with your token first")
	}
	id := strings.TrimPrefix(chatID, "dc:")
	msg, err := sess.ChannelMessageSend(id, text)
	if err != nil {
		return "", err
	}
	rec := MessageRecord{
		ID: msg.ID, ChatID: chatID, SenderName: "You",
		Text: text, Timestamp: time.Now().Unix(), FromMe: true,
	}
	c.mu.Lock()
	c.msgs[chatID] = append(c.msgs[chatID], rec)
	c.mu.Unlock()
	c.sink("messages.event", map[string]any{
		"id": rec.ID, "chatId": chatID, "senderName": "You",
		"text": text, "timestamp": rec.Timestamp, "fromMe": true, "protocol": "discord",
	})
	return msg.ID, nil
}
