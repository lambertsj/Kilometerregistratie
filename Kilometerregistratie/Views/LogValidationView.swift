import SwiftUI
import SwiftData

/// Toont of de rittenregistratie van het huidige belastingjaar sluitend en
/// compleet is, met de gevonden meldingen gegroepeerd op ernst.
///
/// Dit scherm stelt alleen vast wát er in het dossier ontbreekt of niet
/// aansluit; het doet geen uitspraak over wat een belastingdienst daarmee zou
/// doen en is geen garantie dat het rapport daarmee compleet is (zie de
/// `Hinweis`/opmerking onderaan).
struct LogValidationView: View {
    @Environment(\.modelContext) private var context
    @Query private var allSettings: [AppSettings]
    @Query(sort: \Trip.startDate) private var trips: [Trip]

    @State private var selectedTripID: UUID?

    private var settings: AppSettings {
        allSettings.first ?? AppSettings.fetchOrCreate(in: context)
    }

    private var ruleSet: any RegionRuleSet { settings.ruleSet }

    private var taxYear: Int {
        Calendar.current.component(.year, from: .now)
    }

    private var issues: [LogIssue] {
        (try? LogValidationRepository(context: context).issues(forTaxYear: taxYear, ruleSet: ruleSet)) ?? []
    }

    private var headline: LogHeadlineState {
        LogHeadlineState(issues: issues)
    }

    private var groupedIssues: [(severity: IssueSeverity, issues: [LogIssue])] {
        let severities: [IssueSeverity] = [.blocking, .warning]
        return severities.compactMap { severity in
            let matching = issues.filter { $0.severity == severity }
            return matching.isEmpty ? nil : (severity, matching)
        }
    }

    /// Geen eigen `NavigationStack`: dit scherm wordt als push-bestemming
    /// gebruikt (zie `DashboardView.validationCard` en `ReportView`), net
    /// als `VehiclesView`/`BackupView`. Een eigen stack zou een tweede,
    /// geneste navigatiebalk opleveren.
    var body: some View {
        Group {
            if issues.isEmpty {
                ContentUnavailableView(
                    headline.title,
                    systemImage: headline.iconName,
                    description: Text(headline.detail)
                )
            } else {
                List {
                    Section {
                        headlineCard
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    ForEach(groupedIssues, id: \.severity) { group in
                        Section {
                            ForEach(group.issues) { issue in
                                IssueRow(issue: issue, trip: trip(for: issue.primaryTripID))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedTripID = issue.primaryTripID
                                    }
                            }
                        } header: {
                            Label(group.severity.displayName, systemImage: group.severity.iconName)
                                .foregroundStyle(group.severity.color)
                        }
                    }

                    Section {
                        Text(disclaimer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(String(format: String(localized: "Controle %lld", comment: "Titel van het validatiescherm; %lld is het belastingjaar"), taxYear))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedTripID) { tripID in
            if let trip = trips.first(where: { $0.id == tripID }) {
                TripDetailView(trip: trip)
            }
        }
    }

    private var headlineCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: headline.iconName)
                .font(.title2)
                .foregroundStyle(headline.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline.title)
                    .font(.headline)
                Text(headline.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(headline.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func trip(for id: UUID?) -> Trip? {
        guard let id else { return nil }
        return trips.first { $0.id == id }
    }

    /// Nederlandstalige toelichting voor de Nederlandse regio, Duitstalige
    /// voor de Duitse — net als het `Hinweis`-blok op het rapportscherm.
    private var disclaimer: String {
        switch settings.taxRegion {
        case .netherlands:
            "Deze controle stelt alleen vast wat er in de registratie ontbreekt of niet aansluit. Je bent zelf verantwoordelijk voor de volledigheid en juistheid van de rittenregistratie; dit is geen belastingadvies en geen garantie dat de Belastingdienst het rapport accepteert."
        case .germany:
            "Diese Prüfung stellt lediglich fest, was im Fahrtenbuch fehlt oder nicht übereinstimmt. Sie sind selbst für die Vollständigkeit und Richtigkeit des Fahrtenbuchs verantwortlich; dies ist keine Steuerberatung und keine Garantie, dass das Finanzamt das Fahrtenbuch anerkennt."
        }
    }
}

private struct IssueRow: View {
    let issue: LogIssue
    let trip: Trip?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.summary)
                    .font(.subheadline)
                if let trip {
                    Text(trip.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if trip != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        LogValidationView()
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
}
