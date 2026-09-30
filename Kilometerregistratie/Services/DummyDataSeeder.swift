import Foundation
import SwiftData

/// Vult de lokale database met realistische voorbeeldritten, alleen bedoeld
/// voor demo's/schermopnamen. Uitsluitend bereikbaar via een DEBUG-only
/// knop in Instellingen; komt nooit in een release-build terecht.
///
/// Deze seeder schrijft bewust rechtstreeks naar de context en niet via
/// `TripWriteService`: het gaat om demodata, niet om een dossier, en
/// `removeAll` moet die data ook echt kunnen weggooien in plaats van er
/// tombstones en revisies van te maken. Dit is de enige plek in de app die
/// buiten de schrijfservice om ritten aanmaakt, en hij bestaat alleen in
/// DEBUG-builds.
enum DummyDataSeeder {
    private struct Place {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private static let home = Place(name: "Thuis, Rijnstraat 12, Utrecht", latitude: 52.0907, longitude: 5.1214)

    private static let destinations: [(place: Place, category: TripCategory, client: String, note: String)] = [
        (Place(name: "Kantoor, Papendorpseweg 100, Utrecht", latitude: 52.0836, longitude: 5.1058), .commute, "", "Woon-werkverkeer"),
        (Place(name: "Klant De Vries B.V., Herengracht 45, Amsterdam", latitude: 52.3702, longitude: 4.8952), .business, "De Vries B.V.", "Projectoverleg"),
        (Place(name: "Klant Van Dijk Groep, Coolsingel 80, Rotterdam", latitude: 51.9225, longitude: 4.4792), .business, "Van Dijk Groep", "Offerte bespreken"),
        (Place(name: "Vestiging Den Haag, Spui 70, Den Haag", latitude: 52.0799, longitude: 4.3113), .business, "Eigen vestiging", "Teamoverleg"),
        (Place(name: "Bouwplaats Nieuwbouw, Kanaalweg 5, Amersfoort", latitude: 52.1561, longitude: 5.3878), .business, "Bouwbedrijf Hendriks", "Werkbezoek locatie"),
        (Place(name: "Supermarkt, Vredenburg 2, Utrecht", latitude: 52.0919, longitude: 5.1198), .personal, "", "Boodschappen"),
        (Place(name: "Sportschool, Van Sijpesteijnkade 26, Utrecht", latitude: 52.0895, longitude: 5.1152), .personal, "", "Sporten"),
        (Place(name: "Ouders, Dorpsstraat 8, Amersfoort", latitude: 52.1526, longitude: 5.3875), .personal, "", "Familiebezoek"),
        (Place(name: "Klant Bakker Installaties, Marktplein 3, Zwolle", latitude: 52.5168, longitude: 6.0830), .business, "Bakker Installaties", "Oplevering"),
        (Place(name: "Schiphol Airport, Evert van de Beekstraat, Schiphol", latitude: 52.3105, longitude: 4.7683), .business, "Klant Jansen Consultancy", "Klant ophalen"),
    ]

