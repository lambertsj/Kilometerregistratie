# Ontwerp: ritdetectie simuleren en testen zonder toestel

Datum: 2026-10-07 · Status: ter beoordeling

## 1. Doel en aanleiding

Een gebruiker meldde dat een rit op de telefoon niet uit zichzelf afsluit.
Onderzoek liet zien dat dit een samenspel was van detector, watchdog, service
en scherm over tijd, en dat één ontbrekende regel (`endDate` werd niet gezet)
alles liet blijven hangen. Elke fix kreeg een losse unit-test, maar er is geen
test die het scenario zelf nabootst (telefoon in zak, GPS pauzeert, app
opgeschort, kill en herstel). Dit ontwerp maakt zulke scenario's
reproduceerbaar en geautomatiseerd testbaar in `xcodebuild test`.

**Succescriteria**
- Scenario's als "rij 20 min, sta 30 min, app opgeschort, heropend" lopen in
  milliseconden en geven elke keer hetzelfde resultaat.
- Elke aanname over iOS staat expliciet vastgelegd, met ID, bron en een
  handmatige controle; elke scenariotest noemt de aannames waarop hij leunt.
- Alle drie de registratiemodi (handmatig, hybride, automatisch) en de
  combinaties uit het onderzoek zijn gedekt, aangevuld met een seed-gestuurde
  fuzz-test.
- De app verandert niet voor de gebruiker; bestaande tests blijven groen.

**Buiten scope**
- Bewijzen dat iOS zich zo gedraagt (dat blijft een handmatige controle).
- UI-tests en locatie-injectie via `simctl`.
- Een herschrijving van de service tot een pure toestandsmachine.

## 2. Aanpak

Afhankelijkheden van `LocationTrackingService` worden via vier protocollen
geïnjecteerd (aanpak A). De service blijft één klasse. Een toestandsmachine
(aanpak B) is bewust niet gekozen: het is een grote herschrijving en de dunne
laag eromheen zou het ongeteste stuk worden, terwijl juist daar eerder bugs
zaten.

## 3. Protocollen (productiecode, `Services/Platform/`)

Alle protocollen zijn `@MainActor`.

**`LocationProviding`** wrapt `CLLocationManager`.
- `authorizationStatus`, `locationServicesEnabled`
- `requestWhenInUse()`, `requestAlways()`
- `startUpdating()`, `stopUpdating()`
- `startSignificantChanges()`, `stopSignificantChanges()`
- `apply(accuracy:distanceFilter:)`
- `setBackground(allowed:showsIndicator:)`
- Gebeurtenissen via `LocationProvidingDelegate`: nieuwe locaties,
  toestemmingswijziging, fout.
- `CoreLocationProvider` bevat alleen de `CLLocationManagerDelegate`-methoden
  en de `Task { @MainActor }`-sprong die nu in de service staat. Geen logica.

**`MotionProviding`**: `start(handler:)` en `stop()`, levert
`MotionActivityGate.ActivitySample`. `CoreMotionProvider` bevat de
confidence-mapping die nu als private extensie in de service staat.

**`AddressResolving`**: `address(latitude:longitude:context:) async`.
`GeocodingService` voldoet er al aan. De nagebootste versie geeft een vast
adres terug, zodat scenario's geen netwerk raken.

**`TimeSource`**: `var now: Date` en
`every(_ interval: TimeInterval, _ action:) -> Cancellable`. Vervangt
`Task.sleep` in de watchdog en alle `Date.now` in de service.

## 4. Wijzigingen in `LocationTrackingService`

- `init(location:motion:time:geocoder:)` met echte standaardwaarden;
  `KilometerregistratieApp` blijft ongewijzigd behalve punt 3.
- `manager.` wordt `location.`, `motionActivityManager` wordt `motion`,
  `.now` wordt `time.now`, de watchdog wordt `time.every(30) { … }`.
- Nieuwe methode `appDidBecomeActive()`; de app roept die aan bij
  `scenePhase == .active` in plaats van `checkWatchdog` rechtstreeks.
- De service voldoet aan `LocationProvidingDelegate`; de
  `CLLocationManagerDelegate`-extensie verhuist naar `CoreLocationProvider`.
- `startRecording` en `handle(locations:)` blijven internal omdat bestaande
  tests ze gebruiken.
- Kill en herstart vragen geen extra naad: een nieuwe service op dezelfde
  `ModelContext`, gevolgd door `configure`, `applySettings` en
  `resumeIfNeeded`, zoals de app het doet.

## 5. Testgereedschap (`KilometerregistratieTests/Simulation/`)

**`VirtualClock`** (`TimeSource`). Eén wachtrij van gebeurtenissen op een
gedeelde tijdlijn: GPS-samples, timers, levenscyclus, gebruikershandelingen.
`advance(by:)` verwerkt ze op volgorde en zet de klok bij elke gebeurtenis op
haar tijdstip. Timers gaan alleen af als `FakeIOS` dat toestaat.

