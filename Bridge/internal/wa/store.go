package wa

import (
	"sort"
	"sync"
	"time"
)

type ChatRecord struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Kind        string `json:"kind"` // individual | group
	LastPreview string `json:"lastPreview"`
	LastActivity int64 `json:"lastActivity"`
	UnreadCount int    `json:"unreadCount"`
	IsPinned    bool   `json:"isPinned"`
	Protocol    string `json:"protocol"`
}

type MessageRecord struct {
	ID         string `json:"id"`
	ChatID     string `json:"chatId"`
	SenderName string `json:"senderName"`
	Text       string `json:"text"`
	Timestamp  int64  `json:"timestamp"`
	FromMe     bool   `json:"fromMe"`
}

type MemoryStore struct {
	mu       sync.RWMutex
	chats    map[string]*ChatRecord
	messages map[string][]MessageRecord // chatID -> messages
	names    map[string]string          // jid -> display name
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		chats:    map[string]*ChatRecord{},
		messages: map[string][]MessageRecord{},
		names:    map[string]string{},
	}
}

func (s *MemoryStore) SetName(jid, name string) {
	if jid == "" || name == "" {
		return
	}
	s.mu.Lock()
	s.names[jid] = name
	if chat, ok := s.chats[jid]; ok && (chat.Title == "" || chat.Title == jid) {
		chat.Title = name
	}
	s.mu.Unlock()
}

func (s *MemoryStore) Name(jid string) string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.names[jid]
}

func (s *MemoryStore) UpsertChat(chat ChatRecord) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if chat.Protocol == "" {
		chat.Protocol = "whatsapp"
	}
	if existing, ok := s.chats[chat.ID]; ok {
		if chat.Title != "" {
			existing.Title = chat.Title
		}
		if chat.LastPreview != "" {
			existing.LastPreview = chat.LastPreview
		}
		if chat.LastActivity > existing.LastActivity {
			existing.LastActivity = chat.LastActivity
		}
		existing.UnreadCount = chat.UnreadCount
		existing.IsPinned = chat.IsPinned
		existing.Kind = chat.Kind
		return
	}
	if chat.Title == "" {
		if n := s.names[chat.ID]; n != "" {
			chat.Title = n
		} else {
			chat.Title = chat.ID
		}
	}
	cp := chat
	s.chats[chat.ID] = &cp
}

func (s *MemoryStore) AppendMessage(msg MessageRecord) {
	s.mu.Lock()
	defer s.mu.Unlock()

	list := s.messages[msg.ChatID]
	for _, existing := range list {
		if existing.ID == msg.ID {
			return
		}
	}
	s.messages[msg.ChatID] = append(list, msg)

	chat, ok := s.chats[msg.ChatID]
	if !ok {
		title := s.names[msg.ChatID]
		if title == "" {
			title = msg.SenderName
		}
		if title == "" {
			title = msg.ChatID
		}
		chat = &ChatRecord{
			ID:       msg.ChatID,
			Title:    title,
			Kind:     "individual",
			Protocol: "whatsapp",
		}
		s.chats[msg.ChatID] = chat
	}
	chat.LastPreview = msg.Text
	if msg.Timestamp > chat.LastActivity {
		chat.LastActivity = msg.Timestamp
	}
	if !msg.FromMe {
		chat.UnreadCount++
	}
}

func (s *MemoryStore) ListChats() []ChatRecord {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]ChatRecord, 0, len(s.chats))
	for _, chat := range s.chats {
		out = append(out, *chat)
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].LastActivity > out[j].LastActivity
	})
	return out
}

func (s *MemoryStore) ListMessages(chatID string, limit int) []MessageRecord {
	s.mu.RLock()
	defer s.mu.RUnlock()
	list := s.messages[chatID]
	if limit <= 0 || limit > len(list) {
		limit = len(list)
	}
	start := len(list) - limit
	if start < 0 {
		start = 0
	}
	out := make([]MessageRecord, limit)
	copy(out, list[start:])
	return out
}

func (s *MemoryStore) Clear() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.chats = map[string]*ChatRecord{}
	s.messages = map[string][]MessageRecord{}
	s.names = map[string]string{}
}

func nowUnix() int64 { return time.Now().Unix() }
