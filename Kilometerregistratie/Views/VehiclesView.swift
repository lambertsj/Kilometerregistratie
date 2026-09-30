import SwiftUI
import SwiftData

/// Vaste, opgeslagen waarden voor `Vehicle.vehicleType` (vrij tekstveld,
/// zie `Models/Vehicle.swift`). De opgeslagen waarde blijft het Nederlandse
/// woord — net als `TripCategory.rawValue` — en wordt alleen bij het tonen
/// vertaald, zodat bestaande data niet gemigreerd hoeft te worden.
func vehicleTypeDisplayName(_ type: String) -> String {
    switch type {
    case "Auto": String(localized: "Auto", comment: "Voertuigtype: auto")
    case "Bestelbus": String(localized: "Bestelbus", comment: "Voertuigtype: bestelbus")
    case "Motor": String(localized: "Motor", comment: "Voertuigtype: motor")
    case "Fiets": String(localized: "Fiets", comment: "Voertuigtype: fiets")
    case "Anders": String(localized: "Anders", comment: "Voertuigtype: overig")
    default: type // vrij ingevoerde of onbekende waarde: toon zoals opgeslagen
    }
}

/// Voertuigbeheer: overzicht met geschatte kilometerstand, toevoegen,
/// bewerken en verwijderen (ritten blijven bewaard).
struct VehiclesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    @State private var editingVehicle: Vehicle?
    @State private var showsAddSheet = false
    @State private var vehicleToDelete: Vehicle?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if vehicles.isEmpty {
                ContentUnavailableView(
                    "Geen voertuigen",
                    systemImage: "car.2",
                    description: Text("Voeg een voertuig toe om ritten per auto te kunnen filteren en rapporteren.")
                )
            } else {
                List {
                    ForEach(vehicles) { vehicle in
                        Button {
                            editingVehicle = vehicle
                        } label: {
                            VehicleRow(vehicle: vehicle)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Verwijder", systemImage: "trash", role: .destructive) {
                                vehicleToDelete = vehicle
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Voertuigen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsAddSheet = true
                } label: {
                    Label("Voertuig toevoegen", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showsAddSheet) {
            VehicleFormView(vehicle: nil)
        }
        .sheet(item: $editingVehicle) { vehicle in
            VehicleFormView(vehicle: vehicle)
        }
        .confirmationDialog(
            "Voertuig verwijderen?",
            isPresented: .constant(vehicleToDelete != nil),
            titleVisibility: .visible
        ) {
            Button(deleteButtonTitle, role: .destructive) {
                deleteVehicle()
            }
            Button("Annuleer", role: .cancel) { vehicleToDelete = nil }
        } message: {
            Text("De ritten van dit voertuig blijven bewaard, maar zijn er niet langer aan gekoppeld.")
        }
        .alert("Er ging iets mis", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var deleteButtonTitle: String {
        let template = String(localized: "Verwijder %@", comment: "Bevestigingsknop: voertuig verwijderen; %@ is de naam van het voertuig")
        return String(format: template, vehicleToDelete?.name ?? "")
    }

    private func deleteVehicle() {
        guard let vehicle = vehicleToDelete else { return }
        vehicleToDelete = nil
        do {
            // In een regio met bewaarplicht weigert de repository dit met
            // opgaaf van reden; die reden komt in de foutmelding terecht.
            let ruleSet = AppSettings.fetchOrCreate(in: context).ruleSet
            try VehicleRepository(context: context).delete(vehicle, ruleSet: ruleSet)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VehicleRow: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle

    var body: some View {
        HStack {
            Image(systemName: "car.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if !vehicle.licensePlate.isEmpty {
                        Text(vehicle.licensePlate)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.yellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text(vehicleTypeDisplayName(vehicle.vehicleType))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(VehicleRepository(context: context).estimatedOdometer(for: vehicle).formatted(.number.precision(.fractionLength(0)))) km")
                    .font(.subheadline.bold())
                Text(tripsCountText(vehicle.trips.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// Formulier voor nieuw of bestaand voertuig.
struct VehicleFormView: View {
    private static let typeOptions = ["Auto", "Bestelbus", "Motor", "Fiets", "Anders"]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let existingVehicle: Vehicle?

    @State private var name: String
    @State private var licensePlate: String
    @State private var vehicleType: String
    @State private var initialOdometer: Double?
    @State private var errorMessage: String?

    init(vehicle: Vehicle?) {
        existingVehicle = vehicle
        _name = State(initialValue: vehicle?.name ?? "")
        _licensePlate = State(initialValue: vehicle?.licensePlate ?? "")
        _vehicleType = State(initialValue: vehicle?.vehicleType ?? "Auto")
        _initialOdometer = State(initialValue: (vehicle?.initialOdometer ?? 0) > 0 ? vehicle?.initialOdometer : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Voertuig") {
                    TextField("Naam (bv. Bedrijfsauto)", text: $name)
                    TextField("Kenteken", text: $licensePlate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("Type", selection: $vehicleType) {
                        ForEach(Self.typeOptions, id: \.self) { type in
                            Text(vehicleTypeDisplayName(type)).tag(type)
                        }
                    }
                }
                Section {
                    LabeledContent("Beginstand") {
                        TextField("0", value: $initialOdometer, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Kilometerstand bij start registratie")
                        Text("km")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("De kilometerstand op het moment dat je met deze app begon te registreren.")
                }
            }
            // Ternary van twee letterlijke strings wordt door Swift als
            // `String` geïnfereerd, niet als `LocalizedStringKey` — daarom
            // hier expliciet via `String(localized:)`, net als bij de
            // vergelijkbare knoptekst in `OnboardingView`.
            .navigationTitle(existingVehicle == nil
                ? String(localized: "Voertuig toevoegen", comment: "Titel: nieuw voertuig toevoegen")
                : String(localized: "Voertuig bewerken", comment: "Titel: bestaand voertuig bewerken")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
            }
            .alert("Er ging iets mis", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        let vehicle = existingVehicle ?? Vehicle(name: name)
        vehicle.name = name.trimmingCharacters(in: .whitespaces)
        vehicle.licensePlate = licensePlate.trimmingCharacters(in: .whitespaces).uppercased()
        vehicle.vehicleType = vehicleType
        vehicle.initialOdometer = initialOdometer ?? 0

        do {
            if existingVehicle == nil {
                context.insert(vehicle)
            }
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        VehiclesView()
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
}
