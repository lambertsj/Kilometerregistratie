import SwiftUI
import SwiftData

/// Filterbare ritlijst: periode, categorie en voertuig.
struct TripListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    @State private var periodFilter: PeriodFilter = .all
    @State private var categoryFilter: TripCategory?
    @State private var vehicleFilter: UUID?
    @State private var errorMessage: String?

    /// Ritten zonder de tombstones van een regio met bewaarplicht: die zijn
    /// verwijderd en horen nergens in de UI meer te verschijnen.
    private var visibleTrips: [Trip] {
        trips.filter { !$0.isDeleted }
    }

    private var filteredTrips: [Trip] {
        let start = periodFilter.startDate()
        return visibleTrips.filter { trip in
            (start == nil || trip.startDate >= start!)
                && (categoryFilter == nil || trip.category == categoryFilter)
                && (vehicleFilter == nil || trip.vehicle?.id == vehicleFilter)
        }
    }

    private var filteredTotalKm: Double {
        filteredTrips.reduce(0) { $0 + $1.distanceKm }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredTrips.isEmpty {
                    ContentUnavailableView(
                        "Geen ritten",
                        systemImage: "car",
                        description: Text(visibleTrips.isEmpty
                            ? "Start een rit op het registratiescherm of voeg er handmatig één toe."
                            : "Geen ritten binnen dit filter.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(filteredTrips) { trip in
                                NavigationLink(value: trip.id) {
                                    TripRow(trip: trip)
                                }
                            }
                            .onDelete(perform: deleteTrips)
                        } header: {
                            // "km" en "·" zijn geen woorden die vertaald hoeven
                            // te worden; alleen `tripsCountText` levert een
                            // vertaalde tekst, met correct enkelvoud/meervoud.
                            Text("\(tripsCountText(filteredTrips.count)) · \(filteredTotalKm.formatted(.number.precision(.fractionLength(0...1)))) km")
                        }
                    }
                    .navigationDestination(for: UUID.self) { tripID in
                        if let trip = visibleTrips.first(where: { $0.id == tripID }) {
                            TripDetailView(trip: trip)
                        }
                    }
                }
            }
            .navigationTitle("Ritten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ritten")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Periode", selection: $periodFilter) {
                        ForEach(PeriodFilter.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(.bar)
            }
            .alert("Er ging iets mis", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Categorie", selection: $categoryFilter) {
                Text("Alle categorieën").tag(TripCategory?.none)
                ForEach(TripCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.iconName)
                        .tag(TripCategory?.some(category))
                }
            }
            if !vehicles.isEmpty {
                Picker("Voertuig", selection: $vehicleFilter) {
                    Text("Alle voertuigen").tag(UUID?.none)
                    ForEach(vehicles) { vehicle in
                        Text(vehicle.name).tag(UUID?.some(vehicle.id))
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: categoryFilter == nil && vehicleFilter == nil
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func deleteTrips(at offsets: IndexSet) {
        do {
            let writer = TripWriteService(context: context)
            for index in offsets {
                try writer.delete(filteredTrips[index])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Eén rij in de ritlijst: datum, van→naar, afstand en categorie.
struct TripRow: View {
    let trip: Trip

    private var routeText: String {
        if trip.startAddress.isEmpty && trip.endAddress.isEmpty {
            return String(localized: "Onbekende route", comment: "Ritregel: geen begin- of eindadres bekend")
        }
        let from = trip.startAddress.isEmpty ? "?" : trip.startAddress
        let to = trip.endAddress.isEmpty ? "?" : trip.endAddress
        return "\(from) → \(to)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(trip.distanceKm.formatted(.number.precision(.fractionLength(0...1)))) km")
                    .font(.subheadline.bold())
            }
            Text(routeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                CategoryBadge(category: trip.category)
                if let vehicle = trip.vehicle {
                    Text(vehicle.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !trip.clientLabel.isEmpty {
                    Text(trip.clientLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TripListView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