**`FakeIOS`**. Bepaalt de app-toestand (voorgrond, achtergrond-actief,
opgeschort, beëindigd) en wanneer locatie-callbacks en timers worden geleverd.
Elke regel is een instelbare waarde met een aannameverwijzing (hoofdstuk 7):
distanceFilter, auto-pauze na N minuten, hervatten bij beweging, herstart bij
significante wijziging. Voorgeprogrammeerde ruis: `speed = -1`, grote
`horizontalAccuracy`, een eerste fix na een pauze met verouderde tijd. Alle
willekeur loopt via een RNG met vaste seed.

**`FakeLocationProvider`, `FakeMotionProvider`, `FakeAddressResolver`**.
Voldoen aan de protocollen en leggen elke aanroep vast, zodat tests kunnen
controleren dat bijvoorbeeld de updates na een rit zijn gestopt.

**`RoutePlayer`**. Genereert samples langs een route met een snelheidsprofiel
(1 Hz), onderworpen aan de regels van `FakeIOS`.

**`ScenarioRunner`**. Kiest instellingen (`.automatisch(stopNa:)`, `.hybride`,
`.handmatig`) en `FakeIOS`-parameters en biedt stappen:
`rij(route, duur)`, `sta(duur)`, `file(duur)`, `tunnel(duur)`, `gat(duur)`,
`app.opschorten()`, `app.hervatten()`, `app.killen()`, `app.herstarten()`,
`toestemming(.ingetrokken)`, `gebruiker.tiktStart()`, `gebruiker.tiktStop()`,
`wacht(duur)`. De uitkomst komt uit de database: `ritten`, `openRit`, `route`,
`afstand`.

## 6. Invarianten en fuzz-test

Na elk scenario controleert de runner automatisch:

1. Nooit meer dan één open rit tegelijk.
2. Geen overlappende ritten; `endDate >= startDate`.
3. Na afloop plus afwikkeltijd geen open automatische rit.
4. Einddatum ligt hooguit drempel + 60 s (`gpsSilenceGrace`) + 30 s
   (timerinterval) na het laatste beweegmoment.
5. Opgeslagen afstand wijkt hooguit 3% af van de gereden route.
6. Een gat in de samples telt niet mee als afstand.

De fuzz-test kiest per seed een willekeurige reeks stappen over alle drie de
modi, met `FakeIOS`-parameters uit een bereik (auto-pauze 5 tot 20 minuten).
Een mislukte seed wordt als vaste regressietest vastgelegd.

## 7. iOS-aannames (`docs/ios-assumptions.md`)

Per aanname: ID, formulering, bron, de instelbare waarde in `FakeIOS`, en een
handmatige controle op een toestel. De status is de huidige inschatting en nog
niet geverifieerd, behalve waar "zeker" staat.

| ID | Aanname | Status |
|---|---|---|
| A0 | Callbacks komen in volgorde binnen op de main actor | zeker |
| A1 | `distanceFilter` onderdrukt samples zonder beweging | Apple-doc, nog te controleren |
| A2 | Na N minuten stilstand pauzeert iOS de updates (`pausesLocationUpdatesAutomatically`); N is niet gedocumenteerd | onbekend, meten op toestel |
| A3 | Een opgeschorte app voert geen timers uit | zeker |
| A4 | Bij hervatten van de updates wordt de app wakker gemaakt | te verifiëren |
| A5 | Een significante wijziging start een beëindigde app opnieuw | Apple-doc, nog te controleren |
| A6 | Beëindigde app verliest geheugen, SwiftData blijft | zeker |
| A7 | `speed` is `-1` als de snelheid onbekend is | Apple-doc |
| A8 | `timestamp` is het tijdstip van de fix, niet van de levering | Apple-doc, nog te controleren |
| A9 | Toestemming intrekken in Instellingen beëindigt de app | te verifiëren |
| A10 | Bewegingsactiviteit is verouderd na het opschorten | te verifiëren |

Eén bewust verschil met het echte gedrag: de nagebootste locatiebron levert
synchroon, de echte adapter springt via `Task { @MainActor }`. Dat is A0.

## 8. Risico's

- Het blijft een model van iOS. Is A2 of A4 in werkelijkheid anders, dan kan
  een groene suite onterecht geruststellen. Daarom zijn ze parameters en loopt
  de fuzz-test over een bereik.
- De echte adapters blijven ongetest. Tegenmaatregel: ze bevatten geen
  logica, één rooktest maakt ze in de Simulator aan en laat een locatie
  binnenkomen, en de handmatige controles staan in het aannamedocument.
- De refactor raakt het hart van de opname. Bestaande tests (79) moeten
  onveranderd groen blijven en gaan vóór elke volgende stap.

## 9. Volgorde van uitvoering (voor het plan)

1. Protocollen en echte adapters; service gebruikt ze; bestaande tests groen.
2. `VirtualClock`, fakes en `FakeIOS`; eerste scenario ter controle.
3. `RoutePlayer` en `ScenarioRunner` met invarianten; scenario's voor de
   situaties uit het onderzoek (geval 1 t/m 13).
4. Fuzz-test.
5. `docs/ios-assumptions.md` en rooktest voor de adapters.
