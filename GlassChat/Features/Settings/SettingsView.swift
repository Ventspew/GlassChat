import SwiftUI

struct SettingsView: View {
    @Binding var selectedTab: SettingsTab

    init(selectedTab: Binding<SettingsTab> = .constant(.connection)) {
        _selectedTab = selectedTab
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AppearanceSettingsView()
                .tabItem { Label(SettingsTab.appearance.title, systemImage: SettingsTab.appearance.systemImage) }
                .tag(SettingsTab.appearance)

            TranslationSettingsView()
                .tabItem { Label(SettingsTab.translation.title, systemImage: SettingsTab.translation.systemImage) }
                .tag(SettingsTab.translation)

            PrivacySettingsView()
                .tabItem { Label(SettingsTab.privacy.title, systemImage: SettingsTab.privacy.systemImage) }
                .tag(SettingsTab.privacy)

            DeviceLinkingView()
                .tabItem { Label(SettingsTab.connection.title, systemImage: SettingsTab.connection.systemImage) }
                .tag(SettingsTab.connection)

            FeatureMatrixView()
                .tabItem { Label(SettingsTab.features.title, systemImage: SettingsTab.features.systemImage) }
                .tag(SettingsTab.features)
        }
        .padding()
    }
}
