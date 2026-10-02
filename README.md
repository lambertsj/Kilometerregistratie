# Kilometerregistratie

[![Basis Certified](https://basisapps.nl/badge.svg)](https://basisapps.nl)

Native iOS-app voor kilometerregistratie en rittenadministratie, gebouwd met SwiftUI en SwiftData.
Offline-first en privacy-first: alle gegevens blijven lokaal op het toestel. Er is geen backend,
geen account en geen analytics.

De interface is Nederlands. Er is ook een Duitse regio-set (Fahrtenbuch-export) aanwezig.

## BasisApps

Deze app is onderdeel van [BasisApps](https://basisapps.nl), het initiatief voor
eerlijke apps die gewoon gratis horen te zijn: geen abonnementen of in-app aankopen, geen advertenties,
geen tracking, gegevens zoveel mogelijk lokaal en transparant. In de App Store heet de app
**Basis: Kilometerregistratie** (Duitse listing: **Basis: Fahrtenbuch GPS**).

## Functies

- **Automatische ritdetectie**: ritten starten en stoppen vanzelf, met bewegingsgegevens (Core Motion)
  om lopen, fietsen en openbaar vervoer uit te filteren.
- **Slimme classificatie**: zakelijk, woon-werk of privé, met regels die de app van je keuzes leert.
- **Dashboard**: overzicht per periode, inclusief de 500-kilometerteller.
- **Rapportage en export**: PDF en Excel (`.xlsx`), zonder externe libraries.
- **Voorafgaande controle** van het ritregister op gaten en onregelmatigheden.
- **Back-up en herstel** van alle gegevens als bestand.
- **Meerdere voertuigen** en een revisiespoor per rit.

## Privacy

Locatie en bewegingsgegevens verlaten het toestel nooit. De app heeft geen server, geen
inlogsysteem en verstuurt geen telemetrie.

## Aan de slag

Vereisten: Xcode, iOS 17+, [xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open Kilometerregistratie.xcodeproj
```

Deze xcodegen-installatie laadt geen SettingPresets, dus alle build settings staan expliciet in
`project.yml`. Vul zelf een `DEVELOPMENT_TEAM` in om op een toestel te draaien.

Build zonder simulator:

```sh
xcodebuild -project Kilometerregistratie.xcodeproj -scheme Kilometerregistratie \
  -destination 'generic/platform=iOS Simulator' build
```

## Structuur

| Map | Inhoud |
| --- | --- |
| `Kilometerregistratie/App` | app-entry en ModelContainer |
| `Kilometerregistratie/Models` | SwiftData-modellen en migraties |
| `Kilometerregistratie/Core` | pure, UI-vrije logica: afstand, classificatie, ritdetectie, rapportage, XLSX/ZIP, back-up, regio-regels |
| `Kilometerregistratie/Services` | tracking, geocoding, routeafstand, back-up, PDF-rendering |
| `Kilometerregistratie/Repositories` | queries en CRUD op SwiftData |
| `Kilometerregistratie/Views` | SwiftUI-schermen |
| `Kilometerregistratie/Resources` | String Catalog (`Localizable.xcstrings`) |
| `KilometerregistratieTests` | XCTest unit tests |
| `tools/CoreHarness` | losse testharness voor de kernlogica |
| `AppStoreAssets` | App Store-screenshots (nl en de) |

## Tests

De kernlogica in `Core/` importeert bewust geen CoreLocation of UIKit. Daardoor draait de
harness op de Mac, zonder simulator en zonder Xcode-project:

```sh
./tools/run-core-harness.sh
```

De XCTest-suite draait via `xcodebuild test` op een simulator-destination.

## Conventies

- Warnings zijn errors (`SWIFT_TREAT_WARNINGS_AS_ERRORS`).
- Kernlogica blijft UI-vrij en testbaar.

## Licentie

[MIT](LICENSE)
