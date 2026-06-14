import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearancePreference") private var appearance = "system"
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
            NavigationStack { TransactionListView() }
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle.fill") }
            NavigationStack { ScanHubView() }
                .tabItem { Label("Scan", systemImage: "doc.viewfinder.fill") }
            NavigationStack { ProductListView() }
                .tabItem { Label("Products", systemImage: "basket.fill") }
                .badge(env.duplicates.count)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .preferredColorScheme(preferredScheme)
        .overlay {
            if env.appLock.isLocked {
                AppLockGateView()
            }
        }
        .fullScreenCover(isPresented: needsOnboarding) {
            OnboardingView { hasOnboarded = true }
        }
        .task {
            env.appLock.lockIfEnabled()
            materializeRecurring()
            env.duplicates.refresh(context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                env.appLock.lockIfEnabled()
            case .active:
                materializeRecurring()
                env.duplicates.refresh(context: modelContext)
            default:
                break
            }
        }
    }

    private var needsOnboarding: Binding<Bool> {
        Binding(get: { !hasOnboarded }, set: { if !$0 { hasOnboarded = true } })
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private func materializeRecurring() {
        do {
            try RecurringService.materializeDue(context: modelContext)
        } catch {
            Log.persistence.error("Recurring materialization failed: \(String(describing: error))")
        }
    }
}
