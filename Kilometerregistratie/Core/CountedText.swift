import Foundation

/// "1 rit" / "N ritten" met correcte enkelvoud/meervoud.
///
/// Nederlands, Duits en Engels kennen hier alleen een tweedeling (1 versus
/// overig); dat wordt hier met de hand gekozen in plaats van via een
/// ICU-plural-regel in de String Catalog, zodat er geen afhankelijkheid is
/// van Apple's automatische-grammatica-opmaak (die zich niet zonder
/// simulator laat verifiëren).
func tripsCountText(_ count: Int) -> String {
    count == 1
        ? String(localized: "1 rit", comment: "Aantal ritten: precies 1")
        : String(format: String(localized: "%lld ritten", comment: "Aantal ritten: meerdere; %lld is het aantal"), count)
}

/// "1 voertuig" / "N voertuigen".
func vehiclesCountText(_ count: Int) -> String {
    count == 1
        ? String(localized: "1 voertuig", comment: "Aantal voertuigen: precies 1")
        : String(format: String(localized: "%lld voertuigen", comment: "Aantal voertuigen: meerdere; %lld is het aantal"), count)
}
