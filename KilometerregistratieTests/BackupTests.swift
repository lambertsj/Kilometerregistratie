import XCTest
import SwiftData
@testable import Kilometerregistratie

final class BackupTests: XCTestCase {
    private var sampleDocument: BackupDocument {
        BackupDocument(
            formatVersion: 1,
            exportDate: Date(timeIntervalSince1970: 1_800_000_000),
            trips: [
                BackupDocument.TripDTO(
                    id: UUID(), startDate: Date(timeIntervalSince1970: 1_799_000_000), endDate: Date(timeIntervalSince1970: 1_799_003_600),
                    startAddress: "A", endAddress: "B",
                    startLatitude: 52, startLongitude: 5, endLatitude: 52.1, endLongitude: 5.1,
                    distanceKm: 15, startOdometer: nil, endOdometer: nil,
                    category: "zakelijk", note: "Test", clientLabel: "",
                    isAutomaticallyRecorded: true, routeData: nil, vehicleID: nil
                ),
            ],
            vehicles: [
                BackupDocument.VehicleDTO(id: UUID(), name: "Auto", licensePlate: "X-1", vehicleType: "Auto", initialOdometer: 1000, createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            ],
            settings: BackupDocument.SettingsDTO(trackingMode: "hybride", reimbursementRatePerKm: 0.23, workHoursEnabled: true, workDayStartMinute: 540, workDayEndMinute: 1020, workWeekdays: [2, 3], autoStopThresholdMinutes: 3),
            classificationRules: [BackupDocument.RuleDTO(routeKey: "a|b", category: "woon-werk", timesUsed: 4)]
        )
    }

    func testEncryptDecryptRoundTrip() throws {
        let document = sampleDocument
        let encrypted = try BackupCodec.encrypt(document, password: "geheim-wachtwoord")

        XCTAssertEqual(encrypted.prefix(7), Data("KMREG1\n".utf8))
        XCTAssertFalse(String(decoding: encrypted, as: UTF8.self).contains("zakelijk"), "payload mag niet leesbaar zijn")

        let decrypted = try BackupCodec.decrypt(encrypted, password: "geheim-wachtwoord")
        XCTAssertEqual(decrypted, document)
    }

    func testWrongPasswordIsRejected() throws {
        let encrypted = try BackupCodec.encrypt(sampleDocument, password: "goed")
        XCTAssertThrowsError(try BackupCodec.decrypt(encrypted, password: "fout")) { error in
            XCTAssertEqual(error as? BackupCodecError, .wrongPassword)
        }
    }

    func testForeignFileIsRejected() {
        XCTAssertThrowsError(try BackupCodec.decrypt(Data("geen backup".utf8), password: "x")) { error in
            XCTAssertEqual(error as? BackupCodecError, .invalidFormat)
        }
    }

    func testRestoreReplacesExistingData() throws {
        let configuration = ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)
        let context = ModelContext(try ModelContainer(for: AppSchema.schema, configurations: [configuration]))
        context.insert(Trip(startDate: .now, distanceKm: 99))
        context.insert(AppSettings())
        try context.save()

        let service = BackupService(context: context)
        try service.restore(from: sampleDocument)

        let trips = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.distanceKm, 15)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Vehicle>()).first?.name, "Auto")
        let restoredSettings = try context.fetch(FetchDescriptor<AppSettings>())
        // Regressie: restore voegt de nieuwe instellingen vóór het
        // verwijderen van de oude toe (zie BackupService.restore), zodat een
        // fout halverwege geen dataverlies veroorzaakt. Dat mag geen tweede
        // AppSettings-rij achterlaten.
        XCTAssertEqual(restoredSettings.count, 1)
        XCTAssertEqual(restoredSettings.first?.trackingMode, .hybrid)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ClassificationRule>()).first?.timesUsed, 4)
    }
}
