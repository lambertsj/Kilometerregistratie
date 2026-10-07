import SwiftUI
import SwiftData
import UIKit

/// Rapportage & export: kies periode en voertuig, bekijk de totalen en
/// exporteer een Belastingdienst-conform rapport als PDF, Excel of CSV.
struct ReportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query private var allSettings: [AppSettings]

    @State private var period: PeriodFilter = .quarter
    @State private var usesCustomRange = false
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var vehicleFilter: UUID?

    @State private var exportedFile: ExportedFile?
    @State private var errorMessage: String?

    private var settings: AppSettings {
        allSettings.first ?? AppSettings.fetchOrCreate(in: context)
    }

    /// De regelset van de ingestelde regio bepaalt de kolommen, de taal en de
    /// opmaak van elke export. Er staat hier bewust nergens een regiotoets.
    private var ruleSet: any RegionRuleSet { settings.ruleSet }

    // MARK: - Selectie

    private var periodRange: (start: Date?, end: Date?, label: String) {
        if usesCustomRange {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: customEnd))
            let formatting = ruleSet.formatting
            let label = formatting.date(customStart)
                + ruleSet.exportLayout.customRangeSeparator
                + formatting.date(customEnd)
            return (Calendar.current.startOfDay(for: customStart), end, label)
        }
        return (period.startDate(), nil, period.exportLabel(for: settings.taxRegion))
    }

    /// Ritten zonder tombstones (zie `Trip.isDeleted`).
    private var visibleTrips: [Trip] {
        trips.filter { !$0.isDeleted }
    }

    private var selectedRows: [TripReportRow] {
        let range = periodRange
        return visibleTrips
            .filter { trip in
                trip.endDate != nil
                    && (range.start == nil || trip.startDate >= range.start!)
                    && (range.end == nil || trip.startDate < range.end!)
                    && (vehicleFilter == nil || trip.vehicle?.id == vehicleFilter)
            }
            .map { trip in
                TripReportRow(
                    startDate: trip.startDate,
                    endDate: trip.endDate,
                    startAddress: trip.startAddress,
                    endAddress: trip.endAddress,
                    startOdometer: trip.startOdometer,
                    endOdometer: trip.endOdometer,
                    distanceKm: trip.distanceKm,
                    category: trip.category,
                    note: trip.note,
                    clientLabel: trip.clientLabel,
                    vehicleName: trip.vehicle?.name ?? "",
                    vehicleLicensePlate: trip.vehicle?.licensePlate ?? "",
                    destinationPlace: trip.destinationPlace,
                    destinationStreet: trip.destinationStreet,
                    purpose: trip.purpose,
                    businessPartner: trip.businessPartner,
                    detourNote: trip.detourNote
                )
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Periode") {
                    Toggle("Aangepaste periode", isOn: $usesCustomRange)
                    if usesCustomRange {
                        DatePicker("Van", selection: $customStart, displayedComponents: .date)
                        DatePicker("Tot en met", selection: $customEnd, in: customStart..., displayedComponents: .date)
                    } else {
                        Picker("Periode", selection: $period) {
                            ForEach(PeriodFilter.allCases) { period in
                                Text(period.displayName).tag(period)
                            }
                        }
                    }
                    if !vehicles.isEmpty {
                        Picker("Voertuig", selection: $vehicleFilter) {
                            Text("Alle voertuigen").tag(UUID?.none)
                            ForEach(vehicles) { vehicle in
                                Text(vehicle.name).tag(UUID?.some(vehicle.id))
                            }
                        }
                    }
                }

                summarySection

                Section {
                    NavigationLink {
                        LogValidationView()
                    } label: {
                        Label("Registratie controleren", systemImage: "checkmark.shield")
                    }
                } footer: {
                    Text("Bekijk of de rittenregistratie van het huidige belastingjaar compleet en sluitend is, vóórdat je exporteert.")
                }

                Section {
                    exportButton(title: "PDF-rapport", icon: "doc.richtext", format: .pdf)
                    exportButton(title: "Excel (.xlsx)", icon: "tablecells", format: .xlsx)
                    exportButton(title: "CSV", icon: "doc.plaintext", format: .csv)
                } header: {
                    Text("Exporteren")
                } footer: {
                    Label(settings.taxRegion.complianceNotice, systemImage: "info.circle")
                }
            }
                .themedList()
            .navigationTitle("Rapport")
            .sheet(item: $exportedFile) { file in
                ShareSheet(url: file.url)
            }
            .alert("Er ging iets mis", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var summarySection: some View {
        let summary = ReportGenerator.summary(rows: selectedRows, ratePerKm: settings.reimbursementRatePerKm)
        return Section("Samenvatting") {
            LabeledContent("Ritten", value: "\(summary.tripCount)")
            LabeledContent("Totaal", value: "\(summary.totalKm.formatted(.number.precision(.fractionLength(0...1)))) km")
            LabeledContent("Zakelijk", value: "\(summary.businessKm.formatted(.number.precision(.fractionLength(0...1)))) km")
            LabeledContent("Woon-werk", value: "\(summary.commuteKm.formatted(.number.precision(.fractionLength(0...1)))) km")
            LabeledContent("Privé", value: "\(summary.personalKm.formatted(.number.precision(.fractionLength(0...1)))) km")
            LabeledContent("Vergoeding", value: summary.reimbursement.formatted(.currency(code: "EUR")))
        }
    }

    // MARK: - Export

    private enum ExportFormat {
        case pdf, xlsx, csv

        var fileExtension: String {
            switch self {
            case .pdf: "pdf"
            case .xlsx: "xlsx"
            case .csv: "csv"
            }
        }
    }

    private struct ExportedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private func exportButton(title: LocalizedStringResource, icon: String, format: ExportFormat) -> some View {
        Button {
            export(format)
        } label: {
            Label(title, systemImage: icon)
        }
        .disabled(selectedRows.isEmpty)
    }

    private func export(_ format: ExportFormat) {
        let rows = selectedRows
        let summary = ReportGenerator.summary(rows: rows, ratePerKm: settings.reimbursementRatePerKm)
        // Kilometerstand over de periode, om de totalen mee te laten sluiten.
        // Levert nil bij meerdere voertuigen of ontbrekende standen; de
        // betreffende regels vallen dan uit de samenvatting.
        let odometer = ReportGenerator.odometerRange(for: rows)

        let data: Data
        switch format {
        case .pdf:
            data = PDFReportRenderer.render(
                rows: rows, summary: summary, ruleSet: ruleSet,
                periodLabel: periodRange.label, odometer: odometer
            )
        case .xlsx:
            data = XlsxBuilder.workbook(rows: rows, summary: summary, ruleSet: ruleSet, odometer: odometer)
        case .csv:
            data = Data(ReportGenerator.csv(rows: rows, ruleSet: ruleSet).utf8)
        }

        let stem = ruleSet.exportLayout.fileNameStem
        let filename = "\(stem)-\(ruleSet.formatting.date(.now)).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            exportedFile = ExportedFile(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Standaard iOS share sheet voor het exporteren van rapportbestanden.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    ReportView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
