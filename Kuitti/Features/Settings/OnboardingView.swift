import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void

    @Environment(AppEnvironment.self) private var env

    @State private var selection = 0
    @State private var key = ""
    @State private var saveErrorMessage: String?
    @State private var provider = AISettings.provider
    @State private var selectedModel = AISettings.modelID
    @State private var loadState: LoadState = .idle

    private enum LoadState: Equatable { case idle, loading, loaded, failed }

    var body: some View {
        TabView(selection: $selection) {
            welcomePage.tag(0)
            setupPage.tag(1)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color(.systemBackground))
        .onChange(of: key) { _, _ in loadState = .idle }
        .onChange(of: provider) { _, newValue in AISettings.provider = newValue }
        .onChange(of: selectedModel) { _, newValue in AISettings.modelID = newValue }
    }

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 72, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text("Kuitti")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 20) {
                FeatureBullet(icon: "doc.viewfinder",
                              title: "Scan receipts in any language",
                              detail: "A photo becomes a categorized transaction automatically.")
                FeatureBullet(icon: "chart.line.uptrend.xyaxis",
                              title: "Price history across stores",
                              detail: "See what bananas cost at Lidl versus K-Market over time.")
                FeatureBullet(icon: "lock.iphone",
                              title: "Private by design",
                              detail: "Everything stays on your iPhone.")
            }
            .padding(.top, 16)
            Spacer()
            Button {
                withAnimation { selection = 1 }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .padding(32)
    }

    private var setupPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text("One thing to set up")
                .font(.title.bold())
            Text("Receipt scanning uses an AI model with your own free API key from aistudio.google.com. The key is stored only in this device's Keychain.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            configCard

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button {
                saveAndFinish()
            } label: {
                Text("Save and start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(trimmedKey.isEmpty)
            Button("I'll do this later") { onDone() }
                .padding(.bottom, 24)
        }
        .padding(32)
    }

    /// Provider / key / model grouped into a single rounded card so the paged onboarding stays
    /// visually tidy. The model picker stays empty until the key is entered and "Load models" is
    /// tapped (the catalog can't be fetched without a key).
    private var configCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Provider")
                Spacer()
                Picker("Provider", selection: $provider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            Divider()
            SecureField("API key", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
            Divider()
            HStack {
                AIModelPicker(catalog: env.modelCatalog, hasKey: !trimmedKey.isEmpty, selection: $selectedModel)
                if env.modelCatalog.models.isEmpty {
                    Button("Load") { loadModels() }
                        .font(.subheadline)
                        .disabled(trimmedKey.isEmpty || loadState == .loading)
                }
            }
            if loadState == .failed {
                Text("Couldn't load models — check the key or your connection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadModels() {
        loadState = .loading
        let candidate = trimmedKey
        Task {
            let fetched = try? await env.gemini.listModels(key: candidate)
            guard trimmedKey == candidate else { return }
            if let fetched, !fetched.isEmpty {
                env.modelCatalog.adopt(fetched)
                loadState = .loaded
            } else {
                loadState = .failed
            }
        }
    }

    private func saveAndFinish() {
        do {
            try KeychainStore.saveAPIKey(trimmedKey)
            onDone()
        } catch {
            saveErrorMessage = (error as? UserPresentable)?.userMessage ?? "Saving failed. Try again."
        }
    }
}

private struct FeatureBullet: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
