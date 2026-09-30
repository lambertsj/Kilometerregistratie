import SwiftUI
import SwiftData

/// Hoofdnavigatie van de app, met eenmalige privacy-onboarding.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Registreren", systemImage: "car.fill")
                }
            TripListView()
                .tabItem {
                    Label("Ritten", systemImage: "list.bullet")
                }
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.pie.fill")
                }
            ReportView()
                .tabItem {
                    Label("Rapport", systemImage: "doc.text")
                }
            SettingsView()
                .tabItem {
                    Label("Instellingen", systemImage: "gearshape")
                }
        }
        .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
            OnboardingView { region in
                // Ook bij overslaan wordt de regio vastgelegd: dan is het het
                // voorstel op basis van de toestelregio. Bestaande gebruikers
                // zien deze flow niet meer en blijven op Nederland staan (de
                // default van het model).
                let settings = AppSettings.fetchOrCreate(in: context)
                settings.taxRegion = region
                try? context.save()
                hasCompletedOnboarding = true
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AppSchema.models, inMemory: true)
        .environment(LocationTrackingService())
}
