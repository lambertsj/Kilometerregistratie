import SwiftUI
import SwiftData
import MapKit

/// Detailscherm van één rit: kaart met route (of markers), alle fiscale
/// velden en een bewerkknop.
struct TripDetailView: View {
    let trip: Trip

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Trip.startDate) private var allTrips: [Trip]

    @State private var showsEditSheet = false
    @State private var showsMergeConfirmation = false
    @State private var errorMessage: String?

    /// De rit die chronologisch direct vóór deze rit ligt, kandidaat voor
    /// "voeg samen" wanneer een automatische rit onterecht in tweeën is
    /// gesplitst (bv. een langere stop dan de auto-stop-drempel).
    private var previousTrip: Trip? {
        let visible = allTrips.filter { !$0.isDeleted }
        guard let index = visible.firstIndex(where: { $0.id == trip.id }), index > 0 else { return nil }
        return visible[index - 1]
    }

    private var routePoints: [RoutePoint] {
        guard let data = trip.routeData else { return [] }
        return (try? RoutePolyline.decode(data)) ?? []
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        guard let lat = trip.startLatitude, let lon = trip.startLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var endCoordinate: CLLocationCoordinate2D? {
        guard let lat = trip.endLatitude, let lon = trip.endLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var hasMapContent: Bool {
        routePoints.count >= 2 || startCoordinate != nil || endCoordinate != nil
    }

    var body: some View {
        List {
            if hasMapContent {
                Section {
                    tripMap
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel("Kaart van de rit")
                }
            }

            Section("Rit") {
                LabeledContent("Vertrek", value: trip.startDate.formatted(date: .abbreviated, time: .shortened))
                if let endDate = trip.endDate {
                    LabeledContent("Aankomst", value: endDate.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Afstand", value: "\(trip.distanceKm.formatted(.number.precision(.fractionLength(0...1)))) km")
                LabeledContent("Categorie") {
                    CategoryBadge(category: trip.category)
                }
            }

            Section("Route") {
                LabeledContent("Van", value: trip.startAddress.isEmpty ? "—" : trip.startAddress)
                LabeledContent("Naar", value: trip.endAddress.isEmpty ? "—" : trip.endAddress)
            }

            if trip.startOdometer != nil || trip.endOdometer != nil {
                Section("Kilometerstand") {
                    if let start = trip.startOdometer {
                        LabeledContent("Begin", value: start.formatted(.number.precision(.fractionLength(0))))
                    }
                    if let end = trip.endOdometer {
                        LabeledContent("Eind", value: end.formatted(.number.precision(.fractionLength(0))))
                    }
                }
            }

            if trip.vehicle != nil || !trip.note.isEmpty || !trip.clientLabel.isEmpty {
                Section("Details") {
                    if let vehicle = trip.vehicle {
                        LabeledContent("Voertuig", value: vehicle.name)
                    }
                    if !trip.clientLabel.isEmpty {
                        LabeledContent("Klant/project", value: trip.clientLabel)
                    }
                    if !trip.note.isEmpty {
                        LabeledContent("Notitie", value: trip.note)
                    }
                }
            }

            Section {
                // `LabeledContent`'s `value:` toont altijd verbatim (er is
                // geen lokaliserende overload), dus hier expliciet vertaald.
                LabeledContent("Geregistreerd", value: trip.isAutomaticallyRecorded
                    ? String(localized: "Automatisch", comment: "Hoe de rit is vastgelegd: automatisch")
                    : String(localized: "Handmatig", comment: "Hoe de rit is vastgelegd: handmatig")
                )
            }
        }
            .themedList()
        .navigationTitle(trip.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Bewerk") { showsEditSheet = true }
                    if previousTrip != nil {
                        Button("Voeg samen met vorige rit") { showsMergeConfirmation = true }
                    }
                } label: {
                    Label("Meer", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showsEditSheet) {
            TripFormView(trip: trip, mode: .edit)
        }
        .confirmationDialog(
            "Samenvoegen met vorige rit?",
            isPresented: $showsMergeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Samenvoegen", role: .destructive) { mergeWithPreviousTrip() }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("De twee ritten worden één rit; deze rit wordt daarna verwijderd. Gebruik dit als een automatische rit onterecht in tweeën is gesplitst, bijvoorbeeld door een langere stop.")
        }
        .alert("Er ging iets mis", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func mergeWithPreviousTrip() {
        guard let previousTrip else { return }
        do {
            try TripRepository(context: context).merge(
                trip, into: previousTrip, using: TripWriteService(context: context)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var tripMap: some View {
        Map {
            if routePoints.count >= 2 {
                MapPolyline(coordinates: routePoints.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(Theme.accent, lineWidth: 5)
            }
            if let start = startCoordinate {
                Marker("Vertrek", systemImage: "flag.fill", coordinate: start)
                    .tint(Theme.ok)
            }
            if let end = endCoordinate {
                Marker("Aankomst", systemImage: "flag.checkered", coordinate: end)
                    .tint(Theme.danger)
            }
        }
    }
}
