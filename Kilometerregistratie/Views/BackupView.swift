import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Versleutelde back-up maken en terugzetten. Het bestand wordt lokaal
/// gemaakt en de gebruiker kiest zelf waar het heen gaat (bv. de eigen
/// iCloud Drive via de Files-app) — er is geen account of server.
struct BackupView: View {
    @Environment(\.modelContext) private var context

    @State private var password = ""
    @State private var passwordRepeat = ""
    @State private var exportedFile: BackupFile?

    @State private var showsImporter = false
    @State private var importedData: Data?
    @State private var restorePassword = ""
    @State private var showsRestoreConfirmation = false

    @State private var infoMessage: String?
    @State private var errorMessage: String?

    private struct BackupFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        Form {
            Section {
                Text("Je back-up wordt versleuteld met een wachtwoord dat alleen jij kent. Bewaar het bestand waar je wilt — bijvoorbeeld in je eigen iCloud Drive via de Files-app. Zonder wachtwoord is het bestand onleesbaar; er is geen account en niets verlaat je toestel zonder jouw actie.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Back-up maken") {
                SecureField("Wachtwoord", text: $password)
                SecureField("Herhaal wachtwoord", text: $passwordRepeat)
                Button {
                    createBackup()
                } label: {
                    Label("Maak versleutelde back-up", systemImage: "lock.doc")
                }
                .disabled(password.count < 8 || password != passwordRepeat)
                if !password.isEmpty && password.count < 8 {
                    Text("Gebruik minimaal 8 tekens.")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                } else if !passwordRepeat.isEmpty && password != passwordRepeat {
                    Text("De wachtwoorden komen niet overeen.")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            }

            Section {
                Button {
                    showsImporter = true
                } label: {
                    Label("Kies back-upbestand…", systemImage: "square.and.arrow.down")
                }
                if importedData != nil {
                    SecureField("Wachtwoord van de back-up", text: $restorePassword)
                    Button("Zet back-up terug", role: .destructive) {
                        showsRestoreConfirmation = true
                    }
                    .disabled(restorePassword.isEmpty)
                }
            } header: {
                Text("Back-up terugzetten")
            } footer: {
                Text("Terugzetten vervangt alle huidige ritten, voertuigen en instellingen door de inhoud van de back-up.")
            }
        }
            .themedList()
        .navigationTitle("Back-up")
        .sheet(item: $exportedFile) { file in
            ShareSheet(url: file.url)
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.data]) { result in
            loadBackupFile(result)
        }
        .confirmationDialog(
            "Alle huidige gegevens vervangen?",
            isPresented: $showsRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Vervang alles", role: .destructive) { restoreBackup() }
            Button("Annuleer", role: .cancel) {}
        }
        .alert("Gelukt", isPresented: .constant(infoMessage != nil)) {
            Button("OK") { infoMessage = nil }
        } message: {
            Text(infoMessage ?? "")
        }
        .alert("Er ging iets mis", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func createBackup() {
        do {
            let document = try BackupService(context: context).createDocument()
            let data = try BackupCodec.encrypt(document, password: password)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Kilometerregistratie-\(formatter.string(from: .now)).kmregbackup")
            try data.write(to: url, options: .atomic)
            exportedFile = BackupFile(url: url)
            password = ""
            passwordRepeat = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadBackupFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                throw BackupCodecError.invalidFormat
            }
            defer { url.stopAccessingSecurityScopedResource() }
            importedData = try Data(contentsOf: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreBackup() {
        guard let data = importedData else { return }
        do {
            let document = try BackupCodec.decrypt(data, password: restorePassword)
            try BackupService(context: context).restore(from: document)
            importedData = nil
            restorePassword = ""
            let template = String(localized: "Back-up teruggezet: %1$@ en %2$@.", comment: "Melding na terugzetten van een back-up; %1$@ is het aantal ritten, %2$@ het aantal voertuigen")
            infoMessage = String(format: template, tripsCountText(document.trips.count), vehiclesCountText(document.vehicles.count))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        BackupView()
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
}
