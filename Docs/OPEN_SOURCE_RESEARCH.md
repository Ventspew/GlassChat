# Open-source research — WhatsApp / Telegram / Discord

GlassChat is a **native multi-messenger shell**. Backends are local helpers inspired by maintained GitHub projects — not Electron/WebView wrappers.

## WhatsApp

| Project | Stars (approx.) | Approach | Takeaway for GlassChat |
|---|---|---|---|
| [tulir/whatsmeow](https://github.com/tulir/whatsmeow) | ~7.8k | Go multi-device protocol | **Primary engine** (already used) |
| [vadika/yawac](https://github.com/vadika/yawac) | native SwiftUI + whatsmeow | Closest architectural twin — QR, history sync, contacts |
| [thinkter/rust-meow](https://github.com/thinkter/rust-meow) | Tauri + whatsmeow sidecar | Confirms sidecar/bridge pattern |
| [komo1iddin/brisk](https://github.com/komo1iddin/brisk) | SwiftUI + Rust whatsapp engine | Another native Mac direction |
| WebView wrappers (WhatsApp Desk, etc.) | various | WebKit → web.whatsapp.com | **Rejected** (GlassChat hard requirement) |

**GlassChat WhatsApp path:** whatsmeow + local Unix NDJSON bridge (yawac-style), with HistorySync → chat list + message store.

## Telegram — possible in parallel: **yes**

| Project | Notes |
|---|---|
| [gotd/td](https://github.com/gotd/td) | Pure Go MTProto client, QR + phone login |
| [Swiftgram/TDLibKit](https://github.com/Swiftgram/TDLibKit) | Official TDLib Swift wrapper (heavy XCFramework) |
| [overtake/TelegramSwift](https://github.com/overtake/TelegramSwift) | Official Telegram macOS source (GPL, huge) |
| [programVeins/menugram](https://github.com/programVeins/menugram) | Menu-bar TDLibKit sample |

**GlassChat Telegram path:** `gotd/td` inside the same local bridge (fits our Go sidecar). Requires free `api_id` / `api_hash` from https://my.telegram.org.

## Discord — possible with caveats

| Project | Notes |
|---|---|
| [SwiftcordApp/Swiftcord](https://github.com/SwiftcordApp/Swiftcord) | Native SwiftUI Discord client |
| [SwiftcordApp/DiscordKit](https://github.com/SwiftcordApp/DiscordKit) | Swift Discord API (user + bot modules) |
| [bwmarrin/discordgo](https://github.com/bwmarrin/discordgo) | Popular Go Discord library |

**ToS note:** Discord forbids unofficial **user** clients. GlassChat supports Discord via a **bot token** (compliant automation) and optionally a user token behind an explicit risk toggle. Prefer bot tokens for anything you ship.

**GlassChat Discord path:** `discordgo` in the bridge.

## Multi-messenger at once?

**Yes.** Pattern used by Beeper / bridge ecosystems:

```
SwiftUI unified inbox
  → MessagingRouter (protocol filter)
      → WhatsApp (whatsmeow)
      → Telegram (gotd)
      → Discord (discordgo)
```

Each protocol keeps its own session store under Application Support. Chats are namespaced: `wa:…`, `tg:…`, `dc:…`.

## Risks (all unofficial / third-party)

- WhatsApp companion protocol: ban risk, breakage
- Telegram: official API, safest of the three if using your own api_id
- Discord user clients: ToS violation risk — bot path preferred

Also see [BAN_AND_CLIENT_RESEARCH.md](BAN_AND_CLIENT_RESEARCH.md) for Watusi, whatRust, and Android Discord mods.
