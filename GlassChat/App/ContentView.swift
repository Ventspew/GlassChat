import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeEngine.self) private var themeEngine
    @State private var showSettings = false
    @State private var settingsTab: SettingsTab = .connection

    var body: some View {
        NavigationSplitView {
            SidebarView(showSettings: $showSettings, settingsTab: $settingsTab)
                .navigationSplitViewColumnWidth(
                    min: 240,
                    ideal: appState.sidebarWidth,
                    max: 420
                )
        } detail: {
            if appState.selectedConversation != nil {
                ConversationView()
            } else {
                emptyState
            }
        }
        .background(themeBackground)
        .environment(\.chatTheme, themeEngine.current)
        .tint(themeEngine.current.accent)
        .animation(.easeInOut(duration: 0.2), value: themeEngine.current.id)
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGlassChatSettings)) { note in
            if let tab = note.object as? SettingsTab {
                settingsTab = tab
            } else {
                settingsTab = .connection
            }
            showSettings = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)

            Text("GlassChat")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))

            Text(appState.backendKind == .mock
                 ? "Demo mode is active. Connect WhatsApp, Telegram, or Discord to use real chats."
                 : "Select a chat, or open Connection to link another account.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button {
                settingsTab = .connection
                showSettings = true
            } label: {
                Label("Log in / Connection", systemImage: "person.badge.key.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settingsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("GlassChat Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { showSettings = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            SettingsView(selectedTab: $settingsTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 620, height: 560)
    }

    @ViewBuilder
    private var themeBackground: some View {
        let theme = themeEngine.current
        if theme.usesMaterialBackground {
            ZStack {
                LinearGradient(
                    colors: [
                        theme.chatBackground.opacity(0.95),
                        theme.accent.opacity(0.12),
                        theme.chatBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Rectangle().fill(.thinMaterial)
            }
            .ignoresSafeArea()
        } else {
            theme.chatBackground.ignoresSafeArea()
        }
    }
}
