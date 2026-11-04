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
            CommandMenu("Chat") {
                Button("Find in Conversations") {
                    NotificationCenter.default.post(name: .focusConversationSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .environment(appState.themeEngine)
                .environment(appState.translationPreferences)
                .environment(\.chatTheme, appState.themeEngine.current)
                .frame(width: 560, height: 480)
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
}
