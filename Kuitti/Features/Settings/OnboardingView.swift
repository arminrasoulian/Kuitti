import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void

    @State private var selection = 0
    @State private var key = ""
    @State private var saveErrorMessage: String?

    var body: some View {
        TabView(selection: $selection) {
            welcomePage.tag(0)
            setupPage.tag(1)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color(.systemBackground))
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
                              title: "Scan Finnish receipts",
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
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text("One thing to set up")
                .font(.title.bold())
            Text("Receipt scanning uses Google Gemini with your own free API key from aistudio.google.com. The key is stored only in this device's Keychain.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SecureField("Gemini API key", text: $key)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .padding(.top, 8)
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

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
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
