import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeEngine.self) private var themeEngine
    @FocusState private var searchFocused: Bool
    @Binding var showSettings: Bool
    var settingsTab: Binding<SettingsTab>?

    private var onDarkSidebar: Bool {
        themeEngine.current.id == "harbor"
            || themeEngine.current.id == "midnight"
            || themeEngine.current.id == "liquid-glass"
    }

    var body: some View {
        let theme = themeEngine.current

        VStack(spacing: 0) {
            brandHeader

            if !appState.hasLinkedChats {
                connectCard
            }

            if appState.hasLinkedChats {
                Picker("Protocol", selection: Binding(
                    get: { appState.protocolFilter },
                    set: { appState.setProtocolFilter($0) }
                )) {
                    ForEach(MessengerProtocol.allCases) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 8)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(secondaryLabel)
                    TextField("Search", text: Binding(
                        get: { appState.searchText },
                        set: { appState.updateSearch($0) }
                    ))
                    .textFieldStyle(.plain)
                    .foregroundStyle(primaryLabel)
                    .focused($searchFocused)
                }
                .padding(10)
                .background(Color.white.opacity(onDarkSidebar ? 0.08 : 0.95), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                chatList
            } else {
                Spacer(minLength: 0)
            }

            connectionFooter
        }
        .background(theme.sidebarBackground.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: .focusConversationSearch)) { _ in
            searchFocused = true
        }
    }

    private var primaryLabel: Color {
        onDarkSidebar ? Color.white.opacity(0.92) : Color.primary
    }

    private var secondaryLabel: Color {
        onDarkSidebar ? Color.white.opacity(0.62) : Color.secondary
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            appBadge
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("GlassChat")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(primaryLabel)
                Text(appState.hasLinkedChats ? "Linked" : "Not signed in")
                    .font(.caption2)
                    .foregroundStyle(secondaryLabel)
            }

            Spacer(minLength: 8)

            Button {
                settingsTab?.wrappedValue = .connection
                showSettings = true
            } label: {
                Image(systemName: "person.badge.key.fill")
                    .foregroundStyle(primaryLabel)
            }
            .buttonStyle(.borderless)
            .help("Log in")

            Button {
                settingsTab?.wrappedValue = .appearance
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(primaryLabel)
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .keyboardShortcut(",", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var appBadge: some View {
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect an account")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryLabel)
            Text("No demo chats. Link WhatsApp, Telegram, or Discord to fill this inbox.")
                .font(.caption)
                .foregroundStyle(secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                settingsTab?.wrappedValue = .connection
                showSettings = true
            } label: {
                Text("Log in")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(themeEngine.current.accent)
            .controlSize(.large)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(onDarkSidebar ? 0.08 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(onDarkSidebar ? 0.14 : 0.2), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var chatList: some View {
        List(selection: Binding(
            get: { appState.selectedChatID },
            set: { appState.selectChat($0) }
        )) {
            if !appState.filteredConversations.filter(\.isPinned).isEmpty {
                Section {
                    ForEach(appState.filteredConversations.filter(\.isPinned)) { conversation in
                        ConversationRowView(conversation: conversation, onDarkSidebar: onDarkSidebar)
                            .tag(conversation.id)
                            .listRowBackground(selectionBackground(for: conversation.id))
                            .contextMenu { conversationContextMenu(conversation) }
                    }
                } header: {
                    Text("Pinned")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryLabel)
                        .textCase(nil)
                }
            }

            Section {
                if appState.filteredConversations.filter({ !$0.isPinned }).isEmpty {
                    Text("No chats for this filter")
                        .foregroundStyle(secondaryLabel)
                        .padding(.vertical, 12)
                } else {
                    ForEach(appState.filteredConversations.filter { !$0.isPinned }) { conversation in
                        ConversationRowView(conversation: conversation, onDarkSidebar: onDarkSidebar)
                            .tag(conversation.id)
                            .listRowBackground(selectionBackground(for: conversation.id))
                            .contextMenu { conversationContextMenu(conversation) }
                    }
                }
            } header: {
                Text("Chats")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryLabel)
                    .textCase(nil)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .environment(\.colorScheme, onDarkSidebar ? .dark : .light)
    }

    private var connectionFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(appState.connectionState.label)
                .font(.caption)
                .foregroundStyle(secondaryLabel)
                .lineLimit(1)
            Spacer()
            Button("Log in") {
                settingsTab?.wrappedValue = .connection
                showSettings = true
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
            .foregroundStyle(themeEngine.current.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(onDarkSidebar ? 0.22 : 0.04))
    }

    private var connectionColor: Color {
        switch appState.connectionState {
        case .connected: return .green
        case .connecting, .awaitingPairing: return .orange
        case .error: return .red
        case .disconnected: return .secondary
        }
    }

    private func selectionBackground(for id: ChatID) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(appState.selectedChatID == id ? themeEngine.current.sidebarSelection : Color.clear)
            .padding(.vertical, 1)
    }

    @ViewBuilder
    private func conversationContextMenu(_ conversation: Conversation) -> some View {
        Button(conversation.isPinned ? "Unpin" : "Pin") {
            appState.togglePin(conversation)
        }
        Button("Mark as Read") {
            appState.selectChat(conversation.id)
        }
    }
}
