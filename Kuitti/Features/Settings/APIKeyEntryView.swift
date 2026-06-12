import SwiftUI

struct APIKeyEntryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var isRevealed = false
    @State private var testState: TestState = .idle
    @State private var hasExistingKey = KeychainStore.hasAPIKey
    @State private var errorMessage: String?

    private enum TestState: Equatable {
        case idle, testing, success, failure
    }

    var body: some View {
        Form {
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
                Text("Gemini API key")
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
                Button("Save") { save() }
                    .disabled(trimmedKey.isEmpty)
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
        .navigationTitle("Gemini API key")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: key) { _, _ in testState = .idle }
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
            let isValid = await env.gemini.validate(key: candidate)
            // The field may have been edited while the probe ran.
            guard trimmedKey == candidate else { return }
            testState = isValid ? .success : .failure
        }
    }

    private func save() {
        do {
            try KeychainStore.saveAPIKey(trimmedKey)
            dismiss()
        } catch {
            errorMessage = (error as? UserPresentable)?.userMessage ?? "Saving failed. Try again."
        }
    }
}
