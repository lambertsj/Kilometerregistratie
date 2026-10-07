# iOS-aannames achter de ritsimulatie

De scenario-tests (`KilometerregistratieTests/ScenarioTests.swift`, `ScenarioFuzzTests.swift`)
draaien op een model van iOS (`KilometerregistratieTests/Simulation/FakeIOS.swift`). Dit document
legt vast wat dat model aanneemt. Een groene suite bewijst dat **onze logica** klopt onder deze
aannames, niet dat iOS zich zo gedraagt. Elke aanname is daarom een instelbare waarde in
`IOSParameters` en heeft een handmatige controle op een toestel.

**Status:** `zeker` = volgt uit hoe Swift/SwiftData werkt; `Apple-doc` = staat in de
Apple-documentatie, nog te controleren tegen de huidige versie; `te verifiëren` = inschatting,
nog niet gemeten; `meten` = niet gedocumenteerd, waarde moet op een toestel gemeten worden.
Geen enkele aanname is tot nu toe op een toestel gecontroleerd.

| ID | Aanname | Status | Waarde in model | Handmatige controle |
|---|---|---|---|---|
| A0 | Callbacks van CoreLocation komen in volgorde binnen op de main actor. De echte adapter springt via `Task { @MainActor }`, het model levert synchroon af. | zeker | n.v.t. | n.v.t. |
| A1 | `distanceFilter` onderdrukt samples zolang het toestel minder dan die afstand beweegt. | Apple-doc | `FakeLocationProvider.distanceFilter` (25 m standaard) | Laat de telefoon op tafel liggen met een lopende rit en tel de samples in de log. |
| A2 | Met `pausesLocationUpdatesAutomatically` en `.automotiveNavigation` pauzeert iOS de updates na enige tijd stilstand. De duur is niet gedocumenteerd. | meten | `autoPauseAfter` (600 s; fuzz 300 tot 1200 s) | Rit eindigen, telefoon met scherm uit laten liggen, de log laten tonen wanneer de laatste update binnenkwam. |
| A3 | Een opgeschorte app voert geen code uit, ook geen `Task.sleep`-timers. | zeker | `VirtualClock.timersEnabled` | n.v.t. |
| A4 | Hervatten van de updates (beweging na een pauze) maakt een opgeschorte app wakker en levert samples af. | te verifiëren | `wakesWhenUpdatesResume` (aan; fuzz beide) | Na een pauze weer gaan rijden zonder de app te openen; kijk of de rit verder loopt. |
| A5 | Een significante wijziging (ongeveer 500 m) start een beëindigde app opnieuw op de achtergrond. | Apple-doc | `significantChangeDistance` (500 m) | App in de app-schakelaar wegvegen, 1 km rijden, kijken of er een rit ontstaat. |
| A6 | Een beëindigd proces verliest zijn geheugen; de SwiftData-database blijft. | zeker | n.v.t. | n.v.t. |
| A7 | `CLLocation.speed` is `-1` als de snelheid onbekend is. | Apple-doc | `Fix.speed = -1` | Log de snelheid bij een zwakke fix (tunnel, parkeergarage). |
| A8 | `CLLocation.timestamp` is het tijdstip van de fix, niet van de levering; na een pauze kan het oud zijn. | Apple-doc | `Fix.timestamp` (nu altijd gelijk aan virtuele tijd) | Vergelijk `timestamp` met `Date.now` in de log bij het eerste sample na een pauze. |
| A9 | De toestemming intrekken in Instellingen beëindigt de app. | te verifiëren | `revokingPermissionTerminatesApp` (aan) | Tijdens een rit de locatietoestemming op "Nooit" zetten en kijken of het proces stopt. |
| A10 | Bewegingsactiviteit (`CMMotionActivity`) is verouderd na het opschorten. | te verifiëren | niet gemodelleerd; `FakeMotionProvider.send` laat tests het nabootsen | Bij een rit na een lange pauze loggen wanneer de laatste activiteit binnenkwam. |
| A11 | Bij het wakker worden van een opgeschorte app vuren verlopen timers vóór het eerste locatiesample. De volgorde is onbekend. | te verifiëren | `timersResumeBeforeFirstSample` (aan; fuzz beide) | Log in `checkWatchdog` en in `handle(locations:)` met tijdstempel, laat de app wakker worden door te gaan rijden, en lees de volgorde. |

## Wat het model bewust niet doet

- Geen batterij- of thermische beperkingen, geen "Low Power Mode".
- Geen systeemdialogen of ontbrekende toestemming "Bij gebruik" versus "Altijd" op de achtergrond
  (de service krijgt altijd `.authorizedAlways`, behalve bij het intrekken).
- Geen netwerk (`FakeAddressResolver` geeft altijd hetzelfde adres).
- Een gebruiker tikt alleen in een draaiende app: na een kill of opschorten opent de simulatie de
  app eerst (`ScenarioRunner.userTapsStart/Stop`).

## Wat de simulatie al heeft gevonden

- Hervatte automatische ritten eindigden op het heropenmoment in plaats van het laatste teken van
  leven (gevonden door `testKillDuringTripThenQuickRelaunchResumesWithRoute`); opgelost met
  `lastActivityAt` in `LocationTrackingService`.
- Een rit bleef voor altijd open staan als de toestemming verdween terwijl de app gekild was en de
  app binnen 30 minuten weer werd geopend (gevonden door fuzz seed 26,
  `testRelaunchWithoutPermissionWithinResumeWindowFinalizesTrip`); opgelost in `resumeIfNeeded`.
- De gat-controle in `TripDetector` werd door geen enkel scenario geraakt omdat de watchdog altijd
  eerst afsloot; mutatiecheck leidde tot `testDetectorEndsTripOnGapWhenSampleArrivesBeforeTimers`
  en aanname A11.

## Een aanname bijwerken

1. Meet of lees het echte gedrag.
2. Pas de status en de waarde in deze tabel aan.
3. Pas `IOSParameters` of `FakeIOS` aan en draai `ScenarioTests` en `ScenarioFuzzTests`
   (meer seeds: `TEST_RUNNER_FUZZ_SEEDS=600 xcodebuild test …`).
4. Een scenario dat daardoor faalt, laat een echte bug zien. Repareer de app, niet de aanname.
