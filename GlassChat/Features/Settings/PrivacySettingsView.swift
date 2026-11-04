import SwiftUI

struct PrivacySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var confirmClear = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Local data") {
                Text("Conversations are cached locally for the UI. Protocol session material (Phase 4) will live in the Go bridge SQLite store and Keychain-backed bridge tokens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Clear local data…", role: .destructive) {
                    confirmClear = true
                }
            }

            Section("Logging") {
                Text("GlassChat does not log message contents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Encryption") {
                Text("When the whatsmeow bridge is connected, end-to-end encryption remains handled by the Signal protocol implementation inside the helper. GlassChat never weakens or bypasses that model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Clear all local GlassChat data?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                Task {
                    await appState.clearLocalData()
                    statusMessage = "Local UI cache and translation preferences cleared."
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
