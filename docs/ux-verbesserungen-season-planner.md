# UX-Verbesserungsliste – Season Planner (Nutzer- & Flugschulseite)

Erstellt für einen Umsetzungs-Agenten. **Wichtig: Es wird ausschließlich an Darstellung,
Interaktion und Anordnung gearbeitet – keine Funktionalität ändert sich.** Jeder Punkt
nennt Datei(en)/Zeilen, das Problem, die Begründung (UX-Prinzip) und einen konkreten
Lösungsvorschlag. Die Reihenfolge der Abschnitte entspricht der Priorität; innerhalb
eines Abschnitts ist die Nummerierung keine strikte Rangfolge.

## Methodik
- Code-Review von `lib/user/**`, `lib/fsAdmin/**`, `lib/core/**`.
- Live-Test im Browser gegen den lokalen Flutter-Web-Dev-Build (produktives
  Appwrite-Backend `tragegurt.com`), mit einem Testaccount, der sowohl Nutzer- als
  auch Flugschul-Admin-Rolle hat.
- Bewertung anhand der `ui-ux-pro-max`-Richtlinien (Accessibility, Forms & Feedback,
  Navigation Patterns, Style/Color, Layout & Responsive).
- Testaccount hatte keine Events/Verfügbarkeiten angelegt → Kalenderdarstellung mit
  vielen/überlappenden Events wurde nur anhand des Codes bewertet, nicht live.

---

## 1. Event-Erstellung (höchste Priorität)

**Dateien:** `lib/fsAdmin/features/widgets/event_upsert_view.dart`,
`lib/fsAdmin/features/manage_events_view/manage_events_view.dart`

1.1 **Start/Ende brauchen je 2 native Dialoge (Datum, dann Uhrzeit).**
`_pickDateTime` (Zeilen 233–249) ruft `showDatePicker` und danach `showTimePicker`
nacheinander auf – für die mit Abstand häufigste Aktion im Admin-Alltag (Event
anlegen) sind das 4 Dialoge nur für Start+Ende. *Vorschlag:* kombiniertes
Datum+Uhrzeit-Bottom-Sheet, plus Schnellauswahl-Chips ("09:00–17:00", "Ganztägig",
"+1 Woche") und eine sichtbare Dauer-Anzeige ("2 Std.") direkt neben den beiden
Buttons, damit die Länge ohne Kopfrechnen ersichtlich ist.

1.2 **Datum-/Uhrzeit-Dialoge sind auf Englisch und im 12h-AM/PM-Format**, obwohl die
gesamte App deutsch und 24h-geprägt ist (live verifiziert: „Select date“, „Cancel“,
„OK“, AM/PM-Zifferblatt). Ursache: `lib/main.dart` (MaterialApp, Zeilen 35–53) setzt
keine `localizationsDelegates`/`supportedLocales`/`locale`. *Vorschlag:* App um
deutsche Lokalisierung ergänzen (`GlobalMaterialLocalizations.delegate`,
`GlobalWidgetsLocalizations.delegate`, `GlobalCupertinoLocalizations.delegate`,
`locale: Locale('de','DE')`). Betrifft **alle** `showDatePicker`/`showTimePicker`/
`showDateRangePicker`-Aufrufe der App (auch Verfügbarkeiten-Dialog, Event-Filter
„Zeitraum“). Sehr hoher Nutzen bei geringem Aufwand – höchste Priorität im ganzen
Dokument.

1.3 **„Änderungen verwerfen?“-Dialog erscheint beim Schließen (X) immer**, auch wenn
nichts geändert wurde (`_confirmDiscard`, Zeilen 163–186, verknüpft mit dem
Close-Icon in Zeile 880). *Vorschlag:* Dirty-State tracken (Ausgangswerte vs.
aktuelle Werte vergleichen) und den Dialog nur bei echten Änderungen anzeigen.

1.4 **Serienevent-Block ist immer sichtbar** (Zeilen 1016–1096), auch wenn so gut
wie immer „Keine Wiederholung“ gewählt wird. *Vorschlag:* als eingeklappten
Schalter „Wiederholendes Event“ darstellen; Intervall-/Anzahl-Felder erst bei
Aktivierung einblenden. Reduziert visuelle Last im Standardfall (Einzelevent).

