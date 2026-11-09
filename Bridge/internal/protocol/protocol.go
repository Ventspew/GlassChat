package protocol

import "encoding/json"

// Envelope is a single NDJSON line shared with the Swift client.
type Envelope struct {
	ID      string          `json:"id"`
	Type    string          `json:"type"` // request | response | event
	Method  string          `json:"method"`
	OK      *bool           `json:"ok,omitempty"`
	Error   *string         `json:"error,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

const (
	TypeRequest  = "request"
	TypeResponse = "response"
	TypeEvent    = "event"
)

const (
	MethodSessionStatus    = "session.status"
	MethodSessionPairStart = "session.pair.start"
	MethodSessionLogout    = "session.logout"
	MethodSessionConnect   = "session.connect"
	MethodChatsList        = "chats.list"
	MethodMessagesList     = "messages.list"
	MethodMessagesSendText = "messages.send.text"
	MethodMessagesMarkRead = "messages.markRead"

	EventPairQR      = "session.pair.qr"
	EventPairSuccess = "session.pair.success"
	EventPairTimeout = "session.pair.timeout"
	EventPairError   = "session.pair.error"
	EventStatus      = "session.status"
	EventMessage     = "messages.event"
	EventChatsUpdated = "chats.updated"
)

type SessionStatusPayload struct {
	State        string `json:"state"`
	AccountLabel string `json:"accountLabel,omitempty"`
	Detail       string `json:"detail,omitempty"`
}

type PairQRPayload struct {
	Code string `json:"code"`
}

type PairSuccessPayload struct {
	JID          string `json:"jid"`
	AccountLabel string `json:"accountLabel"`
}

type SendTextPayload struct {
	ChatID    string  `json:"chatId"`
	Text      string  `json:"text"`
	ReplyToID *string `json:"replyToId"`
}

type MessageEventPayload struct {
	ID         string `json:"id"`
	ChatID     string `json:"chatId"`
	SenderName string `json:"senderName"`
	Text       string `json:"text"`
	Timestamp  int64  `json:"timestamp"`
	FromMe     bool   `json:"fromMe"`
}

type ChatSummaryPayload struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Kind        string `json:"kind"`
	LastPreview string `json:"lastPreview"`
	UnreadCount int    `json:"unreadCount"`
	IsPinned    bool   `json:"isPinned"`
}
