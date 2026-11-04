import SwiftUI

struct TranslationSettingsView: View {
    @Environment(TranslationPreferencesStore.self) private var store

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Target language", selection: Binding(
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

                Toggle("Auto-translate outgoing messages", isOn: Binding(
                    get: { store.globalDefaults.autoTranslateOutgoing },
                    set: { value in
                        var updated = store.globalDefaults
                        updated.autoTranslateOutgoing = value
                        store.update(updated, for: nil)
                    }
                ))

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
                Text(TranslationProviderKind.appleOnDevice.displayName)
                Text("DeepL is planned as an optional cloud provider. On-device Apple Translation is preferred for privacy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("GlassChat never sends a message without an explicit Send action. Translation preview always appears when auto-translate is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
