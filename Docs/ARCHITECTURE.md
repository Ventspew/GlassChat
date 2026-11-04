# GlassChat Architecture

## Feasibility

GlassChat is a **native macOS client** (Swift 6 / SwiftUI). It does **not** embed WhatsApp Web, Electron, Tauri, or WKWebView automation.

WhatsApp does not publish a public consumer desktop API. The viable path for a native companion client is the **multi-device protocol** used by official linked devices.

### Protocol library evaluation

| Library | Language | Maintenance | Fit |
|---|---|---|---|
| **whatsmeow** | Go | Active (MPL-2.0) | **Chosen** — E2E via libsignal, QR pairing, SQLite store, media/groups/receipts |
| Baileys | TypeScript/Node | Active | Rejected — Node runtime is heavier and conflicts with a native-first Mac app |
| Pure Swift reverse-engineering | Swift | N/A | Rejected — unsustainable against frequent protocol changes |

### Risks (read carefully)

- Unofficial protocol integrations **may break** without notice.
- Using third-party clients **may risk account restrictions**.
- GlassChat **does not** bypass WhatsApp encryption, device authorization, or anti-abuse systems.
- Features the protocol library cannot support (calls, broadcast lists) remain **Unsupported**.

## Layered design

```
SwiftUI App (MVVM)
    → MessagingService abstraction
        → MockMessagingService          (Phase 2–3, current default)
        → WhatsmeowMessagingService     (Phase 4)
            → Unix socket NDJSON IPC
                → glasschat-bridge (Go + whatsmeow)
                    → WhatsApp multi-device infrastructure
```

### Data ownership

| Store | Owner | Contents |
|---|---|---|
| Swift UI state / UserDefaults | App | Themes, translation prefs, sidebar width |
| SwiftData (future cache expansion) | App | Optional chat mirror for offline UI |
| Keychain | App | Bridge auth token (never message bodies) |
| SQLite (`whatsmeow` sqlstore) | Bridge | Device identity, Signal sessions, WA app state |

### IPC

- Transport: Unix domain socket under `~/Library/Application Support/GlassChat/bridge.sock`
- Framing: newline-delimited JSON (request / response / event)
- See [BRIDGE_PROTOCOL.md](BRIDGE_PROTOCOL.md)

## Translation

- Primary: Apple `Translation` framework (on-device), macOS 15+
- Detection: `NaturalLanguage.NLLanguageRecognizer`
- Preview-before-send is mandatory when auto-translate is on
- **Never** auto-sends without an explicit user Send action
- DeepL is documented as a future optional provider only

## Feature matrix

See in-app **Settings → Features** and `FeatureCatalog` in source.

### Implemented now

- Native SwiftUI shell (sidebar, chat, composer, settings)
- Theme engine with five built-ins + live overrides
- Composer translation preview
- Mock messaging backend with sample conversations
- whatsmeow Go bridge with **QR pairing**, session restore, text send, incoming text events

### Planned

- Full chat history / contact sync UI
- Media, voice, reactions over the wire
- Native notifications, full search

### Unsupported

- Calls
- Broadcast lists

## Phases

1. Feasibility & architecture — **this document**
2. Native interface + mock data — **shipped in 0.1**
3. Translation — **shipped in 0.1**
4. Messaging integration — bridge skeleton present; live sync next
5. Advanced messaging features
6. Performance, accessibility, sandbox hardening
