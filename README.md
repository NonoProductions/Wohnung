# Zuhause – Home Assistant für dein iPhone

Native SwiftUI-App (iOS 17+, Swift 6, ohne externe Abhängigkeiten). Sie verbindet sich über die WebSocket-API mit Home Assistant, zeigt deine Räume (HA-Areas) mit Kacheln an und reagiert sofort auf Änderungen.

**Funktionen**
- Übersicht mit Heizungs-Schnellknöpfen („Alle Nacht“, „Alle Abwesend“, „Alle aufwärmen“) und Raumkarten (Temperatur, Luftfeuchte, Licht an/aus). Oben rechts das Zahnrad für die Einstellungen, dort lassen sich auch die Räume sortieren.
- Soll-Temperatur pro Raum über einen Drehregler wie in Apple Home, daneben nur die aktuelle Raumtemperatur. Unten im Heizungsfenster wählst du pro Raum Normal, Nacht oder Abwesend. Bei jedem Moduswechsel springt der Raum auf die feste Temperatur aus den Einstellungen (Aufwärmen pro Raum, Nacht und Abwesend für alle). Drehst du von Hand, steht der Raum auf „Manuell“. Diesen Modus kann man nicht auswählen, er erscheint nur nach dem Drehen (in der App oder im HA-Dashboard, Automation „Heizung: Manuell erkennen“). Er gilt bis zum nächsten Moduswechsel, die festen Werte bleiben unverändert. Ein Tippen auf einen Modus setzt den Raum wieder auf dessen feste Temperatur.
- Raumseiten wie im Dashboard „Zuhause“: Licht, Heizung, Raumklima, Szenen, Batterien
- Szenen kommen aus **Apple Home** (über HomeKit), nicht aus Home Assistant. Die Szenen von Home Assistant (und das Skript „Heizung: Aufheizzeit messen“) zeigt die App nicht mehr an, auch nicht als Favorit. In Home Assistant selbst bleiben sie erhalten. Eine Szene erscheint im Raum, wenn alle ihre Geräte in Apple Home in einem Raum mit gleichem Namen stehen (z. B. „Wohnzimmer“). Szenen über mehrere Räume stehen auf der Übersicht unter „Szenen“. Antippen führt die Szene über Apple Home aus. Beim ersten Start fragt iOS nach dem Zugriff auf „Home“. Ohne diese Erlaubnis bleiben die Szenen leer (ändern unter Einstellungen → Datenschutz → HomeKit).
- Licht: Es werden nur Lichtgruppen angezeigt. Einzelne Lampen erscheinen nur, wenn sie in keiner Gruppe sind. Hue-Räume werden nie angezeigt. Hat der Raum eigene Gruppen (Wohnzimmer), bleiben ihre Lampen ausgeblendet. Ist der Hue-Raum die einzige Gruppe (Schlafzimmer), stehen die Lampen einzeln da. Die Lampen einer Gruppe findest du in deren Detailansicht. Gruppen ohne Raum bekommen den Raum ihrer Lampen. Ob eine Gruppe an ist, richtet sich nach ihren Lampen, nicht nach dem Gruppenzustand von Hue, der manchmal hängen bleibt (z. B. nach dem Ausschalten in Apple Home).
- Heizung über deine Helfer statt direkt am Thermostat: Wunschtemperatur (`input_number.wunschtemperatur_<raum>`), Heizmodus (`input_select.heizmodus_<raum>`: Komfort, Nacht, Abwesend, Manuell), feste Temperaturen (`input_number.aufwarmtemperatur_<raum>`, `input_number.temperatur_nacht`, `input_number.temperatur_abwesend`). „Heizung: Feste Temperatur je Modus“ setzt beim Moduswechsel die Wunschtemperatur, „Heizung: Externe Thermometer nutzen“ stellt daraus die Thermostate.
- Morgens aufwärmen (Karte auf der Übersicht oder in den Einstellungen): Du stellst ein, um wie viel Uhr es warm sein soll (`input_datetime.aufstehzeit`), welche Räume mitmachen (`input_boolean.morgens_aufwarmen_<raum>`) und wie warm jeder wird (`input_number.morgentemperatur_<raum>`). Ein Zeitstrahl zeigt, wann jeder Raum startet. Die Automation „Heizung: Vor dem Aufstehen aufwärmen“ startet jeden Raum um fehlende Grad × seine Aufheizzeit (`input_number.aufheizzeit_<raum>`, Minuten pro Grad) vor der Zeit, 15 bis 240 Minuten. Der Raum wechselt dann auf „Normal“ mit der Morgentemperatur. Mitgenommen wird jeder Raum, der kühler als seine Morgentemperatur eingestellt ist, egal in welchem Modus (Nacht, Abwesend, Normal oder Manuell). Nur Räume, die schon mindestens so warm eingestellt sind, bleiben unverändert. Soll gar nicht aufgewärmt werden (z. B. im Urlaub), schalte „Morgens aufwärmen“ ganz aus.
- Die Aufheizzeit lernt sich selbst, aber nur wenn ein Raum von „Nacht“ aus aufwärmt. Kommt er aus einem anderen Modus (z. B. „Abwesend“), startet er nach derselben gelernten Zeit, ohne sie zu verändern, und ist dann eventuell nicht ganz rechtzeitig warm. Beim Start misst das Skript „Heizung: Aufheizzeit messen“, wann das Raumthermometer die Morgentemperatur erreicht, und verbessert damit den Wert des Raums. Die ersten Morgen zählen voll, danach jeder neue zu 30 %, so pendelt er sich ein. `counter.aufheizen_gelernt_<raum>` zählt die Messungen. In der App steht am Raum „Schätzung“, „Lernt“ oder ab drei Morgen „Eingelernt“.
- Heizungslüfter: Auf der Raumseite unter der Heizung steht die Karte „Heizungslüfter“, sobald es `input_number.heizungslufter_<raum>_stufe` gibt. Sie zeigt, ob die Lüfter laufen (Aus, Halten oder Stufe in %) und ob der Raum Wärme braucht (`binary_sensor.<raum>_braucht_warme`). Oben rechts schaltest du die Steckdose (`switch.<raum>_luftung_heitzung_plug`), der Regler stellt die Stufe (der ESP32 liest sie per REST-API). Eine Stufe über 0 schaltet die Steckdose mit ein. Der Schalter „Automatik“ schaltet die Automation `automation.heizungslufter_<raum>` an oder aus. Beim Einschalten läuft sie einmal sofort. Ist die Automatik an, gilt eine Änderung von Hand nur bis zur nächsten Änderung (Licht, Wärmebedarf, Heizmodus).
- 24-h-Verlauf für jeden Sensor in der Detailansicht
- Steuerbar: Lichter (an/aus, Helligkeit, Farbtemperatur, Farbe), Rollläden (auf/zu/Stopp/Position), Schalter, Szenen aus Apple Home; Sensoren nur zur Anzeige
- Antippen schaltet sofort. Lehnt HA den Befehl ab oder kommt keine Bestätigung, springt die Kachel zurück und ein Hinweis erscheint.
- Langes Drücken öffnet die Detailansicht, dort gibt es den Stern für die Favoriten.
- Die ersten 4 Favoriten erscheinen im Homescreen-Widget und lassen sich dort direkt schalten.
- Siri und Kurzbefehle: „Schalte Stehlampe 1 mit Zuhause ein/aus“
- Im WLAN nutzt die App die lokale Adresse, sonst die externe. Bricht die Verbindung ab, verbindet sie sich automatisch neu (Wartezeit 1, 2, 4 … bis 60 s).
- Der Token liegt im iOS-Schlüsselbund, nicht in UserDefaults.
- Konfigurations- und Diagnose-Entities (Firmware, Übergangszeiten …) sowie in HA ausgeblendete Entities werden nicht angezeigt.

