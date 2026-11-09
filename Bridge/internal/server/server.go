package server

import (
	"bufio"
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"sync"

	"github.com/glasschat/bridge/internal/discord"
	"github.com/glasschat/bridge/internal/protocol"
	"github.com/glasschat/bridge/internal/telegram"
	"github.com/glasschat/bridge/internal/wa"
	"github.com/google/uuid"
)

type Server struct {
	SocketPath string
	Token      string
	DataDir    string

	wa *wa.Client
	tg *telegram.Client
	dc *discord.Client

	mu          sync.Mutex
	subscribers map[net.Conn]struct{}
}

func New(socketPath, token, dataDir string) *Server {
	s := &Server{
		SocketPath:  socketPath,
		Token:       token,
		DataDir:     dataDir,
		subscribers: map[net.Conn]struct{}{},
	}
	s.wa = wa.New(filepath.Join(dataDir, "whatsmeow"), s.broadcast)
	s.tg = telegram.New(filepath.Join(dataDir, "telegram"), s.broadcast)
	s.dc = discord.New(filepath.Join(dataDir, "discord"), s.broadcast)
	return s
}

func (s *Server) Run(ctx context.Context) error {
	if err := os.MkdirAll(filepath.Dir(s.SocketPath), 0o700); err != nil {
		return err
	}
	if err := os.MkdirAll(s.DataDir, 0o700); err != nil {
		return err
	}
	_ = os.Remove(s.SocketPath)

	ln, err := net.Listen("unix", s.SocketPath)
	if err != nil {
		return err
	}
	defer ln.Close()
	_ = os.Chmod(s.SocketPath, 0o600)

	go func() { _ = s.wa.EnsureStarted(ctx) }()

	go func() {
		<-ctx.Done()
		_ = ln.Close()
	}()

	for {
		conn, err := ln.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return nil
			default:
				return err
			}
		}
		go s.handleConn(ctx, conn)
	}
}

func (s *Server) handleConn(ctx context.Context, conn net.Conn) {
	defer conn.Close()
	s.mu.Lock()
	s.subscribers[conn] = struct{}{}
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(s.subscribers, conn)
		s.mu.Unlock()
	}()

	state, label, _ := s.wa.Status()
	s.write(conn, eventEnvelope(protocol.EventStatus, protocol.SessionStatusPayload{
		State: state, AccountLabel: label,
	}))

	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		var env protocol.Envelope
		if err := json.Unmarshal(scanner.Bytes(), &env); err != nil {
			s.write(conn, errorResponse("", "invalid_json", err.Error()))
			continue
		}
		s.write(conn, s.dispatch(ctx, env))
	}
}

