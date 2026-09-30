import Foundation
import SwiftData

extension TripValidationInput {
    /// Vertaalt een SwiftData-rit naar de lichtgewicht invoer van
    /// `LogValidator`. `.annotation` wordt gevuld uit `note`: dat is hetzelfde
    /// veld als waarmee `TripFormView` de korte woon-werkaantekening opslaat.
    init(_ trip: Trip) {
        self.init(
            id: trip.id,
            startDate: trip.startDate,
            endDate: trip.endDate,
            startOdometer: trip.startOdometer,
            endOdometer: trip.endOdometer,
            distanceKm: trip.distanceKm,
            category: trip.category,
            vehicleID: trip.vehicle?.id,
            fieldValues: [
                .startAddress: trip.startAddress,
                .endAddress: trip.endAddress,
                .destinationPlace: trip.destinationPlace,
                .destinationStreet: trip.destinationStreet,
                .purpose: trip.purpose,
                .businessPartner: trip.businessPartner,
                .detourNote: trip.detourNote,
                .annotation: trip.note,
            ]
        )
    }
}

/// Levert de validatie-issues voor een belastingjaar.
struct LogValidationRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Issues die een rit uit `taxYear` raken.
    ///
    /// De sluitendheidscontrole zelf kijkt naar *alle* ritten tot en met het
    /// eind van het jaar: anders zou een gat op de jaargrens (de laatste rit
    /// van december vorig jaar tegenover de eerste van januari) gemist
    /// worden. Pas ná het valideren wordt gefilterd tot issues die minstens
    /// één rit uit het gevraagde jaar raken, zodat een jaargrens-gat precies
    /// één keer verschijnt: in het jaar van de tweede rit.
    func issues(
        forTaxYear taxYear: Int,
        ruleSet: any RegionRuleSet,
        calendar: Calendar = .current
    ) throws -> [LogIssue] {
        guard let yearStart = calendar.date(from: DateComponents(year: taxYear, month: 1, day: 1)),
              let yearInterval = calendar.dateInterval(of: .year, for: yearStart) else {
            return []
        }

        let trips = try TripRepository(context: context).trips(to: yearInterval.end)
        let inputs = trips.map(TripValidationInput.init)
        let allIssues = LogValidator.validate(trips: inputs, ruleSet: ruleSet)

        let idsInYear = Set(
            trips
                .filter { $0.startDate >= yearInterval.start && $0.startDate < yearInterval.end }
                .map(\.id)
        )
        return allIssues.filter { issue in issue.tripIDs.contains { idsInYear.contains($0) } }
    }
}