1.5 **Keine Vorschau der erzeugten Serientermine** vor dem Speichern – der Admin
muss blind vertrauen, dass Intervall × Anzahl das Gewünschte ergibt. *Vorschlag:*
kleine Liste/Chip-Reihe mit den berechneten Terminen (Datum 1, 2, 3 …) einblenden,
sobald Intervall ≠ „Keine Wiederholung“.

1.6 **Verfügbarkeits-Badges im Mitglied-Dropdown nutzen Unicode-Emoji** (`✅
Verfügbar`, `⚠️ Abwesend`, Zeilen 346–360) statt der sonst in der App verwendeten
Material-Icons. Das ist inkonsistent mit der übrigen Icon-Sprache (vgl. 4.3).
*Vorschlag:* durch Icon+Farbe ersetzen, wie es im Rest des Formulars (z. B.
`Icons.event_busy`) bereits gemacht wird.

1.7 **Keine „Duplizieren“-Funktion für ein bestehendes Event.** Wer ein ähnliches
Event wie letztes Jahr/letzte Woche anlegen will, muss alle Felder erneut
ausfüllen. *Vorschlag:* Aktion „Als Kopie neu anlegen“ in der Event-Liste
(`manage_events_view.dart`) oder im Bearbeiten-Screen ergänzen.

1.8 **Keine Warnung bei Terminüberschneidung.** Der Verfügbarkeits-/Blackout-Check
beim Hinzufügen eines Teammitglieds (Zeilen 142–159) prüft nur gegen eingetragene
Verfügbarkeiten, nicht gegen eine bereits bestehende Doppelbuchung derselben
Person in einem zeitgleichen anderen Event. *Vorschlag:* einfache
Überlappungsprüfung über `fs.events` ergänzen und als Hinweis (analog zum
Blackout-Hinweis) anzeigen.

1.9 **Event-Erstellung ist nur über den „Events“-Tab erreichbar**, nicht direkt aus
dem Kalender heraus – siehe Abschnitt 2 für den zugehörigen Kalender-Fix.

---

## 2. Kalenderansicht (höchste Priorität – explizit genannter Schwerpunkt)

**Dateien:** `lib/core/widgets/calender_widget.dart` (gemeinsame Komponente),
`lib/fsAdmin/features/calender_view/calender_view.dart`,
`lib/user/features/calender/calender_view.dart`

2.1 **Tippen auf einen Tag hat keine Funktion.** `onTap` setzt nur `_selectedDay`
fürs Hervorheben (Zeilen 302–306 in `calender_widget.dart`) – live auf Nutzer- und
Admin-Seite verifiziert: der Tag wird lila markiert, sonst passiert nichts. Das ist
ein toter Interaktionspfad, der wie ein Button aussieht. *Vorschlag (Admin):* Tap
auf leeren Tag öffnet „Neues Event“ mit vorausgefülltem Datum; Tap auf einen Tag
mit Events öffnet eine Tages-Agenda (Bottom-Sheet) mit allen Events dieses Tages
(wichtig auch für 2.3). *Vorschlag (Nutzer):* Tap zeigt zumindest die Tagesagenda.

2.2 **Admin-Kalender hat keinen „Neues Event“-Einstiegspunkt** (kein FAB, keine
Aktion in `calender_view.dart` der Flugschule) – Bruch im Workflow: der Admin sieht
ein freies Datum im Kalender vor sich, muss aber zum Anlegen erst in den
„Events“-Tab wechseln und dort Datum/Uhrzeit erneut eintragen. *Vorschlag:* FAB
„Neues Event“ auch im Kalender-Tab ergänzen, Datum aus 2.1 vorausfüllen.

2.3 **„+N weitere“ bei >3 Events/Woche ist nicht antippbar** (reiner Text, Zeilen
409–428). Es gibt keine Möglichkeit, die verdeckten Events einzusehen.
*Vorschlag:* antippbar machen → Liste/Bottom-Sheet mit allen Events der
betroffenen Woche bzw. des Tages (kombinierbar mit 2.1).

2.4 **Kein „Heute“-Button.** Navigation nur über Pfeile Monat-für-Monat
(`_Header`, Zeilen 449–505). Nach mehrmonatigem Vor-/Zurückblättern ist der Weg
zurück zum aktuellen Monat umständlich. *Vorschlag:* „Heute“-Chip neben dem
Monatsnamen.

