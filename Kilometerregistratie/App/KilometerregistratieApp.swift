import SwiftUI
import SwiftData

@main
struct KilometerregistratieApp: App {
    // SwiftData is bewust gekozen boven Core Data: de app target iOS 17+,
    // en de benodigde queries (filteren op periode/categorie/voertuig,
    // sommeren van afstanden) zijn goed uit te drukken met #Predicate en
    // in-memory aggregatie. Alle data blijft lokaal; CloudKit-sync staat uit.
    let container: ModelContainer = {
        let schema = AppSchema.schema
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppSchema.migrationPlan,
                configurations: [configuration]
            )
        } catch {
            fatalError("Kan lokale database niet openen: \(error)")
        }
    }()

    @State private var locationService = LocationTrackingService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationService)
                .task {
                    locationService.configure(context: container.mainContext)
                    locationService.applySettings(AppSettings.fetchOrCreate(in: container.mainContext))
                    // Sluit of hervat een rit die nog "actief" stond toen de
                    // app de vorige keer werd afgesloten of gekilld.
                    await locationService.resumeIfNeeded(context: container.mainContext)
                }
                .onChange(of: scenePhase) { _, phase in
                    // iOS kan de app tijdens een rit hebben opgeschort, waarbij
                    // de watchdog-timer stilstaat. Controleer direct bij terugkeer.
                    guard phase == .active else { return }
                    Task { await locationService.appDidBecomeActive() }
                }
        }
        .modelContainer(container)
    }
}