## 1. Token in Home Assistant erstellen

1. Home Assistant im Browser öffnen und unten links auf deinen **Benutzernamen (Profil)** klicken.
2. Oben den Reiter **Sicherheit** wählen.
3. Ganz unten bei **Langlebige Zugriffstoken** auf **Token erstellen** klicken und einen Namen vergeben, z. B. „iPhone App“.
4. Den angezeigten Token **sofort kopieren**, denn er wird nur einmal angezeigt. Am einfachsten schickst du ihn dir per AirDrop oder über die gemeinsame Zwischenablage aufs iPhone.
5. In der App beim ersten Start einfügen („Aus Zwischenablage einfügen“).

Tipp: Nimm einen Admin-Benutzer. Nur damit darf die App die Räume (Area-Registry) lesen. Mit einem normalen Benutzer funktioniert alles, aber ohne Raumaufteilung.

Adressen beim Einrichten:
- **Im WLAN:** z. B. `http://homeassistant.local:8123` oder `http://192.168.x.x:8123`
- **Unterwegs (optional):** z. B. deine Nabu-Casa-Adresse `https://xxxx.ui.nabu.casa`

## 2. App mit deiner Apple-ID aufs iPhone bringen

### Einmalig in Xcode
1. `Zuhause.xcodeproj` in Xcode öffnen.
2. **Xcode → Settings → Accounts → „+“ → Apple ID** und mit deiner Apple-ID anmelden. Ein kostenloser Account reicht.
3. Links im Projekt-Navigator **Zuhause** (blaues Symbol) anklicken.
4. Für **beide Targets** (`Zuhause` und `ZuhauseWidgetExtension`) unter **Signing & Capabilities** bei **Team** dein „(Personal Team)“ auswählen. „Automatically manage signing“ bleibt an. Das Target `Zuhause` braucht außerdem die Capability **HomeKit** (für die Szenen aus Apple Home). Sie steht schon in `Config/Zuhause.entitlements`. Fehlt sie unter Signing & Capabilities, füge sie mit „+ Capability“ → HomeKit hinzu.
5. Eigene Bundle-ID festlegen: Lege die Datei `Config/Local.xcconfig` an mit der Zeile `BUNDLE_ID_PREFIX = de.deinname`. Bundle-IDs und App-Group-ID passen sich dann automatisch an. Die Datei wird nicht ins Git-Repository hochgeladen (siehe `.gitignore`). Ohne sie gilt der Platzhalter `com.example` aus `Config/Base.xcconfig`.