2.5 **Nur eine Monatsansicht, keine Wochen-/Listenansicht.** Bei Flugschulbetrieb
mit mehreren Terminen pro Woche wirken die schmalen Balken im Monatsraster schnell
unübersichtlich (siehe auch 2.3). *Vorschlag:* Umschalter Monat/Agenda-Liste
ergänzen, insbesondere für die Admin-Seite.

2.6 **Event-Farben sind bedeutungslos.** `_EventBarStyle.from` (Zeilen 642–676)
wählt per Hash der Event-ID eine von 8 Pastellfarben – zufällig und ohne Bezug zu
Status, Rolle oder Planungsstufe. Das widerspricht der UX-Regel „Farbe muss
Bedeutung tragen“. *Vorschlag:* Einfärbung nach Event-Status (geplant/bestätigt/
abgesagt) oder Planungsstufe, plus kurze Legende im Kalender-Header.

2.7 **Offene Tauschanfragen sind im Kalenderbalken nicht erkennbar** – nur in der
Listenansicht „Events verwalten“ gibt es dafür ein Icon. Admins sehen
Tauschbedarf im Kalender nicht auf einen Blick. *Vorschlag:* kleines Tausch-Icon
im `_EventBar` ergänzen, wenn `event.team.any((t) => t.hasOpenSwapRequest)`.

2.8 **ICS-Abo-Icon (RSS-Symbol) und Verbindungsstatus-Icon stehen unmarkiert
nebeneinander** in der AppBar – zwei funktional komplett unterschiedliche Aktionen
ohne visuelle Trennung oder Beschriftung.

---

## 3. Navigation & Anordnung der Funktionen (hohe Priorität – explizit genannt)

**Dateien:** `lib/fsAdmin/features/manage_flight_school_view/manage_flight_school_view.dart`,
`lib/fsAdmin/features/main_scaffold/main_admin_scaffold_view.dart`,
`lib/user/features/main_scaffold/main_user_scaffold_view.dart`,
`lib/user/features/account/account_view.dart`

3.1 **„Flugschule verwalten“ zeigt 10 gleichrangige Menüpunkte untereinander ohne
jede Gruppierung** (live verifiziert: Stammdaten, Qualifikationen, Teamrollen,
Checklisten-Bibliothek, Qualifikationsprüfung, Saisonplanung & Stufen, Statistik,
Audit-Log, ICS-Feed, Admin-Nutzer). Klassisches „Schubladen“-Problem, schlecht
scannbar. *Vorschlag:* in 3–4 Abschnitte mit Zwischenüberschriften gruppieren, z. B.:
  - **Organisation:** Stammdaten & Logo, Admin-Nutzer verwalten, Teamrollen
  - **Qualität & Sicherheit:** Qualifikationen & Pflichtnachweise, Qualifikationsprüfung, Arbeitsanweisungen & Checklisten
  - **Planung & Auswertung:** Saisonplanung, Stufen & Tauschanfragen, Statistik & Einsätze
  - **Sonstiges:** Audit-Log, Kalender-Abo

3.2 **Beziehung zwischen „Events verwalten“ und „Saisonplanung & Stufen“ ist nicht
sichtbar**, obwohl die Planungsstufe direkten Einfluss darauf hat, was Mitglieder
von einem Event sehen (Stufe 1 = nur „Geplanter Zeitraum“). Der einzige Querverweis
ist der Banner „offene Tauschanfragen“ in `manage_events_view.dart` (Zeilen
178–203). *Vorschlag:* in „Events verwalten“ einen Status-Chip pro gefilterter
Saison anzeigen („Saison 2027 – Stufe 1: Verfügbarkeit“) mit Link zur
Stufen-Verwaltung.

3.3 **„In Admin-Modus wechseln“ ist als voller, primärer CTA-Button gestaltet**
(Konto-Tab) – optisch gleichrangig mit einem „Speichern“-Button, obwohl es sich um
einen Kontextwechsel handelt, der laut Testaccount-Setup ein Kernworkflow für
Personen mit Doppelrolle ist. *Vorschlag:* z. B. als Segmented-Control/Switch
„Nutzer ⇄ Admin“ permanent in der AppBar statt eine Ebene tiefer im Konto-Tab
versteckt.

