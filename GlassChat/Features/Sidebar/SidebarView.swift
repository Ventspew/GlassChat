import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeEngine.self) private var themeEngine
    @FocusState private var searchFocused: Bool
    @Binding var showSettings: Bool
    var settingsTab: Binding<SettingsTab>?

    var body: some View {
        let theme = themeEngine.current

        VStack(spacing: 0) {
            brandHeader

            if appState.backendKind == .mock {
                demoBanner
            }

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
                    .foregroundStyle(.secondary)
                TextField("Search", text: Binding(
                    get: { appState.searchText },
                    set: { appState.updateSearch($0) }
                ))
                .textFieldStyle(.plain)
                .focused($searchFocused)
            }
            .padding(10)
            .background(theme.composerBackground.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)

            List(selection: Binding(
                get: { appState.selectedChatID },
                set: { appState.selectChat($0) }
            )) {
                if !appState.filteredConversations.filter(\.isPinned).isEmpty {
                    Section {
                        ForEach(appState.filteredConversations.filter(\.isPinned)) { conversation in
                            ConversationRowView(conversation: conversation)
                                .tag(conversation.id)
                                .listRowBackground(selectionBackground(for: conversation.id))
                                .contextMenu {
                                    conversationContextMenu(conversation)
                                }
                        }
                    } header: {
                        Text("Pinned")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.7))
                            .textCase(nil)
                    }
                }

                Section {
                    if appState.filteredConversations.filter({ !$0.isPinned }).isEmpty {
                        ContentUnavailableView(
                            appState.backendKind == .mock ? "Demo chats" : "No chats yet",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text(
                                appState.backendKind == .mock
                                ? "Open Settings → Connection to link WhatsApp, Telegram, or Discord."
                                : "Link an account to sync conversations."
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(appState.filteredConversations.filter { !$0.isPinned }) { conversation in
                            ConversationRowView(conversation: conversation)
                                .tag(conversation.id)
                                .listRowBackground(selectionBackground(for: conversation.id))
                                .contextMenu {
                                    conversationContextMenu(conversation)
                                }
                        }
                    }
                } header: {
                    Text("Chats")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .textCase(nil)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            connectionFooter
        }
        .background(sidebarBackground)
        .onReceive(NotificationCenter.default.publisher(for: .focusConversationSearch)) { _ in
            searchFocused = true
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 1) {
                Text("GlassChat")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Text(appState.backendKind == .mock ? "Demo mode" : "Live bridge")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                settingsTab?.wrappedValue = .connection
                showSettings = true
            } label: {
                Image(systemName: "person.badge.key.fill")
            }
            .buttonStyle(.borderless)
            .help("Log in / Connection")

            Button {
                settingsTab?.wrappedValue = .appearance
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .keyboardShortcut(",", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var demoBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You’re on demo data")
                .font(.subheadline.weight(.semibold))
            Text("Link WhatsApp, Telegram, or Discord to chat for real.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                settingsTab?.wrappedValue = .connection
                showSettings = true
            } label: {
                Text("Open login")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(themeEngine.current.accent.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(themeEngine.current.accent.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var connectionFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(appState.connectionState.label)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(1)
            Spacer()
            Button("Settings") {
                settingsTab?.wrappedValue = .connection
                showSettings = true
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var connectionColor: Color {
        switch appState.connectionState {
        case .connected:
            return .green
        case .connecting, .awaitingPairing:
            return .orange
        case .error:
            return .red
        case .disconnected:
            return .secondary
        }
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        let theme = themeEngine.current
        if theme.usesMaterialBackground {
            Rectangle()
                .fill(.thickMaterial)
        } else {
            theme.sidebarBackground.opacity(max(theme.sidebarOpacity, 0.92))
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
