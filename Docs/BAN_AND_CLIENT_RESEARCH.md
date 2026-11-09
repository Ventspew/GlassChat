# Ban risk & client research (Watusi, whatRust, Discord Android)

**Nothing is ban-proof.** GlassChat reduces obvious protocol fingerprints and encourages human-like usage. WhatsApp/Meta can still detect unofficial companions.

## Watusi ([FouadRaheb/Watusi-for-WhatsApp](https://github.com/FouadRaheb/Watusi-for-WhatsApp))

- **What it is:** iOS tweak / sideloaded mod of the **official WhatsApp IPA**, not a protocol rewrite.
- **How it “solves” features:** patches the real app UI (themes, privacy toggles) while still speaking Meta’s official mobile protocol from a modified binary.
- **Ban reality:** users still report forced logouts and temporary bans for “unofficial app”. Jailbreak/sideload signals are detectable. **Not ban-proof.**
- **Takeaway for GlassChat:** modifying the official binary is a different product class. We stay on the multi-device companion protocol (whatsmeow), which is closer to WhatsApp Web/Desktop linking.

## whatRust ([karem505/whatRust](https://github.com/karem505/whatRust))

- **What it is:** Rust + Tauri v2 shell around **official `web.whatsapp.com`** (OS webview).
- **How it reduces risk vs bots:** traffic looks like WhatsApp Web in a browser (same servers, cookies, Web client fingerprint). Multi-account = isolated webview stores.
- **Ban reality:** still unofficial packaging; spam/bulk behaviour can ban. Closer to “normal Web” than a raw library with `whatsmeow` fingerprints.
- **Takeaway for GlassChat:** we intentionally do **not** embed WhatsApp Web. Instead we harden the companion fingerprint to look like **Chrome Web companion** (same family as Web).

## Fingerprint hardening we apply

Inspired by community research ([Prekey Pogo](https://arxiv.org/abs/2504.07323)) and [caseyng/whatsmeow](https://github.com/caseyng/whatsmeow):

1. Device props: Chrome / CHROME / realistic version (not `whatsmeow` / `UNKNOWN`)
2. Prefer fingerprint-hardened whatsmeow fork (prekey batch sizes, signed prekey rotation, Chrome TLS via uTLS)
3. Human-like usage: no mass messaging, no rapid pairing retries, keep official phone app active

## Discord on Android (Aliucord / Vendetta / Revenge)

| Project | Approach |
|---|---|
| [Aliucord](https://github.com/Aliucord/Aliucord) (~5k★) | Xposed-style **mod of the official Discord Android APK** |
| [Vendetta](https://github.com/vendetta-mod/Vendetta) / [Revenge](https://github.com/revenge-mod/revenge-bundle) | Client mods injecting into official Discord mobile |

**How they solve Discord:** they don’t reimplement Discord from scratch for end users — they run the **official client** and patch UI/plugins. Auth is a normal Discord user session inside the real app.

**GlassChat Discord path:**

- **Recommended:** bot token (`discordgo`) — ToS-aligned automation.
- **Android-mod style (risky):** user token without `Bot ` prefix — same API surface mods rely on, but Discord forbids unofficial user clients. Enabled only with an explicit risk toggle.

## Practical advice

1. Keep using the **official WhatsApp on your phone** as primary.
2. Link GlassChat as one companion (max 4 devices).
3. Don’t blast messages to non-contacts.
4. Expect breakage; treat unofficial clients as best-effort.
