import XCTest
@testable import Kilometerregistratie

final class ReportTests: XCTestCase {
    /// Exports zijn regiogebonden; deze suite dekt de Nederlandse regelset.
    /// De byte-vergelijking met golden files staat in `tools/CoreHarness`.
    private let dutch: any RegionRuleSet = NetherlandsRuleSet()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private var rows: [TripReportRow] {
        [
            TripReportRow(startDate: date(2026, 3, 2), endDate: date(2026, 3, 2), startAddress: "Thuisstraat 1; Dorp", endAddress: "Kantoorlaan 5", startOdometer: 50_000, endOdometer: 50_030, distanceKm: 30, category: .business, note: "Klantbezoek \"Jansen\"", clientLabel: "Jansen BV", vehicleName: "Bedrijfsauto"),
            TripReportRow(startDate: date(2026, 3, 3), endDate: nil, startAddress: "", endAddress: "", startOdometer: nil, endOdometer: nil, distanceKm: 12.5, category: .personal, note: "", clientLabel: "", vehicleName: ""),
            TripReportRow(startDate: date(2026, 3, 4), endDate: date(2026, 3, 4), startAddress: "A", endAddress: "B", startOdometer: nil, endOdometer: nil, distanceKm: 7.5, category: .commute, note: "", clientLabel: "", vehicleName: ""),
        ]
    }

    func testSummaryTotals() {
        let summary = ReportGenerator.summary(rows: rows, ratePerKm: 0.23)
        XCTAssertEqual(summary.tripCount, 3)
        XCTAssertEqual(summary.totalKm, 50)
        XCTAssertEqual(summary.businessKm, 30)
        XCTAssertEqual(summary.commuteKm, 7.5)
        XCTAssertEqual(summary.personalKm, 12.5)
        XCTAssertEqual(summary.reimbursement, 6.9, accuracy: 0.001)
    }

    func testCSVEscapingAndFormat() {
        let csv = ReportGenerator.csv(rows: rows, ruleSet: dutch)
        XCTAssertTrue(csv.hasPrefix("Datum;Vertrek;Aankomst;"))
        XCTAssertTrue(csv.contains("\"Thuisstraat 1; Dorp\""), "veld met puntkomma moet gequote worden")
        XCTAssertTrue(csv.contains("\"Klantbezoek \"\"Jansen\"\"\""), "aanhalingstekens moeten verdubbeld worden")
        XCTAssertTrue(csv.contains("02-03-2026"))
        XCTAssertTrue(csv.contains("30,0"), "NL decimale komma")
        XCTAssertEqual(csv.components(separatedBy: "\r\n").count, 5)
    }

    func testXlsxIsValidZipWithExpectedParts() {
        let summary = ReportGenerator.summary(rows: rows, ratePerKm: 0.23)
        let data = XlsxBuilder.workbook(rows: rows, summary: summary, ruleSet: dutch)
        XCTAssertEqual(data.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]), "zip local file header signature")

        let contents = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(contents.contains("[Content_Types].xml"))
        XCTAssertTrue(contents.contains("xl/worksheets/sheet1.xml"))
        XCTAssertTrue(contents.contains("Kantoorlaan 5"))
    }

    func testXlsxNumberCellsUseTheRequestedPrecision() {
        // Regressie: summaryRow negeerde eerder zijn `decimals`-parameter en
        // formatteerde alles met 3 decimalen (bv. "3.000" ritten i.p.v. "3").
        let summary = ReportGenerator.summary(rows: rows, ratePerKm: 0.23)
        let data = XlsxBuilder.workbook(rows: rows, summary: summary, ruleSet: dutch)
        let contents = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(contents.contains("<v>50000</v>"), "kilometerstand zonder decimalen")
        XCTAssertTrue(contents.contains("<v>30.0</v>"), "afstand met 1 decimaal")
        XCTAssertTrue(contents.contains("<v>3</v>"), "ritaantal zonder decimalen")
        XCTAssertTrue(contents.contains("<v>6.90</v>"), "vergoeding met 2 decimalen")
        XCTAssertFalse(contents.contains(".000<"), "geen overbodige decimalen meer")
    }

    func testCRC32ReferenceValue() {
        // Bekende referentiewaarde voor "123456789" (IEEE 802.3).
        XCTAssertEqual(ZipArchive.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    func testXMLEscaping() {
        XCTAssertEqual(XlsxBuilder.escapeXML("A & B < C > \"D\""), "A &amp; B &lt; C &gt; &quot;D&quot;")
    }

    /// FASE 3-randgevallen: een rit die middernacht overschrijdt, en een rit
    /// zonder eindadres/kilometerstand. Geen van beide mag de export laten
    /// crashen of velden laten verdwijnen.
    func testExportHandlesOvernightTripAndMissingFields() {
        let overnight = TripReportRow(
            startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 23, minute: 30))!,
            endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 0, minute: 45))!,
            startAddress: "Kantoor", endAddress: "Thuis",
            startOdometer: nil, endOdometer: nil,
            distanceKm: 40, category: .business, note: "", clientLabel: "", vehicleName: ""
        )
        let summary = ReportGenerator.summary(rows: [overnight], ratePerKm: 0.23)

        let csv = ReportGenerator.csv(rows: [overnight], ruleSet: dutch)
        XCTAssertTrue(csv.contains("02-03-2026;23:30;00:45"), "datum blijft die van vertrek, aankomsttijd is die van de volgende dag")

        let xlsxData = XlsxBuilder.workbook(rows: [overnight], summary: summary, ruleSet: dutch)
        XCTAssertFalse(xlsxData.isEmpty)
        XCTAssertEqual(xlsxData.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]))
    }
}
