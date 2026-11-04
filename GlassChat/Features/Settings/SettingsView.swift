import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            TranslationSettingsView()
                .tabItem { Label("Translation", systemImage: "globe") }

            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }

            DeviceLinkingView()
                .tabItem { Label("Connection", systemImage: "qrcode") }

            FeatureMatrixView()
                .tabItem { Label("Features", systemImage: "checklist") }
        }
        .padding()
    }
}
