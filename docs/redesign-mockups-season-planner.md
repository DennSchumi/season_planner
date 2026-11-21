# Redesign-Mockups – Season Planner (helle, moderne Designsprache)

Erstellt für einen Umsetzungs-Agenten. **Wichtig: Es ändert sich ausschließlich die
Optik (Farben, Formen, Abstände, Typografie, Icon-Sprache) – keine Funktionalität,
keine Navigationslogik, keine Datenmodelle.** Alle Vorschläge aus den beiden
vorherigen Reviews (`ux-verbesserungen-season-planner.md`,
`code-review-sicherheit-stabilitaet-appwrite.md`) bleiben unberührt und gültig;
dieses Dokument beschreibt nur die visuelle Oberfläche.

## Klickbare Mockups

Alle Screens als interaktives Mockup-Board (Figma-artiges Canvas, nicht
funktional, nur Optik):
**https://claude.ai/artifact/BXmtEe7RUXmDrHTCMCQPZt**

Enthält: Design-System-Übersicht (Farben/Typografie/Buttons/Chips), Login,
Nutzer-Start, Nutzer-Kalender, Event-Detail (Bottom-Sheet), Konto, Admin-Übersicht,
Admin-Kalender, Events verwalten, Event anlegen/bearbeiten, Flugschule verwalten,
Personal verwalten. Das Artifact ist aktuell **privat** – bevor es an andere
weitergegeben wird, muss es über das Share-Menü der Seite freigegeben werden.

Die übrigen Screens (Qualifikationen, Qualifikationsprüfung, Saisonplanung,
Statistik, Audit-Log, Registrierung …) sind nicht einzeln gemockt, folgen aber
mechanisch aus denselben Bausteinen/Tokens unten (gruppierte Karten-Listen wie
„Flugschule verwalten“, Formulare wie „Event anlegen“, Listen wie „Events
verwalten“).

## Leitidee

Hell, ruhig, klar getrennte Kacheln – angelehnt an moderne Banking-Apps (z. B.
Revolut, Light Mode):

- **Weiße AppBar statt Vollfarbe.** Das bisherige satte Lila (`#6A0DAD`) als
  Flächenfarbe der AppBar entfällt. Violett wird **Akzent** (aktive Icons,
  CTA-Buttons, Hervorhebungen), nicht mehr Fläche.
- **Kacheln statt Listen-Text/Trennlinien.** Jede Informationseinheit bekommt
  eine weiße, abgerundete Karte mit dezentem Schatten statt `Divider`-Linien.
- **Ein durchgängiges Icon-System.** Linien-Icons (≈1.8px Stroke), keine Emoji
  (ersetzt UX-Review-Befund 1.6/4.3), keine Mischung aus gefüllten und
  outlined Material-Icons.
