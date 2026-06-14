import SwiftUI

/// Shared model picker for the Settings "AI Model" screen and onboarding. Populated from the
/// live `ModelCatalog`; renders the no-key / loading / failed / empty states, and keeps a
/// selected id that's no longer in Google's list visible as "(unavailable)" rather than
/// silently resetting it. Self-contained labeled row so it drops into a Form section or a
/// plain VStack identically.
struct AIModelPicker: View {
    let catalog: ModelCatalog
    /// Whether a key is available (saved, or being entered) — drives the empty-state hint.
    let hasKey: Bool
    @Binding var selection: String

    var body: some View {
        HStack {
            Text("Model")
            Spacer()
            if catalog.models.isEmpty {
                status
            } else {
                Picker("Model", selection: $selection) {
                    // Keep a removed/region-gated selection valid so the Picker doesn't reset it.
                    if !selection.isEmpty && !catalog.models.contains(where: { $0.id == selection }) {
                        Text("\(selection) (unavailable)").tag(selection)
                    }
                    ForEach(catalog.models) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if catalog.state == .loading {
            ProgressView()
        } else if catalog.state == .failed {
            Text("Couldn't load").foregroundStyle(.secondary)
        } else if !hasKey {
            Text("Add a key to load").foregroundStyle(.secondary)
        } else {
            Text("None available").foregroundStyle(.secondary)
        }
    }
}
