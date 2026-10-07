import SwiftUI
import UIKit

/// Ontwerpsysteem van de app: kleuren, kaartstijl en cijfertypografie.
///
/// Alle kleuren zijn semantisch benoemd (rol, niet tint) en passen zich aan
/// licht/donker aan. Contrast is per paar gemeten (>= 4,5:1 op `card` en
/// `canvas` voor tekstkleuren). Schermen gebruiken alleen deze tokens.
enum Theme {
    // MARK: Kleuren

    /// Merkaccent: diep petrol (licht) / helder aqua (donker). Bedoeld voor
    /// interactieve elementen en de primaire actie.
    static let accent = dynamic(light: 0x0A6B73, dark: 0x5CC8CF)
    /// Tekst/icoon op een gevulde accentvlak.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x062326)
    /// Paginabackground.
    static let canvas = dynamic(light: 0xF2F6F6, dark: 0x0D1415)
    /// Kaartvlak boven `canvas`.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x162022)
    /// Haarlijn rond kaarten.
    static let hairline = dynamic(light: 0xDCE5E5, dark: 0x263336)
    static let ok = dynamic(light: 0x1E7A45, dark: 0x5CCB8A)
    static let warning = dynamic(light: 0x9A5B00, dark: 0xE8A94A)
    static let danger = dynamic(light: 0xC0392B, dark: 0xFF8A7A)
    /// Gevulde gevaar-knop (STOP): vaste rode vulling met witte tekst.
    static let dangerFill = dynamic(light: 0xC0392B, dark: 0xC0392B)

    // Categoriekleuren: onderling en t.o.v. het accent goed te onderscheiden.
    static let business = dynamic(light: 0x2B58C4, dark: 0x7FA0F5)
    static let commute = dynamic(light: 0x9A5B00, dark: 0xE8A94A)
    static let personal = dynamic(light: 0x8445B8, dark: 0xC39BEB)

    // MARK: Maten

    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 12
    /// Maximale inhoudsbreedte zodat het scherm op grote toestellen en in
    /// landscape niet uitrekt.
    static let maxContentWidth: CGFloat = 640

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Typografie

extension Font {
    /// Afgeronde cijfers voor kilometers en bedragen; schaalt mee met Dynamic Type.
    static func figure(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }
}

// MARK: - Kaart en achtergrond

extension View {
    /// Kaartvlak met haarlijn en zachte, getinte schaduw.
    func themedCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }

    /// Canvas-achtergrond voor lijsten en formulieren.
    func themedList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
    }

    /// Begrenst de breedte en centreert (landscape, grote toestellen).
    func readableWidth() -> some View {
        self
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
    }
}

/// Knopstijl met voelbare indruk (schaal) voor primaire acties.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