- **Farbe = Bedeutung.** Status immer als Pastell-Pill (helle Füllung, kräftige
  Textfarbe derselben Farbfamilie), nie als zufällige/dekorative Farbe (löst
  UX-Review-Befund 2.6 „Event-Farben sind bedeutungslos" gleich mit).

## Design-Tokens (für `lib/core/theme.dart`)

```
Primary            #5B3DF5   (ersetzt #6A0DAD – gleiche Farbfamilie, moderner,
                               heller/kühler Violett-Ton)
Primary Tint (BG)  #EEEAFE   (Icon-Badges, aktive Nav-Pille, sekundäre Buttons)
Primary Dark       #4428D0   (Pressed-State, Shadows)
Ink / Text         #11131A   (ersetzt #1D1B20)
Text Secondary     #6B7280
Text Tertiary      #9AA3B2
Canvas Background  #F4F5FA   (ersetzt #F6F5FA – minimal kühler/heller)
Card / Surface     #FFFFFF
Border subtle      #ECEEF3

Success   Text #12805C / BG #E3F6ED
Warning   Text #B45309 / BG #FEF3C7
Danger    Text #D92D20 / BG #FEE4E2
Info      Text #1570EF / BG #EFF6FF
Swap/Teal Text #0F766E / BG #E4FBF7
Stufe 1   Text #7C3AED / BG #F3EAFE
```

**Radius:** Karten 18–20px, Buttons/Inputs 14px, Icon-Badges 10–12px, Chips/Pills
`999px` (voll rund).

**Schatten (statt Rahmen):** `box-shadow: 0 1px 2px rgba(16,24,40,.04), 0 8px 24px
rgba(16,24,40,.06)` als einzige Elevation-Stufe für Karten; Primär-Buttons
zusätzlich ein farbiger Glow (`0 8px 20px rgba(91,61,245,.25)`).

**Typografie:** Umstellung auf **Inter** (Google Fonts, `google_fonts`-Package
ist dafür geeignet) statt System-Default – Gewichte 400/500/600/700/800. Große,
selbstbewusste Zahlen für Kennzahlen-Kacheln (vgl. Admin-Übersicht), Caption-Texte
in Secondary-Farbe statt Schwarz mit Opacity.

**Spacing-Skala:** 8 / 12 / 16 / 20 / 24 / 32px – Außenabstand der Screens
durchgängig 20px links/rechts.

## Icon-System

Aktuell gemischt: Material-Icons (teils gefüllt, teils outlined) + Unicode-Emoji
(`✅`, `⚠️`) an einzelnen Stellen. Vorschlag: durchgängig ein outlined
Icon-Set mit 1.8–2px Stroke-Breite verwenden (z. B. konsequent die
`_outlined`-Variante aller verwendeten `Icons.*`, oder Umstieg auf ein Paket wie
`phosphor_flutter` für ein einheitliches Strichstärken-Gefühl wie in den
Mockups). Betrifft u. a. die Verfügbarkeits-Badges im Mitglied-Dropdown
(`event_upsert_view.dart`, aktuell Emoji) – dort durch Icon+Farbe ersetzen.

## Screen-für-Screen – was sich ändert (nur Optik)

**Start/Dashboard** (`lib/user/features/home/home_view.dart`,
`lib/fsAdmin/features/home/admin_home_view.dart`): graue Fließtext-Kennzahlen →
2-spaltige Kennzahlen-Kacheln mit Icon-Badge (Primary-Tint-Hintergrund), großer
Zahl, kurzer Caption. „Nächstes Event" bekommt eine hervorgehobene, farbige
Hero-Karte statt einer Listenzeile.

**Kalender** (`lib/core/widgets/calender_widget.dart` +
`fsAdmin/user calender_view.dart`): Monatsraster in eine weiße Karte mit
Schatten verschieben (aktuell freistehend auf dem Hintergrund); Status-Punkte/
-Balken statt Zufallsfarben (ist laut Runde-2-Test bereits teilweise umgesetzt –
hier nur die Farbwerte auf die neuen Tokens ummünzen); „Heute"-Chip und
Monat/Agenda-Umschalter als Pill-Segmented-Control im neuen Stil.

**Event-Detail** (`lib/user/features/home/widgets/event_detail_view.dart`):
als Bottom-Sheet mit großem Radius oben (28px), Status-Pill, Icon-Zeilen für
Zeit/Ort statt reinem Fließtext, Team-Avatare als überlappende Kreise.

**Konto** (`lib/user/features/account/account_view.dart`): Rollenwechsel
„Nutzer ⇄ Admin" nur noch als kleine Pille oben rechts in der AppBar – der
breite, primäre CTA-Button dafür entfällt (löst UX-Review-Befund 3.3). Übrige
Einstellungen als gruppierte Karten mit Icon-Badge + Chevron.

**Event anlegen/bearbeiten** (`lib/fsAdmin/features/widgets/event_upsert_view.dart`):
Beginn/Ende als **eine** tappbare Zusammenfassungs-Zeile („Fr, 21.11.2026 ·
15:00–17:00") mit Dauer-Pill und Lock-Icon statt zwei einzelnen Buttons –
visuelle Vereinfachung, löst nebenbei UX-Review 1.1 optisch mit (die
eigentliche Dialog-Mechanik aus Runde 2 bleibt wie vom UX-Review beschrieben zu
prüfen). Team-Mitglieder als Avatar-Kreise + „+"-Kreis zum Hinzufügen.
Serien-Block bleibt eingeklappt (schon umgesetzt). Nur **ein** Zugang zu
„Als Vorlage speichern" (Button in der unteren Aktionsleiste; AppBar-Icon
entfällt – löst UX-Review-Befund 2.2 gleich mit).

**Events verwalten** (`lib/fsAdmin/features/manage_events_view/manage_events_view.dart`):
Filter-Zeile kompakt (Suchfeld + ein Filter-Icon-Button mit Badge-Punkt statt
dauerhaft sichtbarer Status/Zeitraum/Saison-Zeilen – löst UX-Review 5.3).
Event-Zeilen als Karten mit Datums-Block links, Status-Pill(s) inkl.
Tausch-Indikator.

**Flugschule verwalten** (`lib/fsAdmin/features/manage_flight_school_view/manage_flight_school_view.dart`):
die bereits vorhandene 4er-Gruppierung (Organisation/Qualität & Sicherheit/
Planung & Auswertung/Sonstiges) bleibt – nur die Zeilen werden zu
Icon-Badge-Karten mit dezenter Sektionstrennung statt einfacher Listenzeilen.

**Personal verwalten** (`lib/fsAdmin/features/manage_personal/manage_personal_view.dart`):
Zeilen als Karten mit Avatar, Rollen-Pill, Status-Punkt. *Hinweis:* im Mockup
sind die Zeilen bewusst mit Chevron als „tappbar" dargestellt – das Nachrüsten
der tatsächlichen Tap-Funktion (aktuell laut UX-Review 2.1 nicht vorhanden) ist
eine **Funktionsänderung** und nicht Teil dieses rein visuellen Redesigns,
sollte aber zusammen mit der neuen Optik eingeplant werden, da das Mockup sie
bereits suggeriert.

## Hinweise für den Agenten

- Start in `lib/core/theme.dart`: neue Farbkonstanten, `cardTheme`-Radius auf
  18–20px, `elevation` weiterhin niedrig halten aber per Schatten in den
  Karten-Widgets selbst steuern statt über `Card`-Elevation (mehr Kontrolle
  über Revolut-typische weiche Schatten).
- Dark Theme (`AppTheme.darkTheme`) analog mit denselben Prinzipien
  nachziehen, nicht nur Light.
- Reine Optik-Änderung – vor Umsetzung mit den zwei bestehenden Dokumenten
  abgleichen, damit keine Doppelarbeit entsteht (z. B. Event-Farblogik ist in
  der UX-Review bereits als Funktions-Fix beschrieben, hier nur die Farbwerte).
- Mockups sind bewusst nur eine Auswahl repräsentativer Screens (alle
  Navigationsmuster: Dashboard, Liste, Kalender, Formular, gruppiertes Menü)
  – die übrigen Screens derselben Kategorie (z. B. „Qualifikationsprüfung" ist
  vom Muster „Liste" wie „Events verwalten") übernehmen dieselben Bausteine.
