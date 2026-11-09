import SwiftUI

struct DeviceLinkingView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedProtocol: MessengerProtocol = .whatsapp
    @State private var qrCode: String?
    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var telegramAPIID = ""
    @State private var telegramAPIHash = ""
    @State private var discordToken = ""
    @State private var discordAsBot = false

    var body: some View {
        Form {
            Section("Backend") {
                Picker("Messaging backend", selection: Binding(
                    get: { appState.backendKind },
                    set: { appState.switchBackend($0) }
                )) {
                    ForEach(MessagingBackendKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                LabeledContent("Status", value: appState.connectionState.label)
                if appState.backendKind == .mock {
                    Text("Demo mode shows sample chats only. Switch to “WhatsApp Bridge” (local Go helper) to log in for real.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Switch to live bridge") {
                        appState.switchBackend(.whatsmeowBridge)
                    }
                }
            }

            Section("Protocol") {
                Picker("Service", selection: $selectedProtocol) {
                    Text("WhatsApp").tag(MessengerProtocol.whatsapp)
                    Text("Telegram").tag(MessengerProtocol.telegram)
                    Text("Discord").tag(MessengerProtocol.discord)
                }
                .pickerStyle(.segmented)
                Text(protocolHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedProtocol == .telegram {
                Section("Telegram credentials") {
                    TextField("api_id", text: $telegramAPIID)
                    SecureField("api_hash", text: $telegramAPIHash)
                    Text("Create an app at my.telegram.org (open source: gotd/td).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if selectedProtocol == .discord {
                Section("Discord login") {
                    SecureField("Account token (user login)", text: $discordToken)
                    Toggle("Use bot token instead", isOn: $discordAsBot)
                    Text(discordAsBot
                         ? "Paste a bot token from the Discord Developer Portal. Invite the bot to your servers and enable Message Content Intent."
                         : "Paste your Discord user token for full personal login (DMs + servers), same idea as Aliucord/Vendetta. Against Discord ToS — account risk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Link account") {
                HStack {
                    Spacer()
                    if let qrCode, selectedProtocol != .discord {
                        QRCodeView(code: qrCode, size: 220)
                    } else if selectedProtocol == .discord {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                            .frame(width: 220, height: 220)
                    } else {
                        placeholderQR
                    }
                    Spacer()
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(isBusy ? "Working…" : connectTitle) {
                        Task { await startPairing() }
                    }
                    .disabled(isBusy)

                    Button("Logout") {
                        Task { await logout() }
                    }
                    .disabled(isBusy)
                }
            }

            Section("Open-source stack") {
                Text("WhatsApp: whatsmeow (yawac-style). Telegram: gotd/td. Discord: discordgo. See Docs/OPEN_SOURCE_RESEARCH.md.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: appState.connectionState) { _, newValue in
            if case .connected = newValue {
                if selectedProtocol != .whatsapp && selectedProtocol != .telegram {
                    qrCode = nil
                }
                statusMessage = "Linked / connected."
            }
        }
    }

    private var connectTitle: String {
        switch selectedProtocol {
        case .discord: return "Connect Discord"
        case .telegram: return "Show Telegram QR"
        default: return "Show WhatsApp QR"
        }
    }

    private var protocolHelp: String {
        switch selectedProtocol {
        case .whatsapp:
            return "Scan in WhatsApp → Linked Devices. Uses whatsmeow multi-device protocol."
        case .telegram:
            return "Scan in Telegram → Settings → Devices → Link Desktop Device."
        case .discord:
            return "Full login with your Discord user token (DMs + guild channels). Bot token optional."
        case .all:
            return ""
        }
    }

    private var placeholderQR: some View {
        VStack(spacing: 12) {
            Image(systemName: "qrcode")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No QR yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 220, height: 220)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func startPairing() async {
        isBusy = true
        statusMessage = "Starting local bridge…"
        do {
            if appState.backendKind != .whatsmeowBridge {
                appState.switchBackend(.whatsmeowBridge)
            }
            try await appState.startPairing(
                protocolKind: selectedProtocol,
                telegramAPIID: telegramAPIID.isEmpty ? nil : telegramAPIID,
                telegramAPIHash: telegramAPIHash.isEmpty ? nil : telegramAPIHash,
                discordToken: discordToken.isEmpty ? nil : discordToken,
                discordBot: discordAsBot
            )
            if selectedProtocol != .discord {
                await pollForQR()
                statusMessage = "Scan the QR code."
            } else {
                statusMessage = "Connecting Discord…"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func logout() async {
        isBusy = true
        do {
            try await appState.logout(protocolKind: selectedProtocol)
            qrCode = nil
            statusMessage = "Logged out."
        } catch {
            statusMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func pollForQR() async {
        for _ in 0..<60 {
            if let code = await appState.currentPairingQRCode() {
                qrCode = code
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if qrCode == nil {
            statusMessage = "Timed out waiting for QR."
        }
    }
}
