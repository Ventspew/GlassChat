import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeEngine.self) private var themeEngine

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: 220,
                    ideal: appState.sidebarWidth,
                    max: 420
                )
        } detail: {
            if appState.selectedConversation != nil {
                ConversationView()
            } else {
                ContentUnavailableView(
                    "No Conversation",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a chat from the sidebar to get started.")
                )
            }
        }
        .background(themeBackground)
        .environment(\.chatTheme, themeEngine.current)
        .tint(themeEngine.current.accent)
        .animation(.easeInOut(duration: 0.2), value: themeEngine.current.id)
    }

    @ViewBuilder
    private var themeBackground: some View {
        let theme = themeEngine.current
        if theme.usesMaterialBackground {
            ZStack {
                LinearGradient(
                    colors: [
                        theme.chatBackground.opacity(0.9),
                        theme.accent.opacity(0.18),
                        theme.chatBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Rectangle().fill(.ultraThinMaterial)
            }
            .ignoresSafeArea()
        } else {
            theme.chatBackground.ignoresSafeArea()
        }
    }
}
