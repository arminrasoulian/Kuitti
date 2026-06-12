import SwiftUI
import SwiftData

@main
struct KuittiApp: App {
    let container: ModelContainer
    @State private var environment = AppEnvironment()

    init() {
        do {
            container = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                migrationPlan: KuittiMigrationPlan.self
            )
        } catch {
            // A personal app with an unopenable store has no graceful path; crash with context.
            fatalError("Failed to open the data store: \(error)")
        }
        do {
            try SeedDataService.seedIfNeeded(context: container.mainContext)
        } catch {
            Log.persistence.error("Seeding failed: \(String(describing: error))")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment)
        }
        .modelContainer(container)
    }
}
