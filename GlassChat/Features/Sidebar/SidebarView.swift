import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeEngine.self) private var themeEngine
    @FocusState private var searchFocused: Bool

    var body: some View {
        let theme = themeEngine.current

        VStack(spacing: 0) {
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
            .padding(.top, 10)

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
            .background(theme.composerBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)

            List(selection: Binding(
                get: { appState.selectedChatID },
                set: { appState.selectChat($0) }
            )) {
                Section("Pinned") {
                    ForEach(appState.filteredConversations.filter(\.isPinned)) { conversation in
                        ConversationRowView(conversation: conversation)
                            .tag(conversation.id)
                            .listRowBackground(selectionBackground(for: conversation.id))
                            .contextMenu {
                                conversationContextMenu(conversation)
                            }
                    }
                }

                Section("Chats") {
                    ForEach(appState.filteredConversations.filter { !$0.isPinned }) { conversation in
                        ConversationRowView(conversation: conversation)
                            .tag(conversation.id)
                            .listRowBackground(selectionBackground(for: conversation.id))
                            .contextMenu {
                                conversationContextMenu(conversation)
                            }
                    }
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

    private var connectionFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(appState.connectionState.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
                .fill(.regularMaterial)
                .opacity(theme.sidebarOpacity)
        } else {
            theme.sidebarBackground.opacity(theme.sidebarOpacity)
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
        Divider()
        Text("More actions: Planned")
    }
}
