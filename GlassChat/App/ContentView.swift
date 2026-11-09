import AppKit
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
                    min: 260,
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
        .onAppear {
            if appState.needsFirstLogin || !appState.hasLinkedChats {
                settingsTab = .connection
                showSettings = true
                appState.consumeFirstLoginPrompt()
            }
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
        ZStack {
            LinearGradient(
                colors: [
                    themeEngine.current.chatBackground,
                    themeEngine.current.accent.opacity(0.18),
                    themeEngine.current.sidebarBackground.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Group {
                    if let icon = NSApplication.shared.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image("BrandMark")
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)

                Text("GlassChat")
                    .font(.system(size: 36, weight: .bold, design: .rounded))

                Text("No sample chats. Connect WhatsApp, Telegram, or Discord to start messaging — with translation on send and receive.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                Button {
                    settingsTab = .connection
                    showSettings = true
                } label: {
                    Label("Log in", systemImage: "person.badge.key.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
        }
    }

    private var settingsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                if let icon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
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
        .frame(width: 640, height: 580)
    }

    private var themeBackground: some View {
        themeEngine.current.chatBackground.ignoresSafeArea()
    }
}