    /// Genereert `tripCount` ritten verspreid over de laatste `dayRange` dagen
    /// voor een nieuw aangemaakt voorbeeldvoertuig.
    @discardableResult
    static func seed(context: ModelContext, tripCount: Int = 55, dayRange: Int = 60) -> Vehicle {
        let vehicle = Vehicle(
            name: "Volkswagen Passat",
            licensePlate: "12-ABC-3",
            vehicleType: "Auto",
            initialOdometer: 34_180,
            createdAt: Calendar.current.date(byAdding: .day, value: -dayRange, to: .now) ?? .now
        )
        context.insert(vehicle)

        var odometer = vehicle.initialOdometer
        let calendar = Calendar.current
        var rng = SystemRandomNumberGenerator()

        var day = -dayRange
        var generated = 0
        while generated < tripCount && day <= 0 {
            defer { day += 1 }

            let date = calendar.date(byAdding: .day, value: day, to: .now) ?? .now
            let weekday = calendar.component(.weekday, from: date)
            let isWeekend = weekday == 1 || weekday == 7

            // Op weekdagen meestal 1-2 ritten (woon-werk + evt. zakelijk),
            // in het weekend af en toe een privérit.
            let tripsToday = isWeekend ? Int.random(in: 0...1, using: &rng) : Int.random(in: 1...2, using: &rng)

            for tripIndex in 0..<tripsToday where generated < tripCount {
                let destination: (place: Place, category: TripCategory, client: String, note: String)
                if isWeekend {
                    destination = destinations.filter { $0.category == .personal }.randomElement(using: &rng)!
                } else if tripIndex == 0 {
                    destination = destinations[0] // woon-werk
                } else {
                    destination = destinations.filter { $0.category == .business }.randomElement(using: &rng)!
                }

                let hour = isWeekend ? Int.random(in: 10...18, using: &rng) : (tripIndex == 0 ? 8 : Int.random(in: 12...17, using: &rng))
                let minute = Int.random(in: 0...59, using: &rng)
                let startDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date

                let distanceKm = (GeoDistance.meters(
                    fromLatitude: home.latitude, longitude: home.longitude,
                    toLatitude: destination.place.latitude, longitude: destination.place.longitude
                ) / 1000 * Double.random(in: 1.05...1.25, using: &rng)).rounded(toPlaces: 1)

                let durationMinutes = max(8, Int(distanceKm * Double.random(in: 1.1...1.6, using: &rng)))
                let endDate = calendar.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate

                let isReturnTrip = tripIndex.isMultiple(of: 2) == false
                let (startPlace, endPlace) = isReturnTrip ? (destination.place, home) : (home, destination.place)

                let isAutomatic = Bool.random(using: &rng)
                let startOdo = odometer
                odometer += distanceKm
                let endOdo = odometer

                let trip = Trip(
                    startDate: startDate,
                    endDate: endDate,
                    startAddress: startPlace.name,
                    endAddress: endPlace.name,
                    startLatitude: startPlace.latitude,
                    startLongitude: startPlace.longitude,
                    endLatitude: endPlace.latitude,
                    endLongitude: endPlace.longitude,
                    distanceKm: distanceKm,
                    startOdometer: startOdo.rounded(toPlaces: 1),
                    endOdometer: endOdo.rounded(toPlaces: 1),
                    category: destination.category,
                    note: destination.category == .personal ? destination.note : (isReturnTrip ? "Terugreis: \(destination.note)" : destination.note),
                    clientLabel: destination.client,
                    isAutomaticallyRecorded: isAutomatic,
                    routeData: try? RoutePolyline.encode(routePoints(
                        from: (startPlace.latitude, startPlace.longitude),
                        to: (endPlace.latitude, endPlace.longitude),
                        durationMinutes: durationMinutes
                    )),
                    vehicle: vehicle
                )
                context.insert(trip)
                generated += 1
            }
        }

        try? context.save()
        return vehicle
    }

    /// Verwijdert alle ritten en voertuigen (laat instellingen ongemoeid).
    static func removeAll(context: ModelContext) {
        if let trips = try? context.fetch(FetchDescriptor<Trip>()) {
            trips.forEach { context.delete($0) }
        }
        if let vehicles = try? context.fetch(FetchDescriptor<Vehicle>()) {
            vehicles.forEach { context.delete($0) }
        }
        try? context.save()
    }

    /// Interpoleert een rechte lijn tussen twee punten als eenvoudige
    /// vervanging voor een echte GPS-track (alleen voor demo-doeleinden).
    private static func routePoints(
        from start: (lat: Double, lon: Double),
        to end: (lat: Double, lon: Double),
        durationMinutes: Int
    ) -> [RoutePoint] {
        let steps = max(4, durationMinutes / 2)
        return (0...steps).map { step in
            let fraction = Double(step) / Double(steps)
            return RoutePoint(
                latitude: start.lat + (end.lat - start.lat) * fraction,
                longitude: start.lon + (end.lon - start.lon) * fraction,
                offset: Double(step) * Double(durationMinutes * 60) / Double(steps)
            )
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