### iPhone vorbereiten
1. iPhone per Kabel an den Mac anschließen und **„Diesem Computer vertrauen“** bestätigen.
2. **Entwicklermodus einschalten:** Einstellungen → Datenschutz & Sicherheit → ganz unten **Entwicklermodus** → an. Das iPhone startet neu, danach bestätigst du mit „Aktivieren“. Der Punkt erscheint erst, nachdem das iPhone einmal mit Xcode verbunden war.
3. In Xcode oben als Ziel dein iPhone auswählen und **▶︎ (Run)** drücken (⌘R).
4. Beim ersten Start meldet iOS „Nicht vertrauenswürdiger Entwickler“. Dann: Einstellungen → Allgemein → **VPN und Geräteverwaltung** → deine Apple-ID → **Vertrauen**.
5. Beim ersten Verbinden fragt iOS nach dem Zugriff aufs **lokale Netzwerk**. Bitte erlauben, sonst klappt die lokale Adresse nicht.

### Widget und Siri
- **Widget:** Auf dem Homescreen lange drücken → „Bearbeiten“ → „Widget hinzufügen“ → „Zuhause“. Es zeigt deine ersten 4 Favoriten. Die Reihenfolge änderst du in der App unter Einstellungen → „Widget-Favoriten sortieren“.
- **Siri:** „Schalte *Gerät* mit Zuhause ein“ bzw. „… aus“. Apple verlangt den App-Namen im Satz. Für kürzere Befehle wie „Stehlampe an“ legst du in der **Kurzbefehle-App** einen Kurzbefehl mit der Aktion „Gerät einschalten“ an und benennst ihn „Stehlampe an“. Die Geräteliste für Siri wird aktualisiert, sobald die App einmal verbunden war.

## 3. Alle 7 Tage neu installieren (kostenloser Account)

Mit einem kostenlosen Account ist die Signatur nur **7 Tage** gültig. Danach startet die App nicht mehr. Deine Daten (Token, Favoriten) bleiben erhalten.

**Neu installieren:** iPhone anschließen (oder per WLAN, siehe unten), Projekt in Xcode öffnen und **▶︎ Run** drücken. Das dauert unter einer Minute.

**Ohne Kabel:** In Xcode **Window → Devices and Simulators** öffnen, dein iPhone auswählen und **„Connect via network“** anhaken. Danach erscheint das iPhone als Ziel, solange Mac und iPhone im selben WLAN sind.

Weitere Grenzen des kostenlosen Accounts: höchstens 3 selbst signierte Apps gleichzeitig auf dem Gerät. App + Widget zählen als eine App.

**Dauerhaft vermeiden:** Mit dem **Apple Developer Program (99 €/Jahr)** ist die Signatur **1 Jahr** gültig. Unter developer.apple.com anmelden, danach in Xcode bei Team dein bezahltes Team statt „Personal Team“ wählen und einmal neu installieren. Ganz ohne jährliches Neuinstallieren geht es über **TestFlight** (Build alle 90 Tage) oder mit AltStore/SideStore, das die kostenlose Signatur automatisch im Hintergrund erneuert.

## Hinweise

- Das Widget und Siri lesen Token und Favoriten über eine App Group (`group.<BUNDLE_ID_PREFIX>.zuhause`). Lehnt Xcode die App Group für dein Personal Team ab, entferne unter Signing & Capabilities bei beiden Targets **App Groups**. Die App selbst funktioniert dann weiter, nur Widget und Siri finden die Verbindungsdaten nicht.
- Debug-Builds lesen zum Testen im Simulator optional die Umgebungsvariablen `ZUHAUSE_DEBUG_URL`, `ZUHAUSE_DEBUG_TOKEN`, `ZUHAUSE_DEBUG_FAVORITES` und `ZUHAUSE_DEBUG_TAPS` (siehe `App/DebugLaunchOptions.swift`). In Release-Builds ist dieser Code nicht enthalten.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `App/` | App-Target: WebSocket-Client, `HomeStore` (Zustand, Neuverbindung, optimistisches Schalten), Views, Siri-Phrasen |
| `Shared/` | Gemeinsam für App und Widget: Modelle, Keychain, Adresswahl WLAN/extern, REST-Client, App Intents |
| `Widget/` | WidgetKit-Erweiterung mit den 4 Favoriten |
| `Config/` | Info.plist-Ergänzungen und Entitlements |
