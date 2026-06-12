import SwiftUI

struct SettingsView: View {
    @AppStorage("appearancePreference") private var appearance = "system"
    @State private var hasAPIKey = KeychainStore.hasAPIKey
    // Local mirror of AppLockController.isEnabled — Toggle needs a Binding,
    // UserDefaults-backed statics don't publish.
    @State private var appLockEnabled = AppLockController.isEnabled

    var body: some View {
        List {
            Section("AI") {
                NavigationLink {
                    APIKeyEntryView()
                } label: {
                    LabeledContent("Gemini API key", value: hasAPIKey ? "Key saved •••" : "Not set")
                }
            }

            Section("Manage") {
                NavigationLink("Accounts") { AccountListView() }
                NavigationLink("Categories") { CategoryListView() }
                NavigationLink("Budgets") { BudgetSetupView() }
                NavigationLink("Recurring") { RecurringListView() }
            }

            Section("Data") {
                NavigationLink("Export CSV") { ExportView() }
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }

            Section("Security") {
                Toggle("Require Face ID", isOn: $appLockEnabled)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                Text("Receipts are parsed with Google Gemini using your own API key.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            hasAPIKey = KeychainStore.hasAPIKey
            appLockEnabled = AppLockController.isEnabled
        }
        .onChange(of: appLockEnabled) { _, newValue in
            AppLockController.isEnabled = newValue
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
