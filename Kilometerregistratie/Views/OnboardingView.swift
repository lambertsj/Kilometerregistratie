import SwiftUI

/// Korte, eerlijke onboarding: wat de app doet, hoe privacy geregeld is en
/// waarom (en wanneer) er locatietoestemming gevraagd wordt.
struct OnboardingView: View {
    /// Krijgt de gekozen regio mee, ook als de gebruiker overslaat: dan is het
    /// het voorstel op basis van de toestelregio.
    let onFinish: (TaxRegion) -> Void

    @State private var page = 0
    @State private var region: TaxRegion = .suggested(for: Locale.current.region?.identifier)

    private let lastPage = 3

    var body: some View {
        VStack {
            TabView(selection: $page) {
                OnboardingPage(
                    icon: "car.fill",
                    title: "Sluitende rittenregistratie",
                    text: "Registreer ritten met één tik of volledig automatisch, classificeer ze als zakelijk, woon-werk of privé, en exporteer een rapport dat voldoet aan de eisen van de Belastingdienst."
                )
                .tag(0)

                OnboardingPage(
                    icon: "lock.shield.fill",
                    title: "Jouw data blijft van jou",
                    text: "Alles wordt lokaal op je iPhone opgeslagen. Geen account, geen abonnement, geen advertenties en geen data naar servers. Een back-up maak je zelf — versleuteld, met een wachtwoord dat alleen jij kent."
                )
                .tag(1)

                OnboardingPage(
                    icon: "location.fill",
                    title: "Locatie, alleen voor jouw ritten",
                    text: "Voor route en afstand vraagt de app om locatietoegang zodra je een rit start. Wil je dat ritten vanzelf starten en stoppen, zet dan in Instellingen de automatische registratie aan — daarvoor is toestemming \u{201C}Altijd\u{201D} nodig. Je locatie verlaat je toestel nooit."
                )
                .tag(2)

                regionPage
                    .tag(3)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < lastPage {
                    withAnimation { page += 1 }
                } else {
                    onFinish(region)
                }
            } label: {
                // Expliciet als `String` opgebouwd in plaats van een ternary
                // rechtstreeks in `Text(...)`: een ternary van twee
                // letterlijke strings wordt door Swift als `String`
                // geïnfereerd, niet als `LocalizedStringKey`, en zou dus niet
                // vanzelf gelokaliseerd worden.
                Text(page < lastPage
                    ? String(localized: "Volgende", comment: "Knop: volgende onboardingpagina")
                    : String(localized: "Aan de slag", comment: "Knop: onboarding afronden")
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            if page < lastPage {
                Button("Overslaan") { onFinish(region) }
                    .font(.subheadline)
                    .padding(.bottom, 8)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
    }
}

private extension OnboardingView {
    /// Regiokeuze. Het voorstel komt uit de toestelregio, maar de gebruiker
    /// kiest expliciet: taal en fiscale regio staan los van elkaar.
    var regionPage: some View {
        VStack(spacing: 24) {
            Spacer()
            OnboardingIcon(systemName: "globe.europe.africa.fill")
            Text("Welke regels gelden voor jou?")
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Kies het land waarvoor je de rittenregistratie bijhoudt. Dat bepaalt welke gegevens per rit nodig zijn en hoe het rapport eruitziet. Je kunt dit later wijzigen in Instellingen.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(TaxRegion.allCases) { option in
                    Button {
                        region = option
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: option == region ? "largecircle.fill.circle" : "circle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.displayName)
                                    .font(.headline)
                                Text(option.settingsDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            option == region ? Theme.accent.opacity(0.10) : Theme.card,
                            in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous)
                                .strokeBorder(option == region ? Theme.accent : Theme.hairline, lineWidth: option == region ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

private struct OnboardingPage: View {
    let icon: String
    /// `LocalizedStringResource` in plaats van `String`: zo blijft
    /// `Text(title)` de gelokaliseerde `Text(LocalizedStringResource)`-
    /// initializer gebruiken. Met een plain `String` zou `Text(_:)` de
    /// niet-lokaliserende `Text(StringProtocol)`-initializer kiezen en de
    /// letterlijke, ongelokaliseerde tekst tonen.
    let title: LocalizedStringResource
    let text: LocalizedStringResource

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            OnboardingIcon(systemName: icon)
            Text(title)
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

/// Pictogram in een zachte accentcirkel.
private struct OnboardingIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 48, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 112, height: 112)
            .background(Theme.accent.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingView { _ in }
}
