# glasschat-bridge NDJSON protocol

Local-only IPC between the Swift app and the Go helper.

## Socket

Default path:

```
~/Library/Application Support/GlassChat/bridge.sock
```

Messages are UTF-8 JSON objects separated by `\n`.

## Envelope

```json
{
  "id": "uuid",
  "type": "request|response|event",
  "method": "session.status",
  "ok": true,
  "error": null,
  "payload": {}
}
```

## Methods

| Method | Direction | Status | Purpose |
|---|---|---|---|
| `session.status` | req/res | Implemented | Connection / pairing state |
| `session.pair.start` | req/res | Implemented | Begin QR pairing |
| `session.pair.qr` | event | Implemented | QR payload string for UI rendering |
| `session.pair.success` | event | Implemented | Device linked |
| `session.pair.timeout` | event | Implemented | QR expired |
| `session.connect` | req/res | Implemented | Reconnect existing session |
| `session.logout` | req/res | Implemented | Unlink and wipe bridge session |
| `messages.send.text` | req/res | Implemented | Send plaintext (E2E inside whatsmeow) |
| `messages.event` | event | Implemented | Incoming text messages |
| `chats.list` | req/res | Planned | Conversation summaries |
| `messages.list` | req/res | Planned | Paged history for a chat |

## Payload examples

### `messages.send.text` request

```json
{
  "id": "1",
  "type": "request",
  "method": "messages.send.text",
  "payload": {
    "chatId": "1234567890@s.whatsapp.net",
    "text": "I'll be there in five minutes.",
    "replyToId": null
  }
}
```

### `session.pair.qr` event

```json
{
  "id": "evt-1",
  "type": "event",
  "method": "session.pair.qr",
  "payload": {
    "code": "2@..."
  }
}
```

## Security notes

- Bind the socket with restrictive file permissions (`0600` dir `0700`).
- Authenticate with a random token stored in Keychain (`bridge.auth.token`).
- Do not log message bodies in the bridge.
- Do not expose the socket over TCP/network.
