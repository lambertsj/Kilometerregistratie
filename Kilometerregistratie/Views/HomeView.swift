import SwiftUI
import SwiftData
import UIKit

/// Hoofdscherm: grote START/STOP-knop met de belangrijkste statistieken
/// (km deze maand, 500 km-privételler) direct in beeld.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(LocationTrackingService.self) private var locationService
    private let recorder = TripRecorder()
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    /// De lopende rit, rechtstreeks uit de database. Daardoor volgt het
    /// scherm ook ritten die op de achtergrond automatisch starten of
    /// stoppen, in plaats van een eigen kopie bij te houden.
    private var activeTrip: Trip? {
        trips.first { $0.endDate == nil && $0.deletedAt == nil }
    }

    /// De zojuist gestopte rit waarvoor het afrondformulier getoond wordt.
    @State private var finishedTrip: Trip?
    @State private var showsAddTripSheet = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                statsHeader
                Spacer()
                startStopButton
                if activeTrip != nil {
                    Button("Rit annuleren", role: .destructive) {
                        locationService.cancelRecording()
                        attempt { try recorder.cancel(context: context) }
                    }
                    .font(.subheadline)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Kilometerregistratie")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsAddTripSheet = true
                    } label: {
                        Label("Rit toevoegen", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $finishedTrip) { trip in
                TripFormView(trip: trip, mode: .finishRecorded)
            }
            .sheet(isPresented: $showsAddTripSheet) {
                TripFormView(trip: nil, mode: .addManually)
            }
            .sheet(
                item: Binding(
                    get: { locationService.pendingClassificationTrip },
                    set: { if $0 == nil { locationService.clearPendingClassification() } }
                )
            ) { trip in
                TripQuickClassifyView(trip: trip) {
                    locationService.clearPendingClassification()
                }
            }
            .alert("Er ging iets mis", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(
                "Locatieregistratie gestopt",
                isPresented: Binding(
                    get: { locationService.currentIssue != nil },
                    set: { isPresented in if !isPresented { locationService.dismissIssue() } }
                )
            ) {
                Button("Open Instellingen") { openSettings() }
                Button("OK", role: .cancel) { locationService.dismissIssue() }
            } message: {
                Text(locationIssueMessage)
            }
        }
    }

    private var locationIssueMessage: String {
        switch locationService.currentIssue {
        case .permissionRevokedDuringRecording:
            String(localized: "Locatietoestemming is ingetrokken; de lopende rit is afgesloten op de laatst bekende positie. Vul de rit zo nodig handmatig aan, of zet locatietoegang weer aan in Instellingen voor automatische registratie.", comment: "Melding: locatietoestemming ingetrokken tijdens opname")
        case .locationServicesDisabled:
            String(localized: "Locatievoorzieningen staan uit op dit toestel. Zet ze aan via Instellingen > Privacy en beveiliging > Locatievoorzieningen om ritten automatisch te registreren.", comment: "Melding: locatievoorzieningen systeemwide uit")
        case nil:
            ""
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Statistieken

    /// Ritten zonder tombstones (zie `Trip.isDeleted`).
    private var visibleTrips: [Trip] {
        trips.filter { !$0.isDeleted }
    }

    private var currentMonthKm: Double {
        let calendar = Calendar.current
        let now = Date.now
        return visibleTrips
            .filter { calendar.isDate($0.startDate, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.distanceKm }
    }

    private var privateKmThisYear: Double {
        let summaries = visibleTrips.map {
            TripSummary(startDate: $0.startDate, distanceKm: $0.distanceKm, category: $0.category)
        }
        return MileageStatistics.privateKm(in: Calendar.current.component(.year, from: .now), trips: summaries)
    }

    private var statsHeader: some View {
        HStack(spacing: 12) {
            StatCard(
                title: String(localized: "Deze maand", comment: "Statistiekkaart: kilometers deze maand"),
                value: currentMonthKm.formatted(.number.precision(.fractionLength(0...1))),
                unit: "km",
                color: .accentColor
            )
            privateCounterCard
        }
    }

    private var privateCounterCard: some View {
        let km = privateKmThisYear
        let status = MileageStatistics.privateKmStatus(forYearTotal: km)
        let color: Color = switch status {
        case .ok: .green
        case .nearingLimit: .orange
        case .overLimit: .red
        }
        let unit = String(
            format: String(localized: "van %lld km", comment: "Eenheid bij de privékilometerteller: 'van 500 km'; %lld is de grens"),
            Int(MileageStatistics.privateKmYearLimit)
        )
        return StatCard(
            title: String(localized: "Privé dit jaar", comment: "Statistiekkaart: privékilometers dit jaar"),
            value: km.formatted(.number.precision(.fractionLength(0...1))),
            unit: unit,
            color: color
        )
    }

    // MARK: - START/STOP

    private var startStopButton: some View {
        VStack(spacing: 16) {
            if let trip = activeTrip {
                TimelineView(.periodic(from: trip.startDate, by: 1)) { timeline in
                    Text(elapsedText(since: trip.startDate, now: timeline.date))
                        .font(.system(.title, design: .monospaced))
                        .contentTransition(.numericText())
                }
                .accessibilityLabel("Verstreken rittijd")

                if locationService.recordingSource != nil {
                    Label(
                        "\(locationService.liveDistanceKm.formatted(.number.precision(.fractionLength(1)))) km",
                        systemImage: "location.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Afstand tot nu toe")
                }
            }

            Button {
                toggleRecording()
            } label: {
                Text(activeTrip == nil ? "START" : "STOP")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 180, height: 180)
                    .background(
                        Circle()
                            .fill(activeTrip == nil ? Color.green : Color.red)
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(activeTrip == nil
                ? String(localized: "Start rit", comment: "Toegankelijkheidslabel: rit starten")
                : String(localized: "Stop rit", comment: "Toegankelijkheidslabel: rit stoppen")
            )
            .sensoryFeedback(.impact, trigger: activeTrip != nil)

            if locationDenied {
                Label(
                    "Locatietoegang is uitgeschakeld. Ritten worden zonder route geregistreerd; vul de afstand handmatig in of zet locatie aan in de Instellingen-app.",
                    systemImage: "location.slash"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        }
    }

    private var locationDenied: Bool {
        locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted
    }

    private func toggleRecording() {
        if activeTrip == nil {
            attempt {
                if let trip = try recorder.start(context: context, vehicle: vehicles.first) {
                    locationService.beginRouteRecording(for: trip)
                }
            }
        } else {
            // Eerst de GPS-opname afronden (route, afstand, adressen),
            // daarna de rit afsluiten en het afrondformulier tonen.
            Task {
                await locationService.stopRecording(endDate: .now)
                attempt { finishedTrip = try recorder.stop(context: context) }
            }
        }
    }

    private func attempt(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func elapsedText(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}

/// Compacte statistiekkaart voor het hoofdscherm.
struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: AppSchema.models, inMemory: true)
        .environment(LocationTrackingService())
}