3.4 **Tab-Auswahl geht beim Rollenwechsel verloren** – `MainAdminScaffoldView`
und `MainUserScaffoldView` starten beide immer bei `selectedIndex = 0`. Wer z. B.
kurz in den Nutzer-Modus wechselt und zurück zum Admin will, landet nicht mehr im
zuvor geöffneten Tab (z. B. „Events verwalten“ statt wieder im Kalender).
*Vorschlag:* letzten Tab-Index pro Rolle merken (z. B. in den jeweiligen Providern).

3.5 **Leere Zustände sind durchweg nur grauer Fließtext mittig auf sonst leerer
Fläche** (z. B. Start-Tab „Keine bestätigten Events gefunden.“, live verifiziert –
der Bildschirm bleibt dabei zu >80 % leer). *Vorschlag:* einheitliche
Empty-State-Komponente mit Icon, kurzem Erklärtext und ggf. Handlungs-Button (z. B.
„Zu „Anfragen & Offen“ wechseln“) für Home, Kalender, Aktuell, Events verwalten,
Personal verwalten, Verfügbarkeiten.

---

## 4. Cross-Cutting / Design-System (mittel – hoher Hebel für Konsistenz)

**Dateien:** `lib/core/theme.dart`, `lib/main.dart`, verstreut in Feature-Dateien

4.1 **Kein Dark Theme.** `AppTheme` definiert nur `lightTheme`; `MaterialApp` in
`main.dart` setzt kein `darkTheme`/`themeMode`. Auf Geräten mit System-Dunkelmodus
bleibt die App erzwungen hell bzw. verhält sich inkonsistent. *Vorschlag:*
zumindest ein einfaches `darkTheme` ergänzen und registrieren.

4.2 **Status-/Warnfarben sind an vielen Stellen als Rohwerte verstreut**
(`Colors.red`, `Colors.teal.withValues(...)`, `Colors.orange...` direkt im
Widget-Code, z. B. durchgängig in `event_upsert_view.dart` und
`manage_planning_periods_view.dart`) statt als benannte Theme-Farben. Funktional
unkritisch, aber relevant für Konsistenz, Wartbarkeit und einen künftigen
Dark-Mode. *Vorschlag:* in `AppTheme` semantische Farben ergänzen (z. B.
`successColor`, `warningColor`, `dangerColor`, `swapColor`) und referenzieren.

4.3 **Mischung aus Unicode-Emoji und Material-Icons als Statusindikator** (siehe
1.6) – uneinheitliche Icon-Sprache im selben Formular.

---

## 5. Kleinere, schnell umsetzbare Fixes

5.1 **Lange Datum/Zeit-Texte in Buttons** („Start: 20.11.2026 18:23“) können auf
schmalen Bildschirmen knapp werden. *Vorschlag:* zweizeiliges Layout (Datum über
Uhrzeit) oder kompakteres Format.

5.2 **Verbindungsstatus-Icon** (Sync/Check/Error) in der AppBar ist für
Erstnutzer nicht selbsterklärend – Bedeutung erscheint nur als Snackbar nach Tap.
*Vorschlag:* `tooltip:` durchgängig ergänzen (für Web-Hover) und ggf. kurz
beschrifteten Status statt reinem Icon verwenden.

5.3 **„Events verwalten“: Filterzeilen verbrauchen durchgehend ca. 180 px Höhe**
(Suche, Checkbox+Saison, Status+Zeitraum), bevor überhaupt eine Trefferliste
sichtbar wird – besonders ungünstig bei kurzen Listen. *Vorschlag:* Status/
Zeitraum/Saison-Filter in ein ausklappbares Panel verschieben (per Icon-Button
geöffnet); Suchfeld bleibt permanent sichtbar.

5.4 **Web-Layout bleibt immer auf schmale Mobile-Breite begrenzt**, unabhängig von
der tatsächlichen Browserfenstergröße (keine Breakpoints, reine
`BottomNavigationBar`-Struktur). Auf breiten Desktop-Fenstern bleibt die Fläche
rechts/links ungenutzt leer, besonders auffällig bei Kalender und leeren Listen.
*Vorschlag (ohne Funktionsänderung):* Kalender/Listen auf die volle verfügbare
Höhe strecken statt am Content-Ende abzuschneiden; eine echte Desktop-Navigation
(z. B. `NavigationRail` ab definierter Breite) als separate, spätere Ausbaustufe
vormerken.

---

---

# Runde 2 – Vertiefter Review nach Live-Test mit echten Daten

