import AppKit
import SwiftUI

@main
struct GlassChatApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(appState.themeEngine)
                .environment(appState.translationPreferences)
                .environment(\.chatTheme, appState.themeEngine.current)
                .preferredColorScheme(appState.themeEngine.current.preferredColorScheme.colorScheme)
                .onAppear {
                    appState.restoreSidebarWidth()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openNewWindow()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .appSettings) {
                Button("Connection / Log in…") {
                    NotificationCenter.default.post(name: .openGlassChatSettings, object: SettingsTab.connection)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandMenu("Chat") {
                Button("Find in Conversations") {
                    NotificationCenter.default.post(name: .focusConversationSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openGlassChatSettings, object: SettingsTab.appearance)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .environment(appState.themeEngine)
                .environment(appState.translationPreferences)
                .environment(\.chatTheme, appState.themeEngine.current)
                .frame(width: 620, height: 560)
        }
    }

    private func openNewWindow() {
        if let url = URL(string: "glasschat://new") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension Notification.Name {
    static let focusConversationSearch = Notification.Name("glasschat.focusConversationSearch")
    static let openGlassChatSettings = Notification.Name("glasschat.openSettings")
}
