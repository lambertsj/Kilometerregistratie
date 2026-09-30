import SwiftUI

extension TaxRegion {
    /// Schermnaam van de regio. Dit is UI-tekst en volgt dus de taal van de
    /// gebruiker, niet de regio zelf.
    var displayName: String {
        switch self {
        case .netherlands: String(localized: "Nederland", comment: "Regiokeuze: Nederland")
        case .germany: String(localized: "Duitsland", comment: "Regiokeuze: Duitsland")
        }
    }

    /// Korte uitleg van wat de keuze betekent.
    var settingsDescription: String {
        switch self {
        case .netherlands:
            String(localized: "Rittenregistratie volgens de Nederlandse regels, met de 500 km-privégrens en een rapport voor de Belastingdienst.", comment: "Toelichting bij regiokeuze Nederland")
        case .germany:
            String(localized: "Fahrtenbuch volgens de Duitse regels: sluitende kilometerstanden, vastgelegde wijzigingen en een rapport voor het Finanzamt.", comment: "Toelichting bij regiokeuze Duitsland")
        }
    }

    /// Korte, juridisch voorzichtige toelichting: de app is een hulpmiddel
    /// voor de rittenregistratie, geen belastingadvies en geen garantie op
    /// acceptatie. Verschijnt op het instellingen- en rapportscherm, in de
    /// taal van de regio zelf (net als een exportdocument) omdat het over de
    /// verantwoordelijkheid van de gebruiker tegenover díe belastingdienst
    /// gaat.
    var complianceNotice: String {
        switch self {
        case .netherlands:
            String(localized: "Deze app is een hulpmiddel om je rittenregistratie bij te houden. Je bent zelf verantwoordelijk voor de volledigheid en juistheid ervan; dit is geen belastingadvies.", comment: "Juridische toelichting (Hinweis) voor de Nederlandse regio")
        case .germany:
            String(localized: "Diese App ist ein Hilfsmittel zur Führung Ihres Fahrtenbuchs. Sie sind selbst für dessen Vollständigkeit und Richtigkeit verantwortlich; dies stellt keine Steuerberatung dar.", comment: "Juridische toelichting (Hinweis) voor de Duitse regio")
        }
    }

    var iconName: String {
        switch self {
        case .netherlands: "flag"
        case .germany: "flag.2.crossed"
        }
    }
}
