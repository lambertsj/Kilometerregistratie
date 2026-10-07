import SwiftUI
import SwiftData
import UIKit

/// Instellingen: registratiemodus, kilometervergoeding en de
/// kantooruren-regel voor automatische classificatie.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(LocationTrackingService.self) private var locationService
    @Query private var allSettings: [AppSettings]

    /// Weekdagen maandag-eerst, met Calendar.weekday-waarde en de
    /// locale-correcte afkorting uit het systeem. Bewust geen eigen
    /// vertaling: `shortStandaloneWeekdaySymbols` levert altijd de juiste
    /// afkorting voor de taal van de gebruiker, zonder vertaalrisico.
    private static var weekdayOptions: [(value: Int, label: String)] {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols // index 0 = zondag
        return [2, 3, 4, 5, 6, 7, 1].map { value in (value, symbols[value - 1]) }
    }

    private var settings: AppSettings {
        allSettings.first ?? AppSettings.fetchOrCreate(in: context)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Fiscale regio", selection: regionBinding) {
                        ForEach(TaxRegion.allCases) { region in
                            Text(region.displayName).tag(region)
                        }
                    }
                } header: {
                    Text("Regio")
                } footer: {
                    Text(settings.taxRegion.settingsDescription)
                }

                Section {
                    Label(settings.taxRegion.complianceNotice, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Voertuigen") {
                    NavigationLink {
                        VehiclesView()
                    } label: {
                        Label("Voertuigen beheren", systemImage: "car.2")
                    }
                }

                Section {
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("Versleutelde back-up", systemImage: "lock.icloud")
                    }
                } header: {
                    Text("Back-up")
                } footer: {
                    Text("Alle gegevens staan alleen op dit toestel. Maak zelf een versleutelde back-up en bewaar die bijvoorbeeld in je eigen iCloud Drive.")
                }

                Section {
                    Picker("Registratie", selection: trackingModeBinding) {
                        ForEach(TrackingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    if settings.trackingMode != .manual {
                        Stepper(
                            String(
                                format: String(localized: "Stop na %lld min stilstand", comment: "Instelling: aantal minuten stilstand voor automatisch stoppen; %lld is het aantal"),
                                settings.autoStopThresholdMinutes
                            ),
                            value: intBinding(\.autoStopThresholdMinutes),
                            in: 1...15
                        )
                        if locationService.authorizationStatus != .authorizedAlways {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(locationPermissionHint, systemImage: "location.slash")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.warning)
                                if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
                                    Button("Open Instellingen") { openSettings() }
                                        .font(.footnote)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Ritregistratie")
                } footer: {
                    Text("Automatisch: ritten starten en stoppen vanzelf op basis van rijsnelheid. Hybride: automatische detectie plus handmatig starten/stoppen. Handmatig starten kan altijd.")
                }

                Section {
                    Picker("Nauwkeurigheid", selection: locationAccuracyBinding) {
                        ForEach(LocationAccuracyPreference.allCases) { preference in
                            Text(preference.displayName).tag(preference)
                        }
                    }
                } header: {
                    Text("Nauwkeurigheid vs. batterij")
                } footer: {
                    Text(settings.locationAccuracyPreference.detailText)
                }

                Section {
                    LabeledContent("Tarief per km") {
                        TextField(
                            "0,23",
                            value: doubleBinding(\.reimbursementRatePerKm),
                            format: .currency(code: "EUR")
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Kilometervergoeding in euro per kilometer")
                    }
                } header: {
                    Text("Kilometervergoeding")
                } footer: {
                    Text(reimbursementFooter)
                }

                Section {
                    Toggle("Kantooruren-regel", isOn: boolBinding(\.workHoursEnabled))
                    if settings.workHoursEnabled {
                        DatePicker("Begin werkdag", selection: minuteBinding(\.workDayStartMinute), displayedComponents: .hourAndMinute)
                        DatePicker("Einde werkdag", selection: minuteBinding(\.workDayEndMinute), displayedComponents: .hourAndMinute)
                        weekdayPicker
                    }
                } header: {
                    Text("Classificatie")
                } footer: {
                    Text("Ritten die binnen je werktijden starten worden als zakelijk voorgesteld, daarbuiten als privé. Eerder gekozen categorieën per route gaan altijd voor. Je kunt elke rit handmatig aanpassen.")
                }

#if DEBUG
                Section {
                    Button("Vul met voorbeelddata") {
                        DummyDataSeeder.seed(context: context)
                    }
                    Button("Wis alle ritten en voertuigen", role: .destructive) {
                        DummyDataSeeder.removeAll(context: context)
                    }
                } header: {
                    Text("Ontwikkelaar")
                } footer: {
                    Text("Alleen zichtbaar in debug-builds, voor demo's en schermopnamen.")
                }
#endif
            }
                .themedList()
            .screenTitle("Instellingen")
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 8) {
            ForEach(Self.weekdayOptions, id: \.value) { option in
                let isOn = settings.workWeekdays.contains(option.value)
                Button(option.label) {
                    var days = settings.workWeekdays
                    if isOn { days.remove(option.value) } else { days.insert(option.value) }
                    settings.workWeekdays = days
                    trySave()
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isOn ? Theme.accent : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(isOn ? Theme.onAccent : Color.primary)
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: String(localized: "Werkdag %@", comment: "Toegankelijkheidslabel bij een weekdagknop; %@ is de afkorting van de dag"), option.label))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bindings naar het settings-record

    private var trackingModeBinding: Binding<TrackingMode> {
        Binding(
            get: { settings.trackingMode },
            set: { mode in
                settings.trackingMode = mode
                trySave()
                if mode != .manual {
                    locationService.requestAlwaysAuthorization()
                }
                locationService.applySettings(settings)
            }
        )
    }

    private var locationAccuracyBinding: Binding<LocationAccuracyPreference> {
        Binding(
            get: { settings.locationAccuracyPreference },
            set: { preference in
                settings.locationAccuracyPreference = preference
                trySave()
                locationService.applySettings(settings)
            }
        )
    }

    private func intBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Int> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                settings[keyPath: keyPath] = $0
                trySave()
                locationService.applySettings(settings)
            }
        )
    }

    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0; trySave() }
        )
    }

    private func doubleBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0; trySave() }
        )
    }

    /// Vertaalt minuten-sinds-middernacht naar een Date voor de DatePicker.
    private func minuteBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = settings[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                trySave()
            }
        )
    }

    private func trySave() {
        try? context.save()
    }

    private var regionBinding: Binding<TaxRegion> {
        Binding(
            get: { settings.taxRegion },
            set: { settings.taxRegion = $0; trySave() }
        )
    }

    /// Toelichting bij het vergoedingsveld, afgeleid uit de tarieventabel in
    /// `RegionRates.swift` in plaats van een vast bedrag in de tekst. Zo kan
    /// een nieuw belastingjaar een datawijziging blijven.
    private var reimbursementFooter: String {
        let year = Calendar.current.component(.year, from: .now)
        let rates = settings.ruleSet.rates(forTaxYear: year)
        let amount = rates.businessRatePerKm.formatted(.currency(code: rates.currencyCode))
        let template = String(localized: "De onbelaste vergoeding is %1$@ per kilometer (%2$@).", comment: "Toelichting bij het vergoedingstarief; %1$@ is het bedrag, %2$@ het jaartal")
        return String(format: template, amount, String(rates.taxYear))
    }

    /// Onderscheidt "nog niet gevraagd" (systeemmelding verschijnt vanzelf)
    /// van "expliciet geweigerd" (systeemmelding komt nooit meer terug, de
    /// gebruiker moet zelf naar Instellingen).
    private var locationPermissionHint: String {
        switch locationService.authorizationStatus {
        case .denied, .restricted:
            String(localized: "Automatische detectie heeft locatietoestemming \u{201C}Altijd\u{201D} nodig, maar toegang staat nu uit.", comment: "Melding: locatietoestemming geweigerd")
        default:
            String(localized: "Automatische detectie heeft locatietoestemming \u{201C}Altijd\u{201D} nodig. Als de melding niet verschijnt, zet dit dan aan via Instellingen > Kilometerregistratie > Locatie.", comment: "Melding: locatietoestemming nog niet gevraagd")
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: AppSchema.models, inMemory: true)
        .environment(LocationTrackingService())
}
