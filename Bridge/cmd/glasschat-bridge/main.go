package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/glasschat/bridge/internal/server"
	"github.com/google/uuid"
)

func main() {
	home, _ := os.UserHomeDir()
	defaultSupport := filepath.Join(home, "Library", "Application Support", "GlassChat")
	defaultSocket := filepath.Join(defaultSupport, "bridge.sock")
	defaultData := filepath.Join(defaultSupport, "whatsmeow")

	socket := flag.String("socket", defaultSocket, "Unix domain socket path")
	dataDir := flag.String("data", defaultData, "Directory for whatsmeow SQLite session")
	token := flag.String("token", "", "Auth token (generated if empty)")
	flag.Parse()

	auth := *token
	if auth == "" {
		auth = uuid.NewString()
		fmt.Fprintf(os.Stderr, "glasschat-bridge: token %s\n", auth)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	srv := server.New(*socket, auth, *dataDir)
	fmt.Fprintf(os.Stderr, "glasschat-bridge listening on %s\n", *socket)
	fmt.Fprintf(os.Stderr, "glasschat-bridge session data: %s\n", *dataDir)
	if err := srv.Run(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "bridge error: %v\n", err)
		os.Exit(1)
	}
}
