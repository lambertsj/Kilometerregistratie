import SwiftUI
import SwiftData

/// Eén-tik classificatie voor een automatisch gedetecteerde rit: de
/// gebruiker tikt een categorie aan en de rit is direct opgeslagen en
/// geleerd voor deze adrescombinatie. Raakt bewust alleen `category` aan —
/// nooit datums/afstand/adressen — zodat dit veilig samengaat met
/// `AutomaticTripMerge`, dat een net afgesloten rit soms alsnog heropent
/// (zie `LocationTrackingService.resumeRecording(reopening:at:)`).
struct TripQuickClassifyView: View {
    let trip: Trip
    let onFinished: () -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(routeText)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("\(trip.distanceKm.formatted(.number.precision(.fractionLength(0...1)))) km · \(trip.startDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                .accessibilityElement(children: .combine)

                VStack(spacing: 12) {
                    ForEach(TripCategory.allCases) { category in
                        Button {
                            classify(as: category)
                        } label: {
                            Label(category.displayName, systemImage: category.iconName)
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(category == trip.category ? category.color : Color(.tertiarySystemFill))
                        .foregroundStyle(category == trip.category ? .white : .primary)
                        .accessibilityLabel(String(format: String(localized: "Classificeer als %@", comment: "Toegankelijkheidslabel op een categorieknop; %@ is de categorienaam"), category.displayName))
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Nieuwe rit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { onFinished() }
                }
            }
        }
    }

    private var routeText: String {
        if trip.startAddress.isEmpty, trip.endAddress.isEmpty {
            return String(localized: "Onbekende route", comment: "Route onbekend: geen begin- of eindadres")
        }
        let from = trip.startAddress.isEmpty ? "?" : trip.startAddress
        let to = trip.endAddress.isEmpty ? "?" : trip.endAddress
        return "\(from) → \(to)"
    }

    private func classify(as category: TripCategory) {
        _ = try? TripWriteService(context: context).update(trip) { $0.category = category }
        if let key = TripClassifier.routeKey(startAddress: trip.startAddress, endAddress: trip.endAddress) {
            try? ClassificationRuleRepository(context: context).learn(routeKey: key, category: category)
        }
        onFinished()
    }
}

#Preview {
    TripQuickClassifyView(
        trip: Trip(startDate: .now, startAddress: "Thuis", endAddress: "Kantoor", distanceKm: 12, isAutomaticallyRecorded: true),
        onFinished: {}
    )
    .modelContainer(for: AppSchema.models, inMemory: true)
}
