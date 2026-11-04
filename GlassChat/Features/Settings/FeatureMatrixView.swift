import SwiftUI

struct FeatureMatrixView: View {
    var body: some View {
        List {
            ForEach(FeatureAvailability.allCases, id: \.self) { availability in
                Section(headerTitle(for: availability)) {
                    ForEach(FeatureCatalog.all.filter { $0.availability == availability }) { feature in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(feature.title)
                                    .font(.headline)
                                Spacer()
                                Text(availability.rawValue.capitalized)
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(color(for: availability).opacity(0.15), in: Capsule())
                                    .foregroundStyle(color(for: availability))
                            }
                            Text(feature.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func headerTitle(for availability: FeatureAvailability) -> String {
        switch availability {
        case .implemented: return "Implemented"
        case .planned: return "Planned"
        case .unsupported: return "Unsupported by protocol"
        }
    }

    private func color(for availability: FeatureAvailability) -> Color {
        switch availability {
        case .implemented: return .green
        case .planned: return .orange
        case .unsupported: return .secondary
        }
    }
}
