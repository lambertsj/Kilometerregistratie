import UIKit

/// Rendert een `ReportDocumentPlan` als PDF (A4 liggend). Deze laag doet
/// bewust géén layoutbeslissingen meer: welke kolommen er zijn, wat de rijen
/// bevatten en waar de pagina's breken staat in het plan, dat UI-vrij en
/// testbaar is (zie `Core/ReportDocumentPlan.swift`).
enum PDFReportRenderer {
    static func render(
        rows: [TripReportRow],
        summary: ReportSummary,
        ruleSet: any RegionRuleSet,
        periodLabel: String,
        generatedAt: Date = .now,
        odometer: OdometerRange? = nil
    ) -> Data {
        let plan = ReportDocumentPlan.make(
            rows: rows,
            summary: summary,
            ruleSet: ruleSet,
            periodLabel: periodLabel,
            generatedAt: generatedAt,
            odometer: odometer
        )
        return render(plan: plan)
    }

    static func render(plan: ReportDocumentPlan) -> Data {
        let geometry = plan.geometry
        let rowHeight = CGFloat(geometry.rowHeight)
        let bounds = CGRect(x: 0, y: 0, width: geometry.pageWidth, height: geometry.pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        let headerFont = UIFont.boldSystemFont(ofSize: 7)
        let cellFont = UIFont.systemFont(ofSize: 7)
        let titleFont = UIFont.boldSystemFont(ofSize: 16)
        let metaFont = UIFont.systemFont(ofSize: 9)
        let widths = plan.columnWidths

        return renderer.pdfData { context in
            var y: CGFloat = 0

            for page in plan.pages {
                y = startPage(context, page: page, titleFont: titleFont, metaFont: metaFont, geometry: geometry)
                y = drawTableHeader(page.headers, atY: y, font: headerFont, widths: widths, geometry: geometry)
                for row in page.rows {
                    drawRow(values: row, atY: y, font: cellFont, widths: widths, geometry: geometry)
                    y += rowHeight
                }
            }

            if plan.summaryOnOwnPage, let last = plan.pages.last {
                y = startPage(context, page: last, titleFont: titleFont, metaFont: metaFont, geometry: geometry)
            }
            var summaryY = drawSummary(
                title: plan.summaryTitle,
                entries: plan.summaryEntries,
                atY: y + 16,
                margin: geometry.margin
            )

            if let note = plan.note {
                summaryY += 12
                (note as NSString).draw(
                    in: CGRect(
                        x: CGFloat(geometry.margin), y: summaryY,
                        width: CGFloat(geometry.pageWidth - 2 * geometry.margin), height: 40
                    ),
                    withAttributes: [.font: metaFont, .foregroundColor: UIColor.darkGray]
                )
                summaryY += 40
            }

            if let legendTitle = plan.legendTitle, !plan.legendEntries.isEmpty {
                drawSummary(
                    title: legendTitle,
                    entries: plan.legendEntries,
                    atY: summaryY + 16,
                    margin: geometry.margin,
                    valueOffset: 200
                )
            }
        }
    }

    // MARK: - Tekenen

    private static func startPage(
        _ context: UIGraphicsPDFRendererContext,
        page: ReportDocumentPlan.Page,
        titleFont: UIFont,
        metaFont: UIFont,
        geometry: ReportPageGeometry
    ) -> CGFloat {
        context.beginPage()
        let margin = CGFloat(geometry.margin)
        page.title.draw(at: CGPoint(x: margin, y: margin), withAttributes: [.font: titleFont])

        // Kopregels onder elkaar. Het voertuig hoort in de kop van een
        // Fahrtenbuch; regio's zonder die regel (Nederland) leveren hier nil
        // en houden dus exact de bestaande kop van één regel.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: metaFont, .foregroundColor: UIColor.darkGray,
        ]
        var lineY = margin + 22
        if let vehicleLine = page.vehicleLine {
            vehicleLine.draw(at: CGPoint(x: margin, y: lineY), withAttributes: attributes)
            lineY += CGFloat(geometry.headerLineHeight)
        }
        page.meta.draw(at: CGPoint(x: margin, y: lineY), withAttributes: attributes)
        return CGFloat(geometry.tableTop)
    }

    private static func drawTableHeader(
        _ headers: [String],
        atY y: CGFloat,
        font: UIFont,
        widths: [Double],
        geometry: ReportPageGeometry
    ) -> CGFloat {
        let margin = CGFloat(geometry.margin)
        let rowHeight = CGFloat(geometry.rowHeight)
        UIColor(white: 0.9, alpha: 1).setFill()
        UIRectFill(CGRect(x: margin, y: y, width: tableWidth(widths), height: rowHeight))
        drawRow(values: headers, atY: y, font: font, widths: widths, geometry: geometry)
        return y + rowHeight
    }

    private static func tableWidth(_ widths: [Double]) -> CGFloat {
        CGFloat(widths.reduce(0, +))
    }

    private static func drawRow(
        values: [String],
        atY y: CGFloat,
        font: UIFont,
        widths: [Double],
        geometry: ReportPageGeometry
    ) {
        let margin = CGFloat(geometry.margin)
        let rowHeight = CGFloat(geometry.rowHeight)
        var x = margin
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]

        for (index, width) in widths.enumerated() {
            let value = index < values.count ? values[index] : ""
            let rect = CGRect(x: x + 2, y: y + 3, width: CGFloat(width) - 4, height: rowHeight - 6)
            (value as NSString).draw(in: rect, withAttributes: attributes)
            x += CGFloat(width)
        }

        UIColor(white: 0.8, alpha: 1).setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: y + rowHeight))
        line.addLine(to: CGPoint(x: margin + tableWidth(widths), y: y + rowHeight))
        line.lineWidth = 0.5
        line.stroke()
    }

    /// Tekent een label/waarde-blok en geeft de y-positie eronder terug.
    @discardableResult
    private static func drawSummary(
        title: String,
        entries: [SummaryEntry],
        atY y: CGFloat,
        margin: Double,
        valueOffset: CGFloat = 140
    ) -> CGFloat {
        let originX = CGFloat(margin)
        let labelFont = UIFont.boldSystemFont(ofSize: 10)
        let valueFont = UIFont.systemFont(ofSize: 10)

        title.draw(at: CGPoint(x: originX, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 12)])

        for (index, entry) in entries.enumerated() {
            let lineY = y + 20 + CGFloat(index) * 16
            entry.label.draw(at: CGPoint(x: originX, y: lineY), withAttributes: [.font: labelFont])
            entry.value.draw(at: CGPoint(x: originX + valueOffset, y: lineY), withAttributes: [.font: valueFont])
        }
        return y + 20 + CGFloat(entries.count) * 16
    }
}
