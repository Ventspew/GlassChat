# GlassChat

Native macOS WhatsApp companion client built with **Swift 6 + SwiftUI** and a local **whatsmeow** Go bridge.

Not a WhatsApp Web wrapper — no Electron, Tauri, or WKWebView scraping.

> **Unofficial.** Protocol integrations can break and may risk account restrictions. GlassChat does not bypass encryption, device authorization, or anti-abuse protections.

## Features (0.2)

- Native Messages-inspired UI + theme engine
- On-device translation preview before send
- **QR device linking** via whatsmeow multi-device protocol
- Local Go bridge (bundled inside the `.app`)
- GitHub Actions builds a downloadable `GlassChat-macOS.zip`

## Requirements

- macOS 15.0+
- Xcode 16+ (to build locally)
- Go 1.22+ (for the bridge)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build locally

```bash
# 1) Bridge
cd Bridge
CGO_ENABLED=0 go build -o glasschat-bridge ./cmd/glasschat-bridge
cd ..

# 2) App
xcodegen generate
open GlassChat.xcodeproj
```

Or verify from the CLI (requires full Xcode.app):

```bash
./Scripts/verify.sh
xcodebuild -scheme GlassChat -destination 'platform=macOS' build
```

## Pair with WhatsApp

1. Run GlassChat
2. Open **Settings → Connection**
3. Choose **WhatsApp (QR linked device)**
4. Click **Show pairing QR**
5. On your phone: WhatsApp → Settings → Linked Devices → Link a Device
6. Scan the QR shown in GlassChat

## GitHub Actions artifact

Every push to `main` runs [.github/workflows/build-macos.yml](.github/workflows/build-macos.yml) on `macos-15`, builds `GlassChat.app` (with the bridge embedded), and uploads **GlassChat-macOS.zip**.

Tag a version to publish a GitHub Release:

```bash
git tag v0.2.0
git push origin v0.2.0
```

## Architecture

See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) and [Docs/BRIDGE_PROTOCOL.md](Docs/BRIDGE_PROTOCOL.md).

## License

MIT for GlassChat app code. whatsmeow remains MPL-2.0.