Durchgeführt mit echtem Durchklicken beider Rollen (Nutzer & Flugschul-Admin) im lokalen
Dev-Build, inkl. Anlegen eines echten Test-Events. Besonderer Fokus (Auftrag): **Konsistenz
der Bedienmuster** – wann öffnet sich ein neuer Screen vs. ein Popup, wann wird automatisch
gespeichert vs. über einen manuellen Button, und verhalten sich gleichartige
Kacheln/Buttons/Icons überall gleich?

## Was seit Runde 1 bereits umgesetzt wurde

Deutliche Verbesserungen seit dem ersten Review, u. a.:
- Kalender: „Heute“-Button, Monat/Agenda-Umschalter, Farblegende nach Status/Stufe statt
  Zufallsfarben, FAB „Neues Event“ auch im Kalender-Tab, Tippen auf einen leeren Tag öffnet
  jetzt „Neues Event“ vorausgefüllt mit diesem Datum (09:00–17:00).
- Nutzer-Kalender: Tippen auf einen Tag öffnet ein Bottom-Sheet „Verfügbar eintragen /
  Abwesend“ statt nichts zu tun.
- „Flugschule verwalten“: die 10 Menüpunkte sind jetzt in vier Abschnitte gruppiert
  (Organisation / Qualität & Sicherheit / Planung & Auswertung / Sonstiges) – genau wie in
  Runde 1 vorgeschlagen.
- Event-Erstellung: automatische Dauer-Anzeige („Dauer: 2 Std.“) mit „Dauer sperren“,
  „Als Event-Vorlage speichern“, Event duplizieren („Event kopieren“ inkl. Datum-Verschiebung
  und Team-Übernahme), neues Dashboard „FSA · Übersicht“ als erster Admin-Tab.
- Persönliche Daten / Stammdaten: einheitliches „Felder sind standardmäßig gesperrt – tippe
  auf das Stift-Symbol zum Bearbeiten“ mit dirty-state-abhängigem Speichern/Verwerfen.
- Mehrere Empty-States wurden auf Icon + Titel + Erklärtext umgestellt (siehe aber 2.4 unten
  für verbleibende Ausnahmen).

Das zeigt, dass Runde-1-Feedback sehr zielgerichtet umgesetzt wurde. Runde 2 fokussiert daher
auf neu entdeckte Probleme und verbleibende Inkonsistenzen.

## 1. Kritische Bugs (vor allem umsetzen)

**Datei:** `lib/fsAdmin/features/widgets/event_upsert_view.dart` (jetzt 2298 Zeilen, stark erweitert)

1.1 **Crash „A TextEditingController was used after being disposed“ beim „Als
Event-Vorlage speichern“-Dialog.** Reproduziert durch zweimaliges, schnelles Antippen des
Lesezeichen-Icons oben rechts im Event-Formular (bzw. allgemein: schnelles Doppeltippen auf
ein Element, das `_saveAsTemplateDialog()` auslöst, Zeilen 240–346). Ursache: `tplNameCtrl`
ist ein lokaler `TextEditingController` (Zeile 255), der nach Dialog-Schließen sofort
`dispose()`t wird (Zeile 312). Bei überlappendem Öffnen/Schließen (zwei Dialog-Instanzen durch
Doppeltipp) entsteht eine Race Condition: eine noch ausblendende `TextField`-Animation
referenziert den bereits disponierten Controller der ersten Instanz. Folge im Test: kompletter
Flutter-Fehlerbildschirm, anschließend wurde die ganze „Flugschule verwalten“-Navigation
mehrere Minuten lang unresponsive (nur noch Neuladen der Seite half). *Vorschlag:* Button/Icon
während des Öffnens des Dialogs deaktivieren (Doppel-Trigger verhindern, analog zu `_saving`-
Flags an anderen Stellen im selben File), und generell prüfen, ob lokale
`TextEditingController` in kurzlebigen Dialogen durch ein robusteres Pattern (z. B. Controller
im `State` statt lokal in der Methode) ersetzt werden sollten. Da die Admin-UI ohnehin spürbare
Klick-Verzögerungen hat (siehe Testhinweise), ist ungeduldiges Doppeltippen ein realistisches
Nutzerverhalten – dieser Bug ist kein Rand­fall.

