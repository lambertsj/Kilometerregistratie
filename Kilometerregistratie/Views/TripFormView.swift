import SwiftUI
import SwiftData

/// Formulier voor het afronden van een zojuist gestopte rit én voor het
/// achteraf handmatig toevoegen van een rit (adressen of alleen kilometers).
struct TripFormView: View {
    enum Mode {
        /// Zojuist gestopte rit afronden: de rit staat al in de database.
        case finishRecorded
        /// Achteraf toevoegen: de rit wordt pas bij opslaan bewaard.
        case addManually
        /// Bestaande rit bewerken vanuit het detailscherm.
        case edit

        var title: String {
            switch self {
            case .finishRecorded: String(localized: "Rit afronden", comment: "Titel: zojuist gestopte rit afronden")
            case .addManually: String(localized: "Rit toevoegen", comment: "Titel: handmatig een rit toevoegen")
            case .edit: String(localized: "Rit bewerken", comment: "Titel: bestaande rit bewerken")
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query private var allSettings: [AppSettings]

    let mode: Mode
    private let existingTrip: Trip?

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var startAddress: String
    @State private var endAddress: String
    @State private var distanceKm: Double?
    @State private var category: TripCategory
    @State private var note: String
    @State private var clientLabel: String
    @State private var selectedVehicleID: UUID?
    @State private var startOdometer: Double?
    @State private var endOdometer: Double?
    @State private var destinationPlace: String
    @State private var destinationStreet: String
    @State private var purpose: String
    @State private var businessPartner: String
    @State private var detourNote: String

    @State private var isCalculatingDistance = false
    @State private var errorMessage: String?

    /// Laatst automatisch voorgestelde categorie; wijkt de gebruiker hier
    /// bewust van af, dan overschrijven we zijn keuze niet meer.
    @State private var lastSuggestedCategory: TripCategory?
    @State private var userOverrodeCategory = false

    private let routeService: any RouteDistanceProviding

    init(trip: Trip?, mode: Mode, routeService: any RouteDistanceProviding = MapKitRouteDistanceService()) {
        self.mode = mode
        self.existingTrip = trip
        self.routeService = routeService
        _startDate = State(initialValue: trip?.startDate ?? .now)
        _endDate = State(initialValue: trip?.endDate ?? .now)
        _startAddress = State(initialValue: trip?.startAddress ?? "")
        _endAddress = State(initialValue: trip?.endAddress ?? "")
        _distanceKm = State(initialValue: (trip?.distanceKm ?? 0) > 0 ? trip?.distanceKm : nil)
        _category = State(initialValue: trip?.category ?? .business)
        _note = State(initialValue: trip?.note ?? "")
        _clientLabel = State(initialValue: trip?.clientLabel ?? "")
        _selectedVehicleID = State(initialValue: trip?.vehicle?.id)
        _startOdometer = State(initialValue: trip?.startOdometer)
        _endOdometer = State(initialValue: trip?.endOdometer)
        _destinationPlace = State(initialValue: trip?.destinationPlace ?? "")
        _destinationStreet = State(initialValue: trip?.destinationStreet ?? "")
        _purpose = State(initialValue: trip?.purpose ?? "")
        _businessPartner = State(initialValue: trip?.businessPartner ?? "")
        _detourNote = State(initialValue: trip?.detourNote ?? "")
    }

    private var settings: AppSettings {
        allSettings.first ?? AppSettings.fetchOrCreate(in: context)
    }

    private var ruleSet: any RegionRuleSet { settings.ruleSet }

    /// De velden die de ingestelde regio in enige categorie kan vragen. Voor
    /// Nederland is dat alleen de afstand, dus daar verandert het formulier
    /// niet: er komen geen invoervelden en geen verplichtingen bij.
    private var relevantFields: Set<TripField> { ruleSet.allRelevantFields }

    private func isRequired(_ field: TripField) -> Bool {
        ruleSet.isRequired(field, for: category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tijd") {
                    DatePicker("Vertrek", selection: $startDate)
                    DatePicker("Aankomst", selection: $endDate, in: startDate...)
                }

                Section("Route") {
                    TextField("Beginadres of naam uit contacten", text: $startAddress)
                        .textContentType(.fullStreetAddress)
                    TextField("Eindadres of naam uit contacten", text: $endAddress)
                        .textContentType(.fullStreetAddress)
                    LabeledContent("Afstand") {
                        // Eén HStack: LabeledContent stapelt twee losse views
                        // anders onder elkaar, met "km" los van het getal.
                        HStack(spacing: 4) {
                            TextField("0", value: $distanceKm, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel("Afstand in kilometers")
                            Text("km")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if canCalculateDistance {
                        Button {
                            calculateDistance()
                        } label: {
                            if isCalculatingDistance {
                                ProgressView()
                            } else {
                                Label("Bereken afstand via route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            }
                        }
                        .disabled(isCalculatingDistance)
                    }
                }

                Section("Categorie") {
                    Picker("Categorie", selection: $category) {
                        ForEach(TripCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Ritcategorie")
                }

                if !vehicles.isEmpty {
                    Section("Voertuig") {
                        Picker("Voertuig", selection: $selectedVehicleID) {
                            Text("Geen").tag(UUID?.none)
                            ForEach(vehicles) { vehicle in
                                Text(vehicle.name).tag(UUID?.some(vehicle.id))
                            }
                        }
                    }
                }

                if relevantFields.contains(.startOdometer) || relevantFields.contains(.endOdometer) {
                    odometerSection
                }

                if !germanFields.isEmpty {
                    fahrtenbuchSection
                }

                Section("Details") {
                    TextField("Doel / notitie", text: $note, axis: .vertical)
                    TextField("Klant of project (optioneel)", text: $clientLabel)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") { save() }
                        .disabled(!isValid)
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
            .onAppear { applySuggestionIfNeeded() }
            .onChange(of: startAddress) { applySuggestionIfNeeded() }
            .onChange(of: endAddress) { applySuggestionIfNeeded() }
            .onChange(of: category) { _, newValue in
                if newValue != lastSuggestedCategory {
                    userOverrodeCategory = true
                }
            }
        }
        .interactiveDismissDisabled(mode == .finishRecorded)
    }

    // MARK: - Categorie-suggestie

    /// Stelt de categorie voor op basis van geleerde adrescombinaties en de
    /// kantooruren-regel, zolang de gebruiker zelf nog niets gekozen heeft.
    /// Bij bewerken van een bestaande rit blijft de opgeslagen keuze staan.
    private func applySuggestionIfNeeded() {
        guard mode != .edit, !userOverrodeCategory else { return }

        var learned: TripCategory?
        if let key = TripClassifier.routeKey(startAddress: startAddress, endAddress: endAddress) {
            learned = ClassificationRuleRepository(context: context).learnedCategory(forRouteKey: key)
        }
        let settings = AppSettings.fetchOrCreate(in: context)
        let suggestion = TripClassifier.suggestCategory(
            startDate: startDate,
            learned: learned,
            schedule: settings.workSchedule
        )
        lastSuggestedCategory = suggestion
        category = suggestion
    }

    // MARK: - Regioafhankelijke secties

    /// De Fahrtenbuch-velden die deze regio kent, in vaste volgorde.
    private var germanFields: [TripField] {
        [.destinationPlace, .destinationStreet, .purpose, .businessPartner, .detourNote]
            .filter { relevantFields.contains($0) }
    }

    private var odometerSection: some View {
        Section {
            LabeledContent("Kilometerstand begin") {
                TextField("0", value: $startOdometer, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Kilometerstand bij vertrek")
            }
            LabeledContent("Kilometerstand eind") {
                TextField("0", value: $endOdometer, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Kilometerstand bij aankomst")
            }
        } header: {
            Text("Kilometerstand")
        } footer: {
            Text("De kilometerstanden van opeenvolgende ritten moeten op elkaar aansluiten.")
        }
    }

    @ViewBuilder
    private var fahrtenbuchSection: some View {
        Section {
            ForEach(germanFields, id: \.self) { field in
                TextField(placeholder(for: field), text: binding(for: field), axis: field == .detourNote ? .vertical : .horizontal)
            }
        } header: {
            Text("Ritgegevens")
        } footer: {
            Text(requiredFieldsFooter)
        }
    }

    private var requiredFieldsFooter: String {
        let required = germanFields.filter { isRequired($0) }
        guard !required.isEmpty else {
            return String(localized: "Voor deze categorie zijn deze gegevens niet verplicht.", comment: "Voettekst rittengegevens: niets verplicht voor de gekozen categorie")
        }
        // De veldnamen komen uit `TripField.displayName` (title case) en niet
        // uit een losse, verkleinde variant: Duitse zelfstandige naamwoorden
        // horen altijd met een hoofdletter, ook middenin een zin — een eigen
        // lowercase-vertaling zou die regel per ongeluk kunnen breken.
        let template = String(localized: "Verplicht voor deze categorie: %@.", comment: "Voettekst rittengegevens: opsomming van verplichte velden; %@ is de kommagescheiden lijst")
        return String(format: template, required.map(\.displayName).joined(separator: ", "))
    }

    private func placeholder(for field: TripField) -> String {
        switch field {
        case .destinationPlace: String(localized: "Bestemming (plaats)", comment: "Placeholder: bestemming plaats")
        case .destinationStreet: String(localized: "Bestemming (straat)", comment: "Placeholder: bestemming straat")
        case .purpose: String(localized: "Reisdoel", comment: "Placeholder: reisdoel")
        case .businessPartner: String(localized: "Bezochte zakenrelatie", comment: "Placeholder: bezochte zakenrelatie")
        case .detourNote: String(localized: "Omweg (indien van toepassing)", comment: "Placeholder: omweg")
        default: field.rawValue
        }
    }

    private func binding(for field: TripField) -> Binding<String> {
        switch field {
        case .destinationPlace: $destinationPlace
        case .destinationStreet: $destinationStreet
        case .purpose: $purpose
        case .businessPartner: $businessPartner
        case .detourNote: $detourNote
        default: .constant("")
        }
    }

    // MARK: - Validatie & acties

    /// Geldigheid volgens de regelset van de ingestelde regio. Voor Nederland
    /// levert dit exact de oude regel op: er is een afstand ingevuld.
    private var isValid: Bool {
        ruleSet.requiredFields(for: category).allSatisfy { field in
            switch field {
            case .date: true
            case .distance: (distanceKm ?? 0) > 0
            case .startOdometer: startOdometer != nil
            case .endOdometer: endOdometer != nil
            case .startAddress: !startAddress.trimmingCharacters(in: .whitespaces).isEmpty
            case .endAddress: !endAddress.trimmingCharacters(in: .whitespaces).isEmpty
            case .destinationPlace: !destinationPlace.trimmingCharacters(in: .whitespaces).isEmpty
            case .destinationStreet: !destinationStreet.trimmingCharacters(in: .whitespaces).isEmpty
            case .purpose: !purpose.trimmingCharacters(in: .whitespaces).isEmpty
            case .businessPartner: !businessPartner.trimmingCharacters(in: .whitespaces).isEmpty
            case .detourNote: !detourNote.trimmingCharacters(in: .whitespaces).isEmpty
            case .annotation: !note.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }

    private var canCalculateDistance: Bool {
        !startAddress.trimmingCharacters(in: .whitespaces).isEmpty
            && !endAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func calculateDistance() {
        isCalculatingDistance = true
        let service = routeService
        let from = startAddress
        let to = endAddress
        Task {
            defer { isCalculatingDistance = false }
            do {
                distanceKm = try await service.distanceKm(fromAddress: from, toAddress: to)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        // Alle schrijfacties lopen via TripWriteService: die legt in een regio
        // met bewaarplicht vast wát er gewijzigd is.
        let writer = TripWriteService(context: context)
        let apply: (Trip) -> Void = { trip in
            trip.startDate = startDate
            trip.endDate = endDate
            trip.startAddress = startAddress.trimmingCharacters(in: .whitespaces)
            trip.endAddress = endAddress.trimmingCharacters(in: .whitespaces)
            trip.distanceKm = distanceKm ?? 0
            trip.category = category
            trip.note = note
            trip.clientLabel = clientLabel
            trip.vehicle = vehicles.first { $0.id == selectedVehicleID }
            trip.destinationPlace = destinationPlace.trimmingCharacters(in: .whitespaces)
            trip.destinationStreet = destinationStreet.trimmingCharacters(in: .whitespaces)
            trip.purpose = purpose.trimmingCharacters(in: .whitespaces)
            trip.businessPartner = businessPartner.trimmingCharacters(in: .whitespaces)
            trip.detourNote = detourNote.trimmingCharacters(in: .whitespaces)
            trip.startOdometer = startOdometer
            trip.endOdometer = endOdometer
        }

        do {
            if let existingTrip {
                try writer.update(existingTrip, apply)
            } else {
                let trip = Trip(startDate: startDate)
                apply(trip)
                try writer.create(trip)
            }
            learnClassification()
            Haptics.tripSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Onthoudt de gekozen categorie voor deze adrescombinatie zodat de app
    /// hem de volgende keer kan voorstellen.
    private func learnClassification() {
        guard let key = TripClassifier.routeKey(startAddress: startAddress, endAddress: endAddress) else { return }
        try? ClassificationRuleRepository(context: context).learn(routeKey: key, category: category)
    }
}

#Preview {
    TripFormView(trip: nil, mode: .addManually)
        .modelContainer(for: AppSchema.models, inMemory: true)
}
