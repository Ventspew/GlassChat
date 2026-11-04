# glasschat-bridge

Local Go helper that hosts **whatsmeow** for GlassChat.

## Features

- Unix domain socket + NDJSON IPC
- WhatsApp multi-device QR pairing (`session.pair.start` → `session.pair.qr` events)
- Session persistence (SQLite via `modernc.org/sqlite`, no CGO)
- Text send (`messages.send.text`)
- Incoming text events (`messages.event`)

## Build

```bash
CGO_ENABLED=0 go test ./...
CGO_ENABLED=0 go build -o glasschat-bridge ./cmd/glasschat-bridge
./glasschat-bridge
```

Default socket:

`~/Library/Application Support/GlassChat/bridge.sock`

## Pairing flow

1. Swift app starts the bridge and calls `session.pair.start`
2. Bridge emits `session.pair.qr` with the WhatsApp QR payload string
3. App renders the QR; user scans it in WhatsApp → Linked Devices
4. Bridge emits `session.pair.success` and stays connected

## License note

whatsmeow is MPL-2.0. Modifications to whatsmeow source files (if any) must remain MPL-2.0.