1.2 **Datum-Auswahl im neuen Beginn/Ende-Dialog ließ sich im Test nicht zuverlässig per Tippen
auf einen Kalendertag oder auf die Schnellauswahl-Chips (08:00/09:00/… 18:00) ändern** – die
Kopfzeilen-Vorschau („21.11.2026 · 12:00 Uhr“) blieb unverändert und der Dialog schloss beim
nächsten Tippen ohne die Auswahl zu übernehmen. Nur die Stunde/Minute-Dropdowns
(`_pickDateTimeSheet`, Zeilen 806–959) haben zuverlässig funktioniert und wurden auch
tatsächlich gespeichert (im Test verifiziert: Event mit per Dropdown gesetzter Uhrzeit wurde
korrekt in der Datenbank angelegt). Der Code selbst (`CalendarDatePicker.onDateChanged` Zeile
848, `ChoiceChip.onSelected` Zeile 916) sieht korrekt aus, daher **bitte manuell
nachprüfen** statt blind zu "fixen" – möglicherweise ein reines Artefakt der
Test-Umgebung (Bottom-Sheet-Animation/Hit-Testing im Debug-Web-Build), möglicherweise aber
auch ein reales Problem mit der Tastierbarkeit der `CalendarDatePicker`-Zellen bzw. der
`ChoiceChip`s in der produktiven Build. Hohe Priorität zu klären, da das Ändern des
Start-/Enddatums eine Kernfunktion ist.

## 2. Konsistenz der Bedienmuster (Hauptfokus dieser Runde)

2.1 **Das 3-Punkte-/Overflow-Icon verhält sich auf jeder Listen-Ansicht anders:**
   - **Events verwalten** (`manage_events_view.dart`): Icon öffnet exakt denselben
     „Event bearbeiten“-Screen wie ein Tipp auf die restliche Zeile – das Icon ist rein
     dekorativ und suggeriert fälschlich ein Kontextmenü (Duplizieren/Löschen stehen tatsächlich
     nur *nach* dem Öffnen von „Event bearbeiten“ als AppBar-Icons zur Verfügung, nicht direkt
     aus der Liste).
   - **Personal verwalten → Team-Liste**: Weder das 3-Punkte-Icon noch die restliche Zeile
     reagieren auf Tippen – ein Teammitglied kann aus dieser Liste heraus gar nicht bearbeitet
     oder entfernt werden (im Test mehrfach verifiziert, auch Zeile selbst ist nicht klickbar).
   - **Teamrollen (Einsatzpositionen)**: identisches Bild – weder 3-Punkte-Icon noch Zeile
     öffnen irgendetwas; eine bestehende Rolle (z. B. „Kamera“) kann nicht bearbeitet werden,
     nur über „Neue Rolle“ lassen sich weitere hinzufügen.
   *Vorschlag:* Ein einheitliches Verhalten für alle Listen mit 3-Punkte-Icon festlegen (z. B.
   immer: Icon = Kontextmenü mit Bearbeiten/Duplizieren/Löschen; Zeile = Detail/Bearbeiten
   öffnen) und dort nachrüsten, wo aktuell gar keine Interaktion möglich ist (Personal,
   Teamrollen) – das ist aktuell eine echte Funktionslücke, kein reines Stilproblem.

2.2 **„Als Event-Vorlage speichern“ ist doppelt im selben Screen vorhanden**: einmal als
Lesezeichen-Icon oben rechts in der AppBar, einmal als eigene Karte mit „Speichern“-Button
mitten im Formular (Zeilen 1951–1975 etwa) – beide öffnen denselben Dialog. Zwei Zugänge zur
selben Aktion auf einem Bildschirm sind unnötig und beim ersten Blick nicht als „dasselbe“
erkennbar. *Vorschlag:* nur einen Zugang behalten (empfehlenswert: die Karte im Formular, weil
sie den Zweck erklärt; das AppBar-Icon entfernen oder stattdessen fürs *Laden* einer
bestehenden Vorlage nutzen, was aktuell über einen eigenen Button weiter unten im Formular
läuft und ebenfalls etwas versteckt ist).

2.3 **Rollenwechsel Nutzer ⇄ Admin ist doppelt vorhanden**: als Pille oben rechts in praktisch
jeder AppBar („Nutzer ⇄“ / „Admin ⇄“) *und* als voller, breiter Button unten auf dem
„Konto“-Screen bzw. „Zurück in den Nutzer-Modus“-Button unten auf „Flugschule verwalten“. Beide
lösen denselben Rollenwechsel aus. Das ist nicht falsch (gute Erreichbarkeit), aber
uneinheitlich in der visuellen Sprache: die AppBar-Pille wirkt wie ein sekundärer Status-Chip,
der große Button wirkt wie ein primärer Call-to-Action – für ein und dieselbe Aktion.
*Vorschlag:* Button-Variante entweder ganz entfernen (AppBar-Pille reicht, ist global
sichtbar) oder beide visuell als dieselbe Aktion erkennbar gestalten (gleiche Farbe/Icon).

