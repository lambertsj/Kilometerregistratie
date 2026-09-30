import Foundation
import CryptoKit
import CommonCrypto

/// Draagbaar back-upformaat: alle app-data als JSON, versleuteld met
/// AES-GCM. De sleutel wordt met PBKDF2 (SHA-256, 210k rondes) afgeleid
/// van een wachtwoord dat alleen de gebruiker kent. De gebruiker bewaart
/// het bestand zelf (bv. in de eigen iCloud Drive via de Files-app) —
/// er is geen server en geen account nodig, en zonder wachtwoord is het
/// bestand onleesbaar.
struct BackupDocument: Codable, Equatable {
    struct TripDTO: Codable, Equatable {
        var id: UUID
        var startDate: Date
        var endDate: Date?
        var startAddress: String
        var endAddress: String
        var startLatitude: Double?
        var startLongitude: Double?
        var endLatitude: Double?
        var endLongitude: Double?
        var distanceKm: Double
        var startOdometer: Double?
        var endOdometer: Double?
        var category: String
        var note: String
        var clientLabel: String
        var isAutomaticallyRecorded: Bool
        var routeData: Data?
        var vehicleID: UUID?

        // Formaatversie 2. Optioneel met een standaardwaarde, zodat een
        // back-up van versie 1 gewoon inleesbaar blijft.
        var destinationPlace: String = ""
        var destinationStreet: String = ""
        var purpose: String = ""
        var businessPartner: String = ""
        var detourNote: String = ""
        var deletedAt: Date?
    }

    /// Formaatversie 2: de audit trail hoort bij de rit en moet dus mee in de
    /// back-up — anders levert terugzetten een dossier op zonder
    /// wijzigingsgeschiedenis.
    struct RevisionDTO: Codable, Equatable {
        var id: UUID
        var tripID: UUID
        var changedAt: Date
        var tripStartDate: Date
        var changeKind: String
        var field: String
        var previousValue: String
        var newValue: String
        var wasContemporaneous: Bool
    }

    struct VehicleDTO: Codable, Equatable {
        var id: UUID
        var name: String
        var licensePlate: String
        var vehicleType: String
        var initialOdometer: Double
        var createdAt: Date
    }

    struct SettingsDTO: Codable, Equatable {
        var trackingMode: String
        var reimbursementRatePerKm: Double
        var workHoursEnabled: Bool
        var workDayStartMinute: Int
        var workDayEndMinute: Int
        var workWeekdays: [Int]
        var autoStopThresholdMinutes: Int
        /// Formaatversie 2; oudere back-ups vallen terug op Nederland.
        var taxRegion: String = TaxRegion.netherlands.rawValue
    }

    struct RuleDTO: Codable, Equatable {
        var routeKey: String
        var category: String
        var timesUsed: Int
    }

    var formatVersion: Int
    var exportDate: Date
    var trips: [TripDTO]
    var vehicles: [VehicleDTO]
    var settings: SettingsDTO?
    var classificationRules: [RuleDTO]
    /// Leeg bij een back-up van formaatversie 1.
    var revisions: [RevisionDTO] = []
}

enum BackupCodecError: LocalizedError {
    case invalidFormat
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            String(localized: "Dit is geen geldig back-upbestand van Kilometerregistratie.", comment: "Foutmelding: back-upbestand heeft een onherkenbaar formaat")
        case .wrongPassword:
            String(localized: "Het wachtwoord klopt niet, of het bestand is beschadigd.", comment: "Foutmelding: back-up kan niet ontsleuteld worden")
        }
    }
}

/// Versleutelt en ontsleutelt back-updocumenten.
enum BackupCodec {
    /// Bestandsheader zodat we vreemde bestanden vroeg kunnen afwijzen.
    private static let magic = Data("KMREG1\n".utf8)
    private static let saltLength = 16
    private static let pbkdf2Rounds: UInt32 = 210_000

    static func encrypt(_ document: BackupDocument, password: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(document)

        var salt = Data(count: saltLength)
        let saltResult = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }
        guard saltResult == errSecSuccess else { throw BackupCodecError.invalidFormat }

        let key = deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(payload, using: key)
        guard let combined = sealed.combined else { throw BackupCodecError.invalidFormat }

        return magic + salt + combined
    }

    static func decrypt(_ data: Data, password: String) throws -> BackupDocument {
        guard data.count > magic.count + saltLength, data.prefix(magic.count) == magic else {
            throw BackupCodecError.invalidFormat
        }
        let salt = data.subdata(in: magic.count..<(magic.count + saltLength))
        let combined = data.subdata(in: (magic.count + saltLength)..<data.count)

        let key = deriveKey(password: password, salt: salt)
        let payload: Data
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            payload = try AES.GCM.open(box, using: key)
        } catch {
            throw BackupCodecError.wrongPassword
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(BackupDocument.self, from: payload) else {
            throw BackupCodecError.invalidFormat
        }
        return document
    }

    /// PBKDF2-HMAC-SHA256; bewust veel rondes zodat brute-force op een
    /// gestolen back-upbestand onpraktisch is.
    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        _ = salt.withUnsafeBytes { saltBuffer in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password, passwordBytes.count,
                saltBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                pbkdf2Rounds,
                &derived, derived.count
            )
        }
        return SymmetricKey(data: Data(derived))
    }
}
