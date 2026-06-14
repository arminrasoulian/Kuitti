import SwiftUI
import SwiftData
import UIKit

struct RootTabView: View {
    /// Onboarding is suppressed until the launch splash has finished, so a new
    /// user's onboarding sheet never presents underneath the splash.
    var splashFinished: Bool = true

    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearancePreference") private var appearance = "system"
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    // Receipt shared in from another app / picked from the library.
    @State private var confirmingImport: ImageBatch?   // shown for the external (share) path
    @State private var runningImport: ImageBatch?      // hosts the import flow
    @State private var confirmedBatch: ImageBatch?     // staged across the confirm-sheet dismiss
    @State private var showOnboarding = false          // released once the splash finishes

    private struct ImageBatch: Identifiable {
        let id = UUID()
        let images: [UIImage]
    }

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
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { hasOnboarded = true; showOnboarding = false }
        }
        // A receipt image/PDF "Copy to Kuitti"'d or opened from Files. (When a top-row Share
        // Extension is added later, it would drain its App-Group inbox here too — see
        // ReceiptImportCoordinator.)
        .onOpenURL { url in handleIncomingFile(url) }
        .onChange(of: env.receiptImport.pending?.id) { _, _ in
            guard let pending = env.receiptImport.pending else { return }
            let batch = ImageBatch(images: pending.images)
            if pending.needsConfirmation {
                confirmingImport = batch
            } else {
                runningImport = batch
            }
            env.receiptImport.clear()
        }
        // Present the flow only after the confirm sheet has fully dismissed (avoids a
        // sheet→cover presentation race).
        .sheet(item: $confirmingImport, onDismiss: {
            if let batch = confirmedBatch {
                confirmedBatch = nil
                runningImport = batch
            }
        }) { batch in
            ImportConfirmView(
                images: batch.images,
                onImport: { confirmedBatch = batch; confirmingImport = nil },
                onCancel: { confirmingImport = nil }
            )
        }
        .fullScreenCover(item: $runningImport) { batch in
            ReceiptImportNavigator(initialImages: batch.images)
        }
        .task {
            // Hold onboarding and the App Lock prompt until the splash has
            // played, so neither pops over the launch animation. (The splash
            // covers content meanwhile, so nothing leaks.)
            if splashFinished { releaseAfterSplash() }
            materializeRecurring()
            env.duplicates.refresh(context: modelContext)
            env.modelCatalog.refresh()
        }
        .onChange(of: splashFinished) { _, finished in
            if finished { releaseAfterSplash() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                env.appLock.lockIfEnabled()
            case .active:
                materializeRecurring()
                env.duplicates.refresh(context: modelContext)
                env.modelCatalog.refresh()
            default:
                break
            }
        }
    }

    /// Once the launch splash has played, present onboarding (new users) and/or
    /// engage App Lock. Driven by real `@State` so the cover presents reliably.
    private func releaseAfterSplash() {
        if !hasOnboarded { showOnboarding = true }
        env.appLock.lockIfEnabled()
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private func handleIncomingFile(_ url: URL) {
        // LSSupportsOpeningDocumentsInPlace is false, so the system copies the file into the
        // app's Inbox — readable directly (no security-scoped access) and ours to clean up.
        let images = ReceiptFileLoader.images(from: url)
        try? FileManager.default.removeItem(at: url)
        guard !images.isEmpty else { return }
        env.receiptImport.request(images: images, needsConfirmation: true)
    }

    private func materializeRecurring() {
        do {
            try RecurringService.materializeDue(context: modelContext)
        } catch {
            Log.persistence.error("Recurring materialization failed: \(String(describing: error))")
        }
    }
}