2.4 **Empty-State-Gestaltung ist nicht überall angeglichen worden.** Die meisten Leerzustände
nutzen jetzt Icon + Titel + Erklärtext (z. B. „Keine offenen Beitrittsanfragen“, „Keine
offenen Admin-Aufgaben“, „Keine offenen Anfragen oder Stellen“) – sehr gut. Die
**„Qualifikationsprüfung“-Ansicht** zeigt bei leerem Zustand aber nach wie vor nur einfachen
grauen Fließtext „Keine offenen Nachweise zur Prüfung.“ ohne Icon/Titel. *Vorschlag:* dieselbe
Empty-State-Komponente auch hier verwenden (sofern eine gemeinsame Komponente existiert, sonst
jetzt extrahieren, um weitere Divergenz zu vermeiden).

2.5 **Zwei unterschiedliche „Feld entsperren“-Muster auf derselben Seite
(„Persönliche Daten“):** Vorname/Nachname/E-Mail/Telefon werden **einzeln** über ein
Stift-Icon pro Feld entsperrt; der „Notfallkontakt“-Block wird dagegen **als Ganzes** über
einen einzigen „Bearbeiten“/„Sperren“-Link oben rechts in der Karte entsperrt. Beide Muster
sind für sich funktional und gut umgesetzt, aber uneinheitlich innerhalb *eines* Screens –
ein Nutzer muss zweimal lernen, wie man ein Feld bearbeitet. *Vorschlag:* ein Muster für die
ganze Seite wählen (vermutlich eher „pro Feld“, da granularer) oder zumindest optisch klarer
trennen, warum der Notfallkontakt anders funktioniert (z. B. kurzer Hinweistext).

2.6 **Screen vs. Popup ist größtenteils konsistent, mit einer Ausnahme:** Beobachtetes Muster
in der App: komplexe, mehrfeldrige Objekte (Event, Flugschul-Stammdaten, Persönliche Daten)
öffnen einen vollen Screen mit eigenem „Speichern“/„Abbrechen“ unten; kurze, einzweckige
Eingaben (Teammitglied hinzufügen, Verfügbarkeit eintragen, neue Saison/Periode anlegen) öffnen
ein Dialog-/Bottom-Sheet-Popup mit „Abbrechen“/Aktion. Das ist ein sinnvolles, nachvollziehbares
Prinzip. Die Ausnahme: **Personal- und Teamrollen-Listen bieten für das Bearbeiten eines
bestehenden Eintrags weder Screen noch Popup an** (siehe 2.1) – das durchbricht das Prinzip,
weil Nutzer aus der Erfahrung mit Events erwarten, dass ein Tipp auf eine Zeile etwas öffnet.

2.7 **Bestätigungs-Dialog „Änderungen verwerfen?“ ist jetzt dirty-state-abhängig** (positiv!):
beim Schließen eines frisch geöffneten, unveränderten „Neues Event“-Formulars erschien im
aktuellen Test **keine** Nachfrage mehr – das wirkt wie eine Verbesserung gegenüber Runde 1.
Bitte dennoch stichprobenartig gegenprüfen, ob das bei allen Eintrittspunkten (auch „Event
kopieren“) konsistent so ist, da es in Runde 1 noch unconditional war.

## 3. Kalender – admin-spezifische Lücke

3.1 Die „+N weitere“-Anzeige bei vielen Events pro Woche wurde in diesem Durchlauf nicht erneut
mit genügend Testdaten geprüft (nur 1–2 Events pro Tag im Testbestand) – bitte mit einer Woche,
die mehr als 3 Events enthält, erneut verifizieren, ob das jetzt antippbar ist oder weiterhin
nur Text ist (Runde-1-Befund 2.3).

