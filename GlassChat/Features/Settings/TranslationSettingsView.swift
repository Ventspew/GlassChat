import SwiftUI

struct TranslationSettingsView: View {
    @Environment(TranslationPreferencesStore.self) private var store

    var body: some View {
        Form {
            Section("When you send") {
                Picker("Translate outgoing to", selection: Binding(
                    get: { store.globalDefaults.targetLanguageCode },
                    set: { code in
                        var updated = store.globalDefaults
                        updated.targetLanguageCode = code
                        store.update(updated, for: nil)
                    }
                )) {
                    Text("English").tag("en")
                    Text("Dutch").tag("nl")
                    Text("German").tag("de")
                    Text("French").tag("fr")
                    Text("Spanish").tag("es")
                }

                Toggle("Auto-translate before send", isOn: Binding(
                    get: { store.globalDefaults.autoTranslateOutgoing },
                    set: { value in
                        var updated = store.globalDefaults
                        updated.autoTranslateOutgoing = value
                        store.update(updated, for: nil)
                    }
                ))
            }

            Section("When you receive") {
                Picker("Translate incoming to", selection: Binding(
                    get: { store.globalDefaults.incomingLanguageCode },
                    set: { code in
                        var updated = store.globalDefaults
                        updated.incomingLanguageCode = code
                        store.update(updated, for: nil)
                    }
                )) {
                    Text("Dutch").tag("nl")
                    Text("English").tag("en")
                    Text("German").tag("de")
                    Text("French").tag("fr")
                    Text("Spanish").tag("es")
                }

                Toggle("Translate incoming messages", isOn: Binding(
                    get: { store.globalDefaults.translateIncoming },
                    set: { value in
                        var updated = store.globalDefaults
                        updated.translateIncoming = value
                        store.update(updated, for: nil)
                    }
                ))
            }

            Section("Provider") {
                Text("Local phrase map + MyMemory network fallback")
                Text("Outgoing messages always show a preview before send when auto-translate is on. Incoming translations appear under each bubble (original kept as caption).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("GlassChat never sends a message without an explicit Send action. Network translation only runs for text you ask to translate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
