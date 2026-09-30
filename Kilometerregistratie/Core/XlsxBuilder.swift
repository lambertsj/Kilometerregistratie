import Foundation

/// Bouwt een minimaal maar geldig .xlsx-bestand (Office Open XML) met één
/// werkblad. Strings gaan als inline strings mee zodat er geen
/// sharedStrings-tabel nodig is.
enum XlsxBuilder {
    static func workbook(
        rows: [TripReportRow],
        summary: ReportSummary,
        ruleSet: any RegionRuleSet,
        odometer: OdometerRange? = nil
    ) -> Data {
        let layout = ruleSet.exportLayout
        var sheetRows: [String] = []

        sheetRows.append(headerRow(layout.headers))

        for row in rows {
            let cells = layout.columns.map { column -> String in
                // Numerieke kolommen worden echte getalcellen; een ontbrekende
                // waarde wordt een lege tekstcel (zoals in versie 1).
                if column.field.isNumeric {
                    guard let value = ReportGenerator.numericValue(for: column.field, row: row) else {
                        return inlineString("")
                    }
                    return numberCell(value, decimals: column.field.decimals)
                }
                return inlineString(ReportGenerator.value(for: column.field, row: row, ruleSet: ruleSet))
            }
            sheetRows.append("<row>\(cells.joined())</row>")
        }

        // Samenvattingsblok onder de tabel.
        sheetRows.append("<row/>")
        for line in ReportGenerator.spreadsheetSummaryRows(summary, layout: layout, odometer: odometer) {
            sheetRows.append(summaryRow(line.label, line.value, decimals: line.decimals))
        }

        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>\(sheetRows.joined())</sheetData>
        </worksheet>
        """

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """

        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """

        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="\(escapeXML(layout.spreadsheetSheetName))" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """

        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """

        return ZipArchive.archive(entries: [
            .init(path: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            .init(path: "_rels/.rels", data: Data(rootRels.utf8)),
            .init(path: "xl/workbook.xml", data: Data(workbook.utf8)),
            .init(path: "xl/_rels/workbook.xml.rels", data: Data(workbookRels.utf8)),
            .init(path: "xl/worksheets/sheet1.xml", data: Data(sheet.utf8)),
        ])
    }

    // MARK: - Cellen

    private static func headerRow(_ headers: [String]) -> String {
        "<row>\(headers.map(inlineString).joined())</row>"
    }

    private static func summaryRow(_ label: String, _ value: Double, decimals: Int) -> String {
        "<row>\(inlineString(label))\(numberCell(value, decimals: decimals))</row>"
    }

    private static func inlineString(_ value: String) -> String {
        "<c t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXML(value))</t></is></c>"
    }

    private static func numberCell(_ value: Double, decimals: Int) -> String {
        "<c><v>\(String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value))</v></c>"
    }

    static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
