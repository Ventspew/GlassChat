package server

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/glasschat/bridge/internal/protocol"
)

func TestSessionStatusWithoutPairing(t *testing.T) {
	dir := t.TempDir()
	// Keep the Unix socket path short — macOS sockaddr_un is limited.
	socket := filepath.Join(os.TempDir(), fmt.Sprintf("gc-%d.sock", time.Now().UnixNano()))
	defer os.Remove(socket)
	data := filepath.Join(dir, "data")
	srv := New(socket, "test-token", data)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	errCh := make(chan error, 1)
	go func() {
		errCh <- srv.Run(ctx)
	}()

	deadline := time.Now().Add(3 * time.Second)
	var conn net.Conn
	var err error
	for time.Now().Before(deadline) {
		conn, err = net.Dial("unix", socket)
		if err == nil {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()

	// Drain the initial status event.
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	reader := bufio.NewReader(conn)
	_, _ = reader.ReadBytes('\n')

	req := protocol.Envelope{
		ID:     "1",
		Type:   protocol.TypeRequest,
		Method: protocol.MethodSessionStatus,
	}
	dataReq, _ := json.Marshal(req)
	dataReq = append(dataReq, '\n')
	if _, err := conn.Write(dataReq); err != nil {
		t.Fatal(err)
	}

	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	line, err := reader.ReadBytes('\n')
	if err != nil {
		t.Fatal(err)
	}
	var res protocol.Envelope
	if err := json.Unmarshal(line, &res); err != nil {
		t.Fatal(err)
	}
	if res.OK == nil || !*res.OK {
		t.Fatalf("expected ok response, got %#v", res)
	}

	cancel()
	select {
	case <-errCh:
	case <-time.After(3 * time.Second):
		t.Fatal("server did not shut down")
	}
}