func (s *Server) dispatch(ctx context.Context, env protocol.Envelope) protocol.Envelope {
	protoName := payloadString(env.Payload, "protocol")
	if protoName == "" {
		protoName = "whatsapp"
	}

	switch env.Method {
	case protocol.MethodSessionStatus:
		var state, label string
		switch protoName {
		case "telegram":
			state, label = s.tg.Status()
		case "discord":
			state, label = s.dc.Status()
		default:
			state, label, _ = s.wa.Status()
		}
		payload, _ := json.Marshal(protocol.SessionStatusPayload{State: state, AccountLabel: label})
		return okResponse(env, payload)

	case protocol.MethodSessionPairStart:
		switch protoName {
		case "telegram":
			if id := payloadString(env.Payload, "apiId"); id != "" {
				n, _ := strconv.Atoi(id)
				s.tg.SetCredentials(n, payloadString(env.Payload, "apiHash"))
			}
			if err := s.tg.StartPairing(ctx); err != nil {
				return errResponse(env, err.Error())
			}
		case "discord":
			token := payloadString(env.Payload, "token")
			asBot := payloadBool(env.Payload, "bot", true)
			if token != "" {
				s.dc.SetToken(token, asBot)
			}
			if err := s.dc.Connect(token, asBot); err != nil {
				return errResponse(env, err.Error())
			}
		default:
			if err := s.wa.StartPairing(ctx); err != nil {
				return errResponse(env, err.Error())
			}
		}
		payload, _ := json.Marshal(protocol.SessionStatusPayload{State: "awaiting_pairing"})
		return okResponse(env, payload)

	case protocol.MethodSessionConnect:
		if err := s.wa.ConnectExisting(ctx); err != nil {
			return errResponse(env, err.Error())
		}
		state, label, _ := s.wa.Status()
		payload, _ := json.Marshal(protocol.SessionStatusPayload{State: state, AccountLabel: label})
		return okResponse(env, payload)

	case protocol.MethodSessionLogout:
		switch protoName {
		case "telegram":
			_ = s.tg.Logout(ctx)
		case "discord":
			_ = s.dc.Logout()
		default:
			_ = s.wa.Logout(ctx)
		}
		payload, _ := json.Marshal(protocol.SessionStatusPayload{State: "disconnected"})
		return okResponse(env, payload)

	case protocol.MethodChatsList:
		var chats any
		switch protoName {
		case "telegram":
			chats = s.tg.ListChats()
		case "discord":
			chats = s.dc.ListChats()
		case "all":
			chats = mergeChats(s.wa.ListChats(), s.tg.ListChats(), s.dc.ListChats())
		default:
			chats = s.wa.ListChats()
		}
		payload, _ := json.Marshal(map[string]any{"chats": chats})
		return okResponse(env, payload)

	case protocol.MethodMessagesList:
		chatID := payloadString(env.Payload, "chatId")
		var messages any
		switch {
		case len(chatID) > 3 && chatID[:3] == "tg:":
			messages = s.tg.ListMessages(chatID)
		case len(chatID) > 3 && chatID[:3] == "dc:":
			messages = s.dc.ListMessages(chatID)
		default:
			messages = s.wa.ListMessages(chatID, 200)
		}
		payload, _ := json.Marshal(map[string]any{"messages": messages})
		return okResponse(env, payload)

	case protocol.MethodMessagesSendText:
		var req protocol.SendTextPayload
		if err := json.Unmarshal(env.Payload, &req); err != nil {
			return errResponse(env, "invalid payload")
		}
		var id string
		var err error
		switch {
		case len(req.ChatID) > 3 && req.ChatID[:3] == "tg:":
			id, err = s.tg.SendText(ctx, req.ChatID, req.Text)
		case len(req.ChatID) > 3 && req.ChatID[:3] == "dc:":
			id, err = s.dc.SendText(req.ChatID, req.Text)
		default:
			id, err = s.wa.SendText(ctx, req.ChatID, req.Text)
		}
		if err != nil {
			return errResponse(env, err.Error())
		}
		payload, _ := json.Marshal(map[string]string{"id": id})
		return okResponse(env, payload)

	default:
		return errResponse(env, "unknown method")
	}
}

func mergeChats(parts ...any) []map[string]any {
	out := []map[string]any{}
	for _, part := range parts {
		b, _ := json.Marshal(part)
		var list []map[string]any
		_ = json.Unmarshal(b, &list)
		out = append(out, list...)
	}
	return out
}

func payloadString(raw json.RawMessage, key string) string {
	if len(raw) == 0 {
		return ""
	}
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		return ""
	}
	if v, ok := m[key].(string); ok {
		return v
	}
	if v, ok := m[key].(float64); ok {
		return strconv.FormatInt(int64(v), 10)
	}
	return ""
}

func payloadBool(raw json.RawMessage, key string, fallback bool) bool {
	if len(raw) == 0 {
		return fallback
	}
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		return fallback
	}
	if v, ok := m[key].(bool); ok {
		return v
	}
	return fallback
}

func (s *Server) broadcast(method string, payload any) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return
	}
	env := protocol.Envelope{
		ID: uuid.NewString(), Type: protocol.TypeEvent, Method: method, Payload: raw,
	}
	s.mu.Lock()
	conns := make([]net.Conn, 0, len(s.subscribers))
	for conn := range s.subscribers {
		conns = append(conns, conn)
	}
	s.mu.Unlock()
	for _, conn := range conns {
		s.write(conn, env)
	}
}

func (s *Server) write(conn net.Conn, env protocol.Envelope) {
	if env.ID == "" {
		env.ID = uuid.NewString()
	}
	data, err := json.Marshal(env)
	if err != nil {
		return
	}
	data = append(data, '\n')
	_, _ = conn.Write(data)
}

func okResponse(env protocol.Envelope, payload json.RawMessage) protocol.Envelope {
	ok := true
	return protocol.Envelope{ID: env.ID, Type: protocol.TypeResponse, Method: env.Method, OK: &ok, Payload: payload}
}

func errResponse(env protocol.Envelope, message string) protocol.Envelope {
	ok := false
	return protocol.Envelope{ID: env.ID, Type: protocol.TypeResponse, Method: env.Method, OK: &ok, Error: &message}
}

func errorResponse(id, method, message string) protocol.Envelope {
	ok := false
	return protocol.Envelope{ID: id, Type: protocol.TypeResponse, Method: method, OK: &ok, Error: &message}
}

func eventEnvelope(method string, payload any) protocol.Envelope {
	raw, _ := json.Marshal(payload)
	return protocol.Envelope{ID: uuid.NewString(), Type: protocol.TypeEvent, Method: method, Payload: raw}
}