3.2 Die Kopfzeile des neuen Kalender-Legendenbereichs nimmt auf kleinen Bildschirmen spürbar
Platz ein, bevor der eigentliche Kalender beginnt (Monatsname, Heute/Monat/Agenda-Zeile,
Wochentage, Legende = 4 Zeilen Overhead). Das ist ein akzeptabler Kompromiss für die neu
gewonnene Funktionalität, aber auf sehr kleinen Displays ggf. die Legende einklappbar machen.

## 4. Kleinere Beobachtungen

4.1 Der neue Beginn/Ende-Dialog verwendet in der `CalendarDatePicker`-Kopfzeile **einbuchstabige
Wochentags-Kürzel** („M D M D F S S“ – Montag/Mittwoch beide „M“, Dienstag/Donnerstag beide
„D“), während der Hauptkalender (`calender_widget.dart`) zweibuchstabige, eindeutige Kürzel
verwendet („Mo Di Mi Do Fr Sa So“). Das ist zum einen uneinheitlich, zum anderen für die
einbuchstabige Variante tatsächlich mehrdeutig. *Vorschlag:* im `CalendarDatePicker`, sofern
konfigurierbar, oder per eigener Wochentagszeile die zweibuchstabigen Kürzel erzwingen.

4.2 Im Team-Mitglied-Dropdown des Admin-Personal-Bereichs werden Notfallkontakt-Telefonnummern
direkt und ungeschützt in der Listenübersicht angezeigt (rot hervorgehoben). Das ist für den
Sicherheitszweck nachvollziehbar, aber es gibt keine Möglichkeit, diese sensible
Drittperson-Information auszublenden/zu verbergen, falls der Bildschirm z. B. in einem
öffentlichen Raum sichtbar ist. Kein Muss, aber als Datenschutz-Fingerzeig erwähnenswert.

4.3 „Event kopieren“ verschiebt Start/Ende-Datum automatisch (im Test: Original 01.–05.12.2026
→ Kopie 08.–12.12.2026, exakt +7 Tage). Das ist eine sinnvolle Annahme (nächste Woche), sollte
aber irgendwo kurz kommuniziert werden (z. B. Hinweistext „Datum wurde auf nächste Woche
vorverlegt – bitte anpassen“), da es sonst leicht übersehen wird und ein Admin versehentlich
ein Duplikat mit falschem Datum speichert.

## Testhinweise Runde 2

- Getestet mit echtem Event „UX-Testevent Claude“ (21.11.2026, 15:00–17:00, Flugschule
  Achensee), das während des Tests real angelegt wurde und in der Datenbank verbleibt (laut
  Auftrag unkritisch, da Testinstanz).
- Im Admin-Bereich traten wiederholt Fälle auf, in denen ein Tippen erst beim zweiten Versuch
  sichtbar reagierte (betraf Tab-Wechsel, Dialog-Öffnungen, Formularfelder). Nach dem unter 1.1
  beschriebenen Crash kam es zudem zu einer länger anhaltenden Phase, in der Navigation
  innerhalb von „Flugschule verwalten“ gar nicht mehr reagierte, bis die Seite neu geladen
  wurde. Ob das ein reines Debug-Web-Build-Artefakt ist oder (zumindest teilweise) ein reales
  Performance-/Zustands-Problem der Produktion, konnte nicht abschließend geklärt werden – beim
  nächsten Review auf einem Release-Build gegenprüfen.

## Hinweise für den Agenten / offene Fragen
- Priorität 1 und 2 (Event-Erstellung, Kalender) sind laut Auftrag der Schwerpunkt –
  hier zuerst ansetzen, insbesondere **1.2 (Lokalisierung)** als Quick-Win mit dem
  größten Verhältnis von Aufwand zu Nutzen.
- Alle Vorschläge sind rein UI/UX-seitig gedacht; keiner erfordert eine Änderung an
  Datenmodell, Appwrite-Schema oder Business-Logik.
- Getestet wurde mit einem leeren Testaccount (keine Events/Verfügbarkeiten) gegen
  das produktive Backend – Punkte zu dichten Kalenderansichten (2.3, 2.5, 2.6, 2.7)
  bitte vor Umsetzung nochmal mit echten Beispieldaten gegenprüfen.
- Im lokalen Debug-Web-Build reagierte die UI nach Seitenwechseln gelegentlich erst
  beim zweiten Klick (vermutlich DWDS/Debug-Artefakt) – falls das auch im
  Release-Build auftritt, separat untersuchen; keine der obigen UX-Vorschläge hängt
  davon ab.
