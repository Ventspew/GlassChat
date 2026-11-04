import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(ThemeEngine.self) private var themeEngine

    var body: some View {
        @Bindable var engine = themeEngine

        Form {
            Section("Theme") {
                Picker("Built-in theme", selection: Binding(
                    get: { engine.current.id },
                    set: { engine.select(themeID: $0) }
                )) {
                    ForEach(engine.availableThemes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Customization") {
                HStack {
                    Text("Accent")
                    Spacer()
                    TextField("Hex", text: Binding(
                        get: { engine.current.accentHex },
                        set: { engine.updateAccentHex($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    Circle()
                        .fill(engine.current.accent)
                        .frame(width: 18, height: 18)
                }

                Slider(
                    value: Binding(
                        get: { engine.current.bubbleCornerRadius },
                        set: { engine.updateBubbleCornerRadius($0) }
                    ),
                    in: 6...28
                ) {
                    Text("Corner radius")
                }

                Slider(
                    value: Binding(
                        get: { engine.current.messageSpacing },
                        set: { engine.updateMessageSpacing($0) }
                    ),
                    in: 2...16
                ) {
                    Text("Message spacing")
                }

                Picker("Density", selection: Binding(
                    get: { engine.current.conversationDensity },
                    set: { engine.updateDensity($0) }
                )) {
                    Text("Comfortable").tag(ThemeDensity.comfortable)
                    Text("Compact").tag(ThemeDensity.compact)
                }

                if engine.current.usesMaterialBackground {
                    Slider(
                        value: Binding(
                            get: { engine.current.sidebarOpacity },
                            set: { engine.updateSidebarOpacity($0) }
                        ),
                        in: 0.5...1.0
                    ) {
                        Text("Sidebar opacity")
                    }
                }
            }

            Section {
                Button("Reset customizations") {
                    engine.resetOverrides()
                }
            } footer: {
                Text("Changes apply immediately without restarting GlassChat.")
            }
        }
        .formStyle(.grouped)
    }
}
