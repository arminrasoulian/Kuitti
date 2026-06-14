import SwiftUI

/// The "AI Model" settings screen: provider, model, and API key. Provider/model persist
/// immediately on change (like the Appearance picker); only the key — a paste-once secret with
/// a Test step — sits behind an explicit Save. The model list loads live from the provider.
struct APIKeyEntryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var isRevealed = false
    @State private var testState: TestState = .idle
    @State private var hasExistingKey = KeychainStore.hasAPIKey
    @State private var errorMessage: String?
    @State private var provider = AISettings.provider
    @State private var selectedModel = AISettings.modelID

    private enum TestState: Equatable {
        case idle, testing, success, failure
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $provider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
            } header: {
                Text("Provider")
            } footer: {
                Text("Kuitti uses Google Gemini today; more providers may be added later.")
            }

            Section {
                HStack {
                    keyField
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isRevealed ? "Hide key" : "Show key")
                }
            } header: {
                Text("\(provider.displayName) API key")
            } footer: {
                Text("Get a key at aistudio.google.com → API keys. The free tier is enough. The key is stored only in this device's Keychain.")
            }

            Section {
                Button {
                    testKey()
                } label: {
                    if testState == .testing {
                        HStack {
                            Text("Testing…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Test key")
                    }
                }
                .disabled(trimmedKey.isEmpty || testState == .testing)

                switch testState {
                case .success:
                    Label("Key works", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure:
                    Label("Key was rejected", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                case .idle, .testing:
                    EmptyView()
                }
            }

            Section {
                AIModelPicker(catalog: env.modelCatalog,
                              hasKey: hasExistingKey || !trimmedKey.isEmpty,
                              selection: $selectedModel)
            } header: {
                Text("Model")
            } footer: {
                Text("Loaded live from \(provider.displayName) — new models appear automatically. Used to read your receipts.")
            }

            Section {
                Button("Save") { save() }
                    .disabled(trimmedKey.isEmpty)
            } footer: {
                Text("Your provider and model choices are saved automatically; Save stores the API key.")
            }

            if hasExistingKey {
                Section {
                    Button("Remove key", role: .destructive) {
                        KeychainStore.deleteAPIKey()
                        hasExistingKey = false
                        key = ""
                        testState = .idle
                    }
                } footer: {
                    Text("Removing the key disables receipt scanning until a new one is saved.")
                }
            }
        }
        .navigationTitle("AI Model")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: key) { _, _ in testState = .idle }
        .onChange(of: provider) { _, newValue in AISettings.provider = newValue }
        .onChange(of: selectedModel) { _, newValue in AISettings.modelID = newValue }
        .task { env.modelCatalog.refresh() }
        .alert("Couldn't save the key", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var keyField: some View {
        // Toggling field type loses focus, which is fine for a paste-once value.
        if isRevealed {
            TextField("Paste your key", text: $key)
        } else {
            SecureField("Paste your key", text: $key)
        }
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func testKey() {
        testState = .testing
        let candidate = trimmedKey
        Task {
            // A successful ListModels both proves the key and yields the catalog to adopt.
            let fetched = try? await env.gemini.listModels(key: candidate)
            // The field may have been edited while the probe ran.
            guard trimmedKey == candidate else { return }
            if let fetched, !fetched.isEmpty {
                env.modelCatalog.adopt(fetched)
                testState = .success
            } else {
                testState = .failure
            }
        }
    }

    private func save() {
        do {
            try KeychainStore.saveAPIKey(trimmedKey)
            hasExistingKey = true
            // A new key may unlock a different model list.
            env.modelCatalog.refresh()
            dismiss()
        } catch {
            errorMessage = (error as? UserPresentable)?.userMessage ?? "Saving failed. Try again."
        }
    }
}
