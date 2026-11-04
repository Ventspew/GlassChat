import SwiftUI

struct DeviceLinkingView: View {
    @Environment(AppState.self) private var appState
    @State private var qrCode: String?
    @State private var statusMessage: String?
    @State private var isBusy = false

    var body: some View {
        Form {
            Section("Backend") {
                Picker("Messaging backend", selection: Binding(
                    get: { appState.backendKind },
                    set: { kind in
                        appState.switchBackend(kind)
                    }
                )) {
                    ForEach(MessagingBackendKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                LabeledContent("Status", value: appState.connectionState.label)
            }

            Section("WhatsApp pairing") {
                Text("Scan this QR code in WhatsApp → Settings → Linked Devices → Link a Device. GlassChat uses the official multi-device protocol via a local helper — not WhatsApp Web.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    if let qrCode {
                        QRCodeView(code: qrCode, size: 220)
                    } else {
                        placeholderQR
                    }
                    Spacer()
                }
                .padding(.vertical, 8)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(isBusy ? "Working…" : "Show pairing QR") {
                        Task { await startPairing() }
                    }
                    .disabled(isBusy || appState.backendKind != .whatsmeowBridge)

                    Button("Logout / unlink") {
                        Task { await logout() }
                    }
                    .disabled(isBusy || appState.backendKind != .whatsmeowBridge)
                }
            }

            Section("Risk notice") {
                Text("Unofficial multi-device clients may break when WhatsApp changes servers, and may risk account restrictions. Use at your own risk. GlassChat does not bypass encryption, device authorization, or anti-abuse protections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if appState.backendKind == .whatsmeowBridge {
                Task { await refreshQRFromService() }
            }
        }
        .onChange(of: appState.connectionState) { _, newValue in
            if case .connected = newValue {
                qrCode = nil
                statusMessage = "Linked successfully."
            }
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
        statusMessage = "Starting bridge and requesting QR…"
        do {
            if appState.backendKind != .whatsmeowBridge {
                appState.switchBackend(.whatsmeowBridge)
            }
            try await appState.startWhatsAppPairing()
            await pollForQR()
            statusMessage = "Scan the QR code with your phone."
        } catch {
            statusMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func logout() async {
        isBusy = true
        do {
            try await appState.logoutWhatsApp()
            qrCode = nil
            statusMessage = "Logged out."
        } catch {
            statusMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func pollForQR() async {
        for _ in 0..<40 {
            if let code = await appState.currentPairingQRCode() {
                qrCode = code
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if qrCode == nil {
            statusMessage = "Timed out waiting for QR. Is the bridge built?"
        }
    }

    private func refreshQRFromService() async {
        qrCode = await appState.currentPairingQRCode()
    }
}
