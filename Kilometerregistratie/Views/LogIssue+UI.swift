import SwiftUI

extension TripField {
    /// Schermnaam van het veld, voor gebruik in een melding. Losse naamgeving
    /// van `GermanyRuleSet.exportLabel`: dat zijn de vaste, regiogebonden
    /// exporttermen voor in een document; dit is UI-taal en volgt de
    /// instelling van de gebruiker.
    var displayName: String {
        switch self {
        case .date: String(localized: "Datum", comment: "Veldnaam in een validatiemelding")
        case .distance: String(localized: "Afstand", comment: "Veldnaam in een validatiemelding")
        case .startOdometer: String(localized: "Kilometerstand begin", comment: "Veldnaam in een validatiemelding")
        case .endOdometer: String(localized: "Kilometerstand eind", comment: "Veldnaam in een validatiemelding")
        case .startAddress: String(localized: "Beginadres", comment: "Veldnaam in een validatiemelding")
        case .endAddress: String(localized: "Eindadres", comment: "Veldnaam in een validatiemelding")
        case .destinationPlace: String(localized: "Bestemming (plaats)", comment: "Veldnaam in een validatiemelding")
        case .destinationStreet: String(localized: "Bestemming (straat)", comment: "Veldnaam in een validatiemelding")
        case .purpose: String(localized: "Reisdoel", comment: "Veldnaam in een validatiemelding")
        case .businessPartner: String(localized: "Zakenrelatie", comment: "Veldnaam in een validatiemelding")
        case .detourNote: String(localized: "Omweg", comment: "Veldnaam in een validatiemelding")
        case .annotation: String(localized: "Aantekening", comment: "Veldnaam in een validatiemelding")
        }
    }
}

extension IssueSeverity {
    var displayName: String {
        switch self {
        case .blocking: String(localized: "Ontbreekt of sluit niet aan", comment: "Groepskop: blokkerende validatiemeldingen")
        case .warning: String(localized: "Opvallend", comment: "Groepskop: waarschuwende validatiemeldingen")
        }
    }

    var color: Color {
        switch self {
        case .blocking: Theme.danger
        case .warning: Theme.warning
        }
    }

    var iconName: String {
        switch self {
        case .blocking: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
}

extension LogIssue {
    /// Feitelijke, neutrale beschrijving van wat er ontbreekt of niet
    /// aansluit — geen voorspelling van wat een belastingdienst ermee zou
    /// doen, en geen garantie dat het rapport daarmee compleet is.
    ///
    /// Gebouwd via `String(format:)` met een eigen, met de hand gekozen
    /// sleuteltekst in plaats van `Text("\(x) km")`-interpolatie: zo ligt de
    /// sleutel die in de String Catalog moet staan altijd vast, en hoeft die
    /// niet te worden geraden bij het vertalen.
    var summary: String {
        switch kind {
        case .odometerGap(let km):
            let template = String(localized: "Tussen deze twee ritten zit een gat van %@ km dat niet aan een rit is toegekend.", comment: "Validatiemelding: onverklaard gat in de kilometerstand")
            return String(format: template, km.formatted(.number.precision(.fractionLength(0...1))))
        case .odometerOverlap(let km):
            let template = String(localized: "Deze rit begint %@ km vóór het einde van de vorige rit.", comment: "Validatiemelding: overlappende kilometerstand")
            return String(format: template, km.formatted(.number.precision(.fractionLength(0...1))))
        case .missingOdometer(let field), .missingRequiredField(let field):
            let template = String(localized: "%@ ontbreekt bij deze rit.", comment: "Validatiemelding: verplicht veld ontbreekt; %@ is de veldnaam")
            return String(format: template, field.displayName)
        case .distanceMismatch(let odometerKm, let recordedKm):
            let template = String(localized: "De kilometerstanden geven %1$@ km aan, de rit staat genoteerd als %2$@ km.", comment: "Validatiemelding: afstand komt niet overeen met de kilometerstanden")
            return String(
                format: template,
                odometerKm.formatted(.number.precision(.fractionLength(0...1))),
                recordedKm.formatted(.number.precision(.fractionLength(0...1)))
            )
        case .missingVehicle:
            return String(localized: "Deze rit heeft geen voertuig, waardoor de kilometerstand niet in een reeks past.", comment: "Validatiemelding: rit zonder voertuig")
        case .unfinishedTrip:
            return String(localized: "Deze rit is nog niet afgesloten.", comment: "Validatiemelding: rit zonder eindtijd")
        }
    }
}

extension LogHeadlineState {
    var title: String {
        switch self {
        case .ok:
            String(localized: "Registratie is compleet", comment: "Koptekst validatiescherm: geen meldingen")
        case .warnings:
            String(localized: "Registratie is compleet, met opmerkingen", comment: "Koptekst validatiescherm: alleen waarschuwingen")
        case .blocking:
            String(localized: "Registratie is niet compleet", comment: "Koptekst validatiescherm: blokkerende meldingen")
        }
    }

    var detail: String {
        switch self {
        case .ok:
            return String(localized: "Er zijn geen ontbrekende gegevens of gaten in de kilometerstanden gevonden.", comment: "Toelichting validatiescherm: geen meldingen")
        case .warnings(let count):
            return Self.countedText(
                count,
                one: String(localized: "1 opmerking gevonden, niets dat de registratie blokkeert.", comment: "Toelichting validatiescherm: precies 1 waarschuwing"),
                other: String(localized: "%lld opmerkingen gevonden, niets dat de registratie blokkeert.", comment: "Toelichting validatiescherm: meerdere waarschuwingen, %lld is het aantal")
            )
        case .blocking(let count, let warningCount):
            let blockingText = Self.countedText(
                count,
                one: String(localized: "1 melding over ontbrekende of niet-aansluitende gegevens.", comment: "Toelichting validatiescherm: precies 1 blokkerende melding"),
                other: String(localized: "%lld meldingen over ontbrekende of niet-aansluitende gegevens.", comment: "Toelichting validatiescherm: meerdere blokkerende meldingen, %lld is het aantal")
            )
            guard warningCount > 0 else { return blockingText }
            let extra = Self.countedText(
                warningCount,
                one: String(localized: " Daarnaast 1 opmerking.", comment: "Toevoeging: precies 1 extra waarschuwing naast de blokkerende meldingen"),
                other: String(localized: " Daarnaast %lld opmerkingen.", comment: "Toevoeging: meerdere extra waarschuwingen naast de blokkerende meldingen, %lld is het aantal")
            )
            return blockingText + extra
        }
    }

    /// Kiest de enkelvouds- of meervoudstekst op basis van het aantal. Dutch
    /// en German kennen hier allebei alleen een tweedeling (1 vs. overig),
    /// dus een handmatige keuze is taalkundig genoeg — een ICU-plural-regel
    /// via de catalog is voor deze twee talen niet nodig.
    private static func countedText(_ count: Int, one: String, other: String) -> String {
        count == 1 ? one : String(format: other, count)
    }

    var iconName: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warnings: "exclamationmark.triangle.fill"
        case .blocking: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .ok: Theme.ok
        case .warnings: Theme.warning
        case .blocking: Theme.danger
        }
    }
}
