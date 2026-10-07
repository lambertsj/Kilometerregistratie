import SwiftUI
import SwiftData
import Charts

/// Dashboard: verdeling zakelijk/woon-werk/privé, de 500 km-privételler
/// voor het lopende jaar en de geschatte kilometervergoeding.
struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query private var allSettings: [AppSettings]

    @State private var period: PeriodFilter = .month

    private var settings: AppSettings {
        allSettings.first ?? AppSettings.fetchOrCreate(in: context)
    }

    /// Ritten zonder tombstones (zie `Trip.isDeleted`).
    private var visibleTrips: [Trip] {
        trips.filter { !$0.isDeleted }
    }

    private var periodSummaries: [TripSummary] {
        let start = period.startDate()
        return visibleTrips
            .filter { start == nil || $0.startDate >= start! }
            .map { TripSummary(startDate: $0.startDate, distanceKm: $0.distanceKm, category: $0.category) }
    }

    private var breakdown: [(category: TripCategory, km: Double)] {
        let totals = MileageStatistics.breakdown(periodSummaries)
        // Vaste categorievolgorde, niet gesorteerd op grootte: kleuren en
        // volgorde blijven zo stabiel bij elk filter.
        return TripCategory.allCases.compactMap { category in
            guard let km = totals[category], km > 0 else { return nil }
            return (category, km)
        }
    }

    private var totalKm: Double {
        MileageStatistics.totalKm(periodSummaries)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Periode", selection: $period) {
                        ForEach(PeriodFilter.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    if periodSummaries.isEmpty {
                        ContentUnavailableView(
                            "Nog geen ritten",
                            systemImage: "chart.pie",
                            description: Text("Zodra je ritten registreert zie je hier de verdeling en totalen.")
                        )
                        .padding(.top, 40)
                    } else {
                        distributionCard
                        reimbursementCard
                    }
                    // De privékilometergrens is een Nederlands begrip; regio's
                    // die hem niet kennen (Duitsland) tonen de kaart niet.
                    if settings.ruleSet.privateKmYearLimit != nil {
                        privateLimitCard
                    }
                    validationCard
                }
                .padding()
                .readableWidth()
            }
            .navigationTitle("Dashboard")
            .background(Theme.canvas.ignoresSafeArea())
        }
    }

    // MARK: - Verdeling

    private var distributionCard: some View {
        DashboardCard(title: "Verdeling") {
            HStack(spacing: 20) {
                Chart(breakdown, id: \.category) { item in
                    SectorMark(
                        angle: .value("Kilometers", item.km),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(item.category.color)
                    .cornerRadius(3)
                }
                .frame(width: 130, height: 130)
                .chartBackground { _ in
                    VStack {
                        Text(totalKm.formatted(.number.precision(.fractionLength(0))))
                            .font(.title3.bold())
                        Text("km")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Taartdiagram kilometerverdeling")

                // Directe labels naast het diagram zodat identiteit nooit
                // alleen van kleur afhangt.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(breakdown, id: \.category) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.category.color)
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.category.displayName)
                                    .font(.caption.weight(.medium))
                                Text("\(item.km.formatted(.number.precision(.fractionLength(0...1)))) km · \(percentage(item.km))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func reimbursementDetailText(businessKm: Double) -> String {
        let template = String(localized: "%1$@ zakelijke km × %2$@", comment: "Toelichting bij de kilometervergoeding: %1$@ is het aantal zakelijke km, %2$@ het tarief per km")
        return String(
            format: template,
            businessKm.formatted(.number.precision(.fractionLength(0...1))),
            settings.reimbursementRatePerKm.formatted(.currency(code: "EUR"))
        )
    }

    private func percentage(_ km: Double) -> String {
        guard totalKm > 0 else { return "0%" }
        return (km / totalKm).formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Vergoeding

    private var reimbursementCard: some View {
        let businessKm = MileageStatistics.totalKm(periodSummaries, category: .business)
        let amount = MileageStatistics.reimbursement(businessKm: businessKm, ratePerKm: settings.reimbursementRatePerKm)
        return DashboardCard(title: "Kilometervergoeding") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(amount.formatted(.currency(code: "EUR")))
                        .font(.figure(.title))
                    Text(reimbursementDetailText(businessKm: businessKm))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "eurosign.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.ok)
            }
        }
    }

    // MARK: - 500 km-teller

    private var privateLimitCard: some View {
        // Altijd het lopende kalenderjaar, los van het periode-filter:
        // dat is waar de fiscale grens over gaat.
        let year = Calendar.current.component(.year, from: .now)
        let yearSummaries = visibleTrips.map {
            TripSummary(startDate: $0.startDate, distanceKm: $0.distanceKm, category: $0.category)
        }
        let privateKm = MileageStatistics.privateKm(in: year, trips: yearSummaries)
        // De kaart wordt alleen getoond als de regio een grens kent; de
        // fallback houdt het bestaande Nederlandse gedrag aan.
        let limit = settings.ruleSet.privateKmYearLimit ?? MileageStatistics.privateKmYearLimit
        let status = MileageStatistics.privateKmStatus(forYearTotal: privateKm, limit: limit)

        let title = String(format: String(localized: "Privékilometers %lld", comment: "Titel van de 500 km-kaart; %lld is het jaartal"), year)
        return DashboardCard(titleText: title) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(privateKm.formatted(.number.precision(.fractionLength(0...1)))) km")
                        .font(.figure(.title))
                        .foregroundStyle(statusColor(status))
                    Spacer()
                    Text(String(format: String(localized: "grens %lld km", comment: "Bijschrift bij de 500 km-voortgangsbalk; %lld is de grens"), Int(limit)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(privateKm, limit), total: limit)
                    .tint(statusColor(status))
                    .scaleEffect(x: 1, y: 1.6)
                    .padding(.vertical, 2)

                switch status {
                case .ok:
                    Text("Je zit ruim onder de 500 km-grens voor bijtellingsvrij rijden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .nearingLimit:
                    Label("Let op: je nadert de 500 km-grens. Boven de grens geldt bijtelling voor het hele jaar.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                case .overLimit:
                    Label(overLimitText(privateKm: privateKm), systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
        }
    }

    // MARK: - Registratie controleren

    /// Kleine kaart die naar `LogValidationView` doorlinkt, met de headline-
    /// toestand van het lopende belastingjaar zodat je zonder erin te tappen
    /// al ziet of er iets aandacht nodig heeft.
    private var validationCard: some View {
        let year = Calendar.current.component(.year, from: .now)
        let issues = (try? LogValidationRepository(context: context)
            .issues(forTaxYear: year, ruleSet: settings.ruleSet)) ?? []
        let headline = LogHeadlineState(issues: issues)

        return NavigationLink {
            LogValidationView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: headline.iconName)
                    .font(.title2)
                    .foregroundStyle(headline.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: String(localized: "Controle %lld", comment: "Kaart naar het validatiescherm; %lld is het belastingjaar"), year))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(headline.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .themedCard()
        }
        .buttonStyle(.plain)
    }

    private func overLimitText(privateKm: Double) -> String {
        let template = String(localized: "Grens overschreden: met %@ privékilometers vervalt de vrijstelling van bijtelling dit jaar.", comment: "Melding als de 500 km-privégrens overschreden is; %@ is het aantal privékilometers")
        return String(format: template, privateKm.formatted(.number.precision(.fractionLength(0))))
    }

    private func statusColor(_ status: MileageStatistics.PrivateKmStatus) -> Color {
        switch status {
        case .ok: Theme.ok
        case .nearingLimit: Theme.warning
        case .overLimit: Theme.danger
        }
    }
}

/// Witte kaart met titel, zoals de systeem-instellingenkaarten.
///
/// Twee initializers: de meeste titels zijn statische, gelokaliseerde tekst
/// (via `LocalizedStringResource`); de 500 km-kaart bouwt zijn titel zelf op
/// met een jaartal erin (`String(format:)`) en moet dus verbatim getoond
/// worden in plaats van nogmaals als sleutel opgezocht.
struct DashboardCard<Content: View>: View {
    let title: Text
    let content: Content

    init(title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.content = content()
    }

    init(titleText: String, @ViewBuilder content: () -> Content) {
        self.title = Text(titleText)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
