package server

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"

	"github.com/glasschat/bridge/internal/protocol"
	"github.com/glasschat/bridge/internal/wa"
	"github.com/google/uuid"
)

// Server speaks NDJSON over a Unix domain socket and hosts whatsmeow.
type Server struct {
	SocketPath string
	Token      string
	DataDir    string

	wa *wa.Client

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
	s.wa = wa.New(dataDir, s.broadcast)
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

	// Restore an existing session after the socket is listening.
	go func() {
		_ = s.wa.EnsureStarted(ctx)
	}()

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

	// Push current status immediately.
	state, label, _ := s.wa.Status()
	s.write(conn, eventEnvelope(protocol.EventStatus, protocol.SessionStatusPayload{
		State:        state,
		AccountLabel: label,
	}))

	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	for scanner.Scan() {
		line := scanner.Bytes()
		var env protocol.Envelope
		if err := json.Unmarshal(line, &env); err != nil {
			s.write(conn, errorResponse("", "invalid_json", err.Error()))
			continue
		}
		s.write(conn, s.dispatch(ctx, env))
	}
}

func (s *Server) dispatch(ctx context.Context, env protocol.Envelope) protocol.Envelope {
	switch env.Method {
	case protocol.MethodSessionStatus:
		state, label, detail := s.wa.Status()
		payload, _ := json.Marshal(protocol.SessionStatusPayload{
			State:        state,
			AccountLabel: label,
			Detail:       detail,
		})
		return okResponse(env, payload)

	case protocol.MethodSessionPairStart:
		if err := s.wa.StartPairing(ctx); err != nil {
			return errResponse(env, err.Error())
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
		if err := s.wa.Logout(ctx); err != nil {
			return errResponse(env, err.Error())
		}
		payload, _ := json.Marshal(protocol.SessionStatusPayload{State: "disconnected"})
		return okResponse(env, payload)

	case protocol.MethodMessagesSendText:
		var req protocol.SendTextPayload
		if err := json.Unmarshal(env.Payload, &req); err != nil {
			return errResponse(env, "invalid payload")
		}
		id, err := s.wa.SendText(ctx, req.ChatID, req.Text)
		if err != nil {
			return errResponse(env, err.Error())
		}
		payload, _ := json.Marshal(map[string]string{"id": id})
		return okResponse(env, payload)

	case protocol.MethodChatsList, protocol.MethodMessagesList:
		return errResponse(env, fmt.Sprintf("%s not fully implemented yet — pairing and text send work", env.Method))

	default:
		return errResponse(env, "unknown method")
	}
}

func (s *Server) broadcast(method string, payload any) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return
	}
	env := protocol.Envelope{
		ID:      uuid.NewString(),
		Type:    protocol.TypeEvent,
		Method:  method,
		Payload: raw,
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
	return protocol.Envelope{
		ID:      env.ID,
		Type:    protocol.TypeResponse,
		Method:  env.Method,
		OK:      &ok,
		Payload: payload,
	}
}

func errResponse(env protocol.Envelope, message string) protocol.Envelope {
	ok := false
	return protocol.Envelope{
		ID:     env.ID,
		Type:   protocol.TypeResponse,
		Method: env.Method,
		OK:     &ok,
		Error:  &message,
	}
}

func errorResponse(id, method, message string) protocol.Envelope {
	ok := false
	return protocol.Envelope{
		ID:     id,
		Type:   protocol.TypeResponse,
		Method: method,
		OK:     &ok,
		Error:  &message,
	}
}

func eventEnvelope(method string, payload any) protocol.Envelope {
	raw, _ := json.Marshal(payload)
	return protocol.Envelope{
		ID:      uuid.NewString(),
		Type:    protocol.TypeEvent,
		Method:  method,
		Payload: raw,
	}
}
