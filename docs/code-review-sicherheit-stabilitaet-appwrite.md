# Code-Review – Sicherheit, Stabilität & effiziente Appwrite-Nutzung

Reiner Code-Review (keine UI/UX-Themen – siehe dazu `ux-verbesserungen-season-planner.md`).
Erstellt für einen Umsetzungs-Agenten. Jeder Befund nennt Datei(en)/Zeilen, das Problem, die
Relevanz und einen konkreten Lösungsvorschlag.

## Methodik

- Vollständige Analyse der kompletten Appwrite-Service-Schicht: `lib/user/services/database_service.dart`
  (1294 Zeilen), `lib/fsAdmin/services/flight_school_service.dart` (743) +
  `flight_school_functions.dart` (64) + `flight_school_provider.dart` (157),
  `lib/core/services/qualification_service.dart` (788), `role_document_service.dart` (659),
  `planning_service.dart` (375), `event_template_service.dart` (111), `audit_log_service.dart`
  (65), `inventory_todo_service.dart` (269), `lib/user/user_provider.dart` (40),
  `lib/core/services/auth_service.dart` (279), `lib/core/services/realtime_service.dart` (78).
- Ergänzend: `appwrite_config.dart`, `pubspec.yaml`, die einzige Appwrite Function
  (`appwrite_functions/ics_feed`), sowie projektweite Grep-Analyse (Permission-/Role-Nutzung,
  Query.limit/offset-Nutzung, leere catch-Blöcke, Query.select/Relationship-Nutzung).
- **Wichtige Einschränkung:** Appwrite-Collection-/Row-Permissions, Indizes und
  Relationship-Definitionen selbst werden in der Appwrite-Konsole konfiguriert und sind in
  diesem Repository **nicht einsehbar**. Viele Sicherheitsbefunde unten lauten deshalb korrekt
  „hängt vollständig von der Konsolen-Konfiguration ab, die hier nicht geprüft werden kann“ –
  das ist kein Freispruch, sondern genau der Punkt: der Code selbst bietet keine zweite,
  unabhängige Absicherung, falls die Konsolen-Konfiguration zu großzügig ist oder sich mal
  ändert.

---

## Zusammenfassung – die 3 wichtigsten systemischen Themen

1. **Autorisierung läuft fast ausschließlich client-seitig.** In der gesamten `lib/`-Codebase
   wird kein einziges Mal `Permission.` oder `Role.` beim Erstellen/Ändern einer Row übergeben
   (0 Treffer). Es gibt nur eine einzige Appwrite Function (`ics_feed`, rein lesend). Jede
   privilegierte Aktion – Qualifikation freigeben, Admin hinzufügen, Planungsstufe wechseln,
   Tausch final bestätigen, Abo-gesperrte Funktionen – ist im Code ein ganz normaler
   `updateRow`/`createRow`-Aufruf mit der Session des eingeloggten Nutzers, ohne jede
   Rollenprüfung im Dart-Code. Ob das sicher ist, hängt zu 100 % von Appwrite-Collection-
   Permissions ab, die dieses Repo nicht zeigt.
2. **Appwrite-Relationships werden an einigen Stellen vorbildlich genutzt, an den meisten
   anderen aber ignoriert**, obwohl dieselbe Beziehung (z. B. `events` ↔
   `team_assignments_events`) im Projekt nachweislich schon als native Relationship existiert
   (siehe `appwrite_functions/ics_feed/src/main.js:127`: `Query.select(['*', 'events.*'])`).
   Das Ergebnis ist ein massives N+1-Problem: `flight_school_service.dart` lädt für jede
   Flugschule bis zu **201 einzelne Requests** (1 pro Event), wo eine erweiterte
   `Query.select` vermutlich 1 Request bräuchte.
3. **Feste `Query.limit`-Werte (100–500) ohne jede Pagination.** Es wird nirgends
   `Query.offset`/`Query.cursorAfter` verwendet. Bei wachsenden Datenmengen (mehrjährige
   Flugschul-Historie, Audit-Log, Checklisten-Completions) werden ältere Einträge irgendwann
   kommentarlos nicht mehr geladen – stiller Datenverlust statt Fehler.

---

## 1. Sicherheit

### 1.1 Privilegierte Mutationen ohne serverseitige Rollenprüfung (übergreifend, höchste Priorität)

Durchgängiges Muster im gesamten Projekt – der Dart-Code prüft zwar oft in der UI, ob der
aktuelle Nutzer Admin ist, die eigentliche Appwrite-Mutation selbst tut das nie:

- `database_service.dart:460-495` (`changeEventAssignmentStatus`) – jeder beliebige Status
  (auch `accepted_flight_school`, eigentlich Admin-only) kann gesetzt werden.
- `flight_school_service.dart:147-171` (`updateAdmins`) – Admin-Liste einer Flugschule wird
  direkt per `updateRow` geschrieben.
- `qualification_service.dart:209-273, 632-664` (`approveQualificationRequest`,
  `rejectQualificationRequest`, `reviewApproval`) – Freigabe-Entscheidungen ohne Prüfung.
- `planning_service.dart:83-106` (`updatePeriodStage`) – Wechsel der Planungsstufe (steuert,
  was Mitglieder überhaupt sehen dürfen).
- `planning_service.dart:312-345` (`approveSwap`) – finale Zuweisung eines Tauschplatzes;
  dieselbe Row muss aber auch von normalen Mitgliedern beschreibbar sein (für
  `swap_offered`/`swap_requested_by`), wodurch Appwrite ohne Function nicht zwischen „Tausch
  anbieten“ (Mitglied) und „Tausch final bestätigen“ (Admin) unterscheiden kann.

**Warum relevant:** Ein technisch versierter Nutzer kann mit der eigenen, gültigen Session
direkt gegen die Appwrite-REST-API aufrufen (Endpoint + Projekt-ID sind ohnehin öffentlich) und
so – falls die Collection-Permissions das zulassen – Admin-Aktionen ausführen, fremde
Qualifikationen freigeben oder sich selbst einen Tauschplatz zuweisen, komplett ohne die
Flutter-UI zu benutzen.

**Vorschlag:** Für die wirklich kritischen Mutationen (Admin-Verwaltung, Qualifikationsfreigabe,
Tausch-Finalisierung, Planungsstufe) jeweils eine Appwrite Function einführen, die mit
API-Key läuft und die Rolle des aufrufenden Nutzers (`req.headers['x-appwrite-user-id']`)
serverseitig gegen die `memberships`/`team_roles`-Tabelle prüft, bevor sie schreibt – nach
demselben Muster wie die bereits vorhandene `ics_feed`-Function. Zusätzlich: Row-Permissions
beim Erstellen dieser sensiblen Rows explizit setzen (`Permission.update(Role.team(fsId,
'admin'))` o. ä.) statt sich allein auf Collection-Defaults zu verlassen.

### 1.2 Abo-/Subscription-Sperre ist rein client-seitig

`lib/fsAdmin/features/widgets/subscription_locked_view.dart:29` (`SubscriptionGate`) blendet
gesperrte Admin-Bereiche nur in der Flutter-UI aus, wenn `fs.isSubscriptionActive == false`.
Dieselbe Prüfung wiederholt sich in `flight_school_service.dart:433-448`
(`_assertSubscriptionActive`, wirft lediglich eine clientseitig gefangene Exception) und in
`database_service.dart:945, 1067, 1220`. **Keine dieser Prüfungen verhindert**, dass derselbe
`updateRow`/`createRow`-Aufruf direkt per API ohne aktives Abo ausgeführt wird.

**Warum relevant:** Das ist nicht nur ein Datenschutz-, sondern ein **Umsatzrisiko** – ein
Nutzer mit abgelaufenem/ausstehendem Abo kann technisch weiterhin kostenpflichtige Funktionen
nutzen, solange er die App umgeht.

**Vorschlag:** Abo-Pflicht zusätzlich serverseitig erzwingen – entweder über eine Function, die
vor jeder kostenpflichtigen Mutation den `subscription_status` prüft, oder (eleganter, falls
Appwrite das für Tables unterstützt) über eine Attribut-basierte Permission-Regel.

### 1.3 Audit-Log ist nicht manipulationssicher

`audit_log_service.dart:18-42` (`log`) wird von `planning_service.dart` und
`event_template_service.dart` als **zweiter, unabhängiger Client-Call direkt nach** der
eigentlichen Mutation aufgerufen – nicht serverseitig (Trigger/Function) erzeugt. Der optionale
`userId`-Parameter (Zeile 22/25) erlaubt zudem theoretisch, einen fremden Nutzer als
Log-Urheber unterzuschieben.

**Warum relevant:** Die App bewirbt das Audit-Log explizit als „Nachvollziehbare Historie aller
Änderungen“ (UI-Text). Ein Client, der die eigentliche Mutation per direktem API-Call macht und
den zweiten Log-Call einfach weglässt, hinterlässt gar keine Spur – das Feature hält dem
eigenen Versprechen nicht stand, sobald jemand die App umgeht.

**Vorschlag:** Audit-Einträge serverseitig erzeugen (Appwrite-Function, die auf Änderungen der
relevanten Tabellen reagiert, oder zumindest alle sicherheitsrelevanten Mutationen selbst über
eine Function laufen lassen, die am Ende auch loggt). `audit_logs` sollte für normale Nutzer nur
Lese-, keine Schreibrechte haben.

### 1.4 Datei-Uploads: keine Datei-Permissions, unsignierte Dauer-URLs für sensible Dokumente

- `qualification_service.dart:451`, `role_document_service.dart:206`,
  `role_document_service.dart:552` – alle drei `_storage.createFile(...)`-Aufrufe (Lizenz-/
  Gesundheitsnachweise, Markdown-Bilder, Checklisten-Unterschriften) übergeben **keine**
  datei-individuellen `permissions`. Zugriff hängt komplett von Bucket-weiten
  Konsolen-Einstellungen ab.
- `appwrite_config.dart:65-71` (`fileViewUrl`/`fileDownloadUrl`), genutzt u. a. in
  `role_document_service.dart:212` – die erzeugten URLs enthalten nur `?project=`, **keine
  Signatur, keine Ablaufzeit**. Wer eine solche URL kennt (Browser-Cache, DevTools, geteilter
  Screenshot-Link), kann sie erneut aufrufen, solange Session/Bucket-Permission das zulassen.

**Warum relevant:** Hier geht es um Gesundheits-/Lizenznachweise (z. B. „Ärztliche
Tauglichkeit“) und persönliche Unterschriften – sensible personenbezogene Daten. Ohne
dateispezifische Permissions kann jeder mit Lesezugriff auf den Bucket theoretisch auch fremde
Dokumente einsehen, nicht nur die eigenen oder die der eigenen Flugschule.

**Vorschlag:** Beim Upload explizit `permissions: [Permission.read(Role.user(userId)),
Permission.read(Role.team(flightSchoolTeamId, 'admin'))]` setzen. Für Downloads zeitlich
begrenzte, signierte URLs verwenden (Appwrite unterstützt das für Storage-Dateien) statt der
rohen, dauerhaft gültigen View/Download-URL.

### 1.5 Keine Validierung von Dateityp/-größe vor Upload

`qualification_service.dart:439-486` (`uploadDocument`) prüft weder erlaubte Formate (z. B. nur
PDF/JPG/PNG) noch eine Maximalgröße, bevor hochgeladen wird. **Vorschlag:** Validierung vor
`_storage.createFile` ergänzen (clientseitig als UX-Schutz, serverseitig/Bucket-Konfiguration
als eigentliche Durchsetzung).

### 1.6 User-Enumeration über `inviteMember`

`flight_school_service.dart:659-711` – unterschiedliches Verhalten je nachdem, ob die
eingeladene E-Mail bereits ein Tragegurt-Konto hat oder nicht, erlaubt jedem Flugschul-Admin,
beliebige E-Mail-Adressen daraufhin zu prüfen, ob ein Konto existiert. **Vorschlag:**
einheitliche, nichtssagende Erfolgsmeldung unabhängig vom internen Pfad zurückgeben.

### 1.7 Platztausch: Identität des Anfragenden wird nur behauptet, nicht geprüft

`planning_service.dart:264-310` (`setSwapOffered`, `requestSwapTakeover`) – `requesterUserId`/
`requesterName` kommen als einfache Parameter vom Client; nichts verifiziert, dass das wirklich
der eingeloggte Nutzer ist. **Vorschlag:** `requesterUserId` serverseitig aus der Session
ableiten (Function), nicht vom Client übernehmen.

### 1.8 „Planungsstufe 1“-Datenschutz ist nur UI-Filterung, nicht Datenfilterung

`database_service.dart:507-519` (`loadUserEvents`) holt via `Query.select(['*','events.*'])`
das **volle** Event-Dokument (inkl. `location`, `notes`, `identifier`) für alle Zuweisungen,
unabhängig von der Planungsstufe. Erst danach (Zeilen 661-681) entscheidet Dart-Code, ob diese
Felder im UI-Modell ankommen. Die kompletten Rohdaten sind aber bereits über das Netz beim
Client – über Browser-DevTools/Netzwerk-Tab einsehbar, auch für Events, die laut Fachlogik noch
„Stufe 1: nur Zeitraum“ zeigen sollen.

**Vorschlag:** Sensible Felder für Stufe-1-Fälle serverseitig ausblenden (gezieltes
`Query.select` ohne `location`/`notes`, oder eine Function/View, die stufenabhängig filtert),
statt nur im Flutter-Modell zu filtern.

### 1.9 Potenzieller Stored-XSS über Markdown-Import

`role_document_service.dart:97-280` (`importMarkdownBundle`), insbesondere die
`htmlImgRegex`-Verarbeitung (Zeilen 250-263) lässt rohe `<img src=...>`-Tags unverändert im
gespeicherten `content_md` stehen, ohne weitere HTML-Konstrukte zu sanitisieren. **Vorschlag:**
Prüfen, ob `flutter_markdown_plus` HTML-Rendering zulässt (Web-Build!) – falls ja, Inhalte vor
dem Speichern sanitisieren oder HTML-Rendering in der Markdown-Konfiguration deaktivieren.

### 1.10 Kleinere Sicherheits-Fundstücke

- `flight_school_functions.dart:13` – `print()` statt `debugPrint`/Logger; loggt die
  Flugschul-ID auch in Release-Builds unkontrolliert mit. Entfernen oder durch strukturiertes
  Logging ersetzen.
- `appwrite_functions/ics_feed/src/main.js:77, 112` – Token-Vergleich (`school.ics_token !==
  token`) ist ein einfacher String-Vergleich, nicht timing-safe. Bei einem öffentlich
  erreichbaren Endpoint theoretisch anfällig für Timing-Angriffe auf den Token; angesichts des
  Risikoprofils (Kalender-Abo-Link) niedrige Priorität, aber mit konstante-Zeit-Vergleich
  (`crypto.timingSafeEqual`) leicht zu härten.

---

## 2. Stabilität

### 2.1 Ein einzelner korrupter Datensatz kann die gesamte Flugschule leerräumen

`flight_school_service.dart:344-425` – der komplette Lade-Loop über alle Events einer
Flugschule steht in einem einzigen try/catch (422-425). Wirft `DateTime.parse` (383/384) bei
nur **einem** beschädigten/unvollständigen Event-Dokument eine Exception, wird `events` für die
**gesamte** Flugschule auf `[]` zurückgesetzt – alle Nutzer sehen plötzlich einen leeren
Kalender, ohne Fehlermeldung. `getFlightSchool` selbst (175-241) gibt bei jedem Teilfehler
(Qualifikationen/Rollen/Perioden/Mitglieder/Events) komplett `null` zurück statt granular zu
degradieren.

**Vorschlag:** Pro Event einzeln fangen (einzelnes Event überspringen + loggen statt ganzen
Batch verwerfen); `getFlightSchool` so umbauen, dass ein Teilfehler nicht den kompletten
Ladevorgang zunichtemacht.

### 2.2 Uneinheitliche Fehlerbehandlung über die gesamte Service-Schicht

Durchgängig beobachtet in praktisch allen untersuchten Dateien: manche Methoden fangen Fehler
und geben `null`/`false`/`[]` zurück (z. B. fast alle Methoden in `qualification_service.dart`,
`acceptMembership`/`leaveMembership` in `database_service.dart`), andere werfen ungefangen
(`updateEventWithTeam` in `database_service.dart:1061-1211`, `createDocument`/`updateDocument`
in `role_document_service.dart:282-358`). Aufrufer können sich auf kein einheitliches Verhalten
verlassen, und „kein Ergebnis gefunden“ ist von „Request fehlgeschlagen“ nicht unterscheidbar –
das führt in der UI potenziell zu falschen Empty-States statt Fehlermeldungen.

**Vorschlag:** Eine verbindliche Konvention für die ganze Service-Schicht festlegen (empfohlen:
immer werfen, zentrales Error-Handling/Snackbar im UI-Layer) und schrittweise durchziehen.

### 2.3 Kein Rollback/keine Kompensation bei Teilausfällen

- `database_service.dart:1226-1259` (`deleteEventWithTeam`) – Team-Zuweisungen werden einzeln
  in einer Schleife gelöscht, **danach** erst das Event. Schlägt das Event-Löschen fehl, bleibt
  ein inkonsistenter Zwischenzustand (Event existiert noch, Team weg) ohne erkennbares Signal.
- `database_service.dart:1003-1059` (`createEventSeries`) – erzeugt bis zu `count` Events
  sequentiell; schlägt z. B. Event 5 von 12 fehl, bleiben 4 bereits angelegte Events ohne
  Rollback stehen, Nutzer sieht nur eine allgemeine Fehlermeldung.
- `qualification_service.dart:439-486`, `role_document_service.dart:206-215, 552-599` – wenn
  `_storage.createFile` erfolgreich ist, der nachfolgende `createRow`/`updateRow` aber scheitert,
  bleibt eine verwaiste Datei ohne DB-Referenz im Bucket zurück.

**Vorschlag:** Für jeden Fall entweder echten Rollback einbauen oder dem Nutzer explizit
mitteilen, was bereits erfolgreich war („4 von 12 Events angelegt, danach abgebrochen“), statt
eines generischen Fehlers.

### 2.4 Race Conditions / verworfene Reload-Anfragen

`flight_school_provider.dart:146-156` (`reloadFlightSchoolInBackground`) – `if (_isReloading)
return;` lässt einen während eines laufenden Reloads angestoßenen weiteren Reload-Wunsch
komplett verfallen, statt ihn danach nachzuholen. Nach schnell aufeinanderfolgenden Admin-
Aktionen kann der UI-Zustand dadurch veraltet bleiben, bis zufällig der nächste 60-Sekunden-
Timer oder ein Realtime-Event greift. **Vorschlag:** „Pending reload“-Flag setzen und nach
Abschluss des aktuellen Reloads automatisch einen weiteren anstoßen.

### 2.5 Force-Unwrap ohne Null-Guard

`user_provider.dart:20-22` (`userFlightSchools`-Getter) – `_user!.flightSchools` wirft eine
Laufzeit-Exception, wenn der Getter aufgerufen wird während `_user == null` ist (z. B. kurz
nach Logout/vor Login), inkonsistent zu `updateEvents` in derselben Klasse (34-38), das korrekt
auf `null` prüft. **Vorschlag:** Analogen Null-Guard ergänzen.

### 2.6 Fragile Heuristiken statt strukturierter Daten

`inventory_todo_service.dart:89-95` (`_isRepackCategory`) – ob ein Inventar-Gegenstand als
„Neupacken fällig“ gilt, wird über Substring-Suche im Kategorie-/Artikelnamen entschieden
(`'retter'`, `'rettung'`, `'reserve'`, `'pack'`). Eine Umbenennung der Kategorie in der separaten
Inventar-App ändert die Klassifizierung im Season Planner still und ohne Fehler. **Vorschlag:**
explizites Typ-/Kategorie-Flag in `inventory_db` nutzen statt Namens-Heuristik.

### 2.7 Harte, ungetypte Kopplung an das Schema einer anderen App

`inventory_todo_service.dart` liest direkt aus der Datenbank der separat entwickelten
Inventar-Manager-App (`inventory_db`) über rohe Feldnamen-Strings (`schoolId`, `itemId`,
`categoryId`, `isLocked`, `nextServiceDate`, Status wie `'disposed'`) in camelCase – abweichend
von der sonst im Season Planner verwendeten snake_case-Konvention. Ändert sich das Schema der
Inventar-App, bricht dieser Code still (falsche/fehlende Zähler), ohne dass Compiler oder Tests
das auffangen. **Vorschlag:** gemeinsame Konstanten/Enums für geteilte Feldnamen/Status-Werte
auslagern oder zumindest zentral dokumentieren.

### 2.8 Bereits bekannt aus dem UX-Review

Der dort dokumentierte Absturz „`TextEditingController was used after being disposed`“ (siehe
`ux-verbesserungen-season-planner.md`, Runde 2, Punkt 1.1) ist technisch gesehen ebenfalls ein
Stabilitätsbefund dieses Reviews: fehlender Schutz gegen doppeltes Öffnen von
`_saveAsTemplateDialog()` in `event_upsert_view.dart`. Wird hier nicht erneut im Detail
ausgeführt, sollte aber in derselben Umsetzungsrunde behoben werden.

---

## 3. Effiziente Nutzung der Appwrite-Datenbank(en)

### 3.1 Relationships: vorhanden, aber inkonsequent genutzt

Positiv: Das Projekt nutzt Appwrite-Relationship-Attribute bereits an mehreren Stellen correct,
u. a.:
- `database_service.dart:117` – `Query.select(['*', 'flightSchools.*'])`
- `database_service.dart:517` – `Query.select(['*', 'events.*'])`
- `database_service.dart:827` – verschachtelt: `memberships.*`, `memberships.flightSchools.*`
- `flight_school_service.dart:255` – `Query.select(['*', 'users.*'])`
- `appwrite_functions/ics_feed/src/main.js:127` – `Query.select(['*', 'events.*'])` auf
  `team_assignments_events`

Dieselbe oder eine vergleichbare Beziehung wird an anderer Stelle **nicht** genutzt, obwohl sie
sich anbieten würde:
- `flight_school_service.dart:357-371` (siehe 3.2) – Events ↔ Team-Zuweisungen erneut, aber
  diesmal manuell statt über die nachweislich existierende Relationship.
- `qualification_service.dart` (`checkQualification`, 732-787) – `qualification_approvals.
  document_id` → `qualification_documents` nur als String-ID mit manuellem clientseitigem
  Abgleich.
- `role_document_service.dart` – `team_roles.checklist_id`/`instruction_ids` →
  `role_documents` ebenfalls nur als String-IDs.
- `planning_service.dart` (`deletePeriod`, 143-161) – `planning_period_id` in `events` und
  `availability_submissions` als reiner String-FK ohne erkennbare Relationship/Cascade.
- `inventory_todo_service.dart` – `items.categoryId → categories`,
  `transactions.itemId → items` komplett manuell im Dart-Code aufgelöst.
- `qualification_service.dart` – `requested_qualifications`/`qualifications` als einfache
  Array-Felder auf `memberships` statt einer normalisierten M:N-Relationship-Tabelle; Fragen wie
  „wer hat Qualifikation X“ erfordern das Laden *aller* Memberships und clientseitiges Filtern.

**Vorschlag:** Einheitlich entscheiden, welche Beziehungen als native Appwrite-Relationships
modelliert werden sollen (vermutlich alle „echten“ 1:n/n:m-Fachbeziehungen), und dann
konsequent per `Query.select` nutzen statt manueller ID-Joins. Das reduziert gleichzeitig das
N+1-Problem (3.2) und ermöglicht serverseitige Cascade-Regeln (3.7).

### 3.2 N+1-Query-Muster (teils gravierend)

- **`flight_school_service.dart:357-371`** – für **jedes** Event (bis zu 200, Zeile 351) wird
  einzeln und sequenziell `tablesDB.listRows` für `team_assignments_events` aufgerufen → **bis
  zu 201 Appwrite-Requests für eine einzige `getFlightSchool`-Ladung.** Höchste Priorität, da
  dies bei jedem Admin-Login und nach jeder Einzeländerung (siehe 3.5) erneut passiert.
- `database_service.dart:692-717` (`loadUserEvents`) – pro Event eine zusätzliche Query, um die
  übrigen Team-Mitglieder desselben Events zu laden, obwohl die Haupt-Query bereits eine
  Relationship nutzt (517).
- `role_document_service.dart:83-92` (`getDocumentsByIds`) – ein `getRow`-Call pro ID in einer
  Schleife statt eines `listRows` mit `Query.equal('$id', [ids])` (Appwrite unterstützt Listen
  bei `equal`).

**Vorschlag:** Für den gravierendsten Fall (Events ↔ Team-Zuweisungen) entweder die
Events-Query um die vorhandene Relationship erweitern, oder minimal-invasiv `team_assignments_
events` **einmal** mit `Query.equal('events', <Liste aller Event-IDs>)` statt pro Event
abzufragen. Für `getDocumentsByIds` dasselbe Prinzip (ein `listRows` mit ID-Liste statt N
Einzelabfragen).

### 3.3 Keine Pagination über die erste Seite hinaus

Projektweit bestätigt (u. a. `audit_log_service.dart:56` Default-Limit 100,
`qualification_service.dart:427/580/601` Limit 200, `role_document_service.dart:471` Limit
500, `planning_service.dart:198` Limit 500, `flight_school_service.dart:351` Limit 200,
`inventory_todo_service.dart:120` Limit 500 für Inventar-Artikel) – nirgends wird
`Query.offset`/`Query.cursorAfter` genutzt, um eine zweite Seite nachzuladen. Bei
langlebigen Flugschulen (mehrere Saisons, viele Mitglieder/Checklisten-Completions/Audit-
Einträge) werden ältere/überzählige Datensätze irgendwann **kommentarlos nicht mehr geladen** –
das betrifft insbesondere `audit_logs` (wächst strukturell unbegrenzt) und
`checklist_completions` (eine pro Event-Teilnahme).

**Vorschlag:** Für mindestens `audit_logs`, `checklist_completions` und `inventory_items`
Cursor-Pagination einführen (nachladen „weitere anzeigen“ oder vollständig paginiert laden);
für die übrigen Limits zumindest bewusst dokumentieren und mit Monitoring versehen, ab wann sie
in der Praxis greifen könnten.

### 3.4 Sequentielle statt parallele unabhängige Queries

- `database_service.dart:853-905` (`getUserInformation`) – pro Mitgliedschaft werden
  `listTeamRoles`, `listQualifications`, `listPeriods` nacheinander per `await` aufgerufen
  (861-864) statt mit `Future.wait`; bei 2+ Flugschulen summiert sich unnötig Latenz.
- `qualification_service.dart:732-736` (`checkQualification`) – `listUserDocuments` und
  `listUserApprovals` nacheinander statt parallel, obwohl unabhängig voneinander – relevant, da
  diese Funktion pro Team-Zuweisung aufgerufen wird.

Positives Gegenbeispiel als Vorbild: `inventory_todo_service.dart:106-134` nutzt bereits
`Future.wait([...])` für drei parallele Queries.

**Vorschlag:** Die beiden oben genannten Stellen nach demselben Muster wie
`inventory_todo_service.dart` umbauen; bei Gelegenheit die übrige Service-Schicht auf weitere
sequentielle-aber-unabhängige `await`-Ketten durchsuchen.

### 3.5 Voller Reload nach jeder kleinsten Änderung

`flight_school_provider.dart:83-104` – `upsertEvent`/`upsertMember`/`removeEventById` etc. lösen
standardmäßig `reloadFlightSchoolInBackground()` aus, was den unter 3.2 beschriebenen
N+1-Ladevorgang für die **komplette** Flugschule erneut durchläuft – für die Statusänderung
eines einzelnen Events wird aktuell jedes Mal alles neu geladen (alle Events + alle
Team-Zuweisungen). In Kombination mit 3.2 besonders gravierend.

**Vorschlag:** Nach Beheben von 3.2 bleibt dieser Punkt relevant – gezieltere Teil-Updates
(optimistisches lokales Update + gezielte Einzel-Nachlade statt globalem Reload) statt
„Admin ändert eine Kleinigkeit → komplette Flugschule neu laden“.

### 3.6 `Query.select` teils breiter als nötig

`flight_school_service.dart:250-258` (`Query.select(['*', 'users.*'])`) holt für die reine
Mitgliederliste auch z. B. `emergency_contact_*`-Felder jedes Nutzers mit, unabhängig davon, ob
der aufrufende Screen sie braucht. **Vorschlag:** `Query.select` dort granularer auf die
tatsächlich benötigten Felder einschränken, wo die volle Row nicht gebraucht wird.

### 3.7 Fehlende serverseitige Kaskaden-Regeln

Da Beziehungen überwiegend als reine String-IDs statt Appwrite-Relationships mit
`onDelete`-Verhalten (`cascade`/`restrict`/`setNull`) modelliert sind, muss Aufräumen beim
Löschen manuell im Client nachgebaut werden – mit den unter 2.3 genannten
Teilausfall-Risiken, und an mindestens einer Stelle gar nicht:
`planning_service.dart:143-161` (`deletePeriod`) hinterlässt verwaiste `planning_period_id`-
Referenzen in `events`/`availability_submissions` ohne Warnung oder Bereinigung.

**Vorschlag:** Für `planning_period_id` und die Event↔Team-Beziehung prüfen, ob eine echte
Appwrite-Relationship mit serverseitigem `onDelete: restrict` (verhindert Löschen einer Periode
mit noch zugeordneten Events) bzw. `cascade` (räumt Team-Zuweisungen beim Event-Löschen
automatisch auf) die manuelle Lösch-Logik und ihre Fehlerfälle komplett eliminieren würde.

### 3.8 Realtime- und Polling-Architektur

`realtime_service.dart:23-77` (`subscribeToSeasonPlanner`) abonniert **11 Tabellen-Kanäle
global** (`Channel.tablesdb(db).table(id).row()`), nicht auf die jeweils relevante Flugschule
eingeschränkt – jede Änderung in jeder Zeile jeder dieser Tabellen löst (nach 600 ms
Entprellung) bei **jedem verbundenen Client** denselben vollständigen Reload (siehe 3.5) aus,
unabhängig davon, ob die Änderung die eigene(n) Flugschule(n) überhaupt betrifft. Zusätzlich
läuft parallel ein 60-Sekunden-Timer-Polling (`main_admin_scaffold_view.dart`,
`main_user_scaffold_view.dart`) permanent mit, auch wenn Realtime verbunden ist.

**Warum relevant:** Bei mehreren Flugschulen/vielen gleichzeitig aktiven Nutzern skaliert das
nicht – jede Datenänderung bei Flugschule A löst bei allen Nutzern von Flugschule B ebenfalls
einen vollen Reload aus (auch wenn Appwrite aus Berechtigungsgründen keine Nutzdaten dafür
zurückgibt, der Reload-Request selbst wird trotzdem ausgelöst).

**Vorschlag:** Falls Appwrite-Realtime das unterstützt, auf dokument-/query-gefilterte Kanäle
umstellen (z. B. nur Events der eigenen Flugschule(n)); das 60-Sekunden-Polling nur als
echten Fallback laufen lassen (z. B. deaktivieren/verlangsamen, solange die
Realtime-Verbindung nachweislich aktiv ist), statt dauerhaft parallel zu pollen.

---

## 4. Priorisierte Reihenfolge für die Umsetzung

**Sofort (Sicherheit, geringer Aufwand):**
1. Appwrite-Konsole: Collection-/Row-Permissions aller in 1.1 genannten Tabellen gegen das
   beschriebene Bedrohungsmodell prüfen (wer darf wirklich schreiben?).
2. Datei-Permissions bei allen drei Upload-Stellen ergänzen (1.4).
3. `print()` in `flight_school_functions.dart:13` entfernen (1.10).

**Kurzfristig (Stabilität/Sicherheit, mittlerer Aufwand):**
4. N+1-Problem Events↔Team-Zuweisungen beheben (3.2/3.5) – größter Effizienzgewinn im ganzen
   Review.
5. Fehlerbehandlung in `flight_school_service.dart` pro Event statt pro Batch (2.1).
6. Einheitliche Fehlerbehandlungs-Konvention für die Service-Schicht festlegen (2.2).

**Mittelfristig (strukturell):**
7. Mindestens Admin-Verwaltung, Qualifikationsfreigabe und Tausch-Finalisierung in Appwrite
   Functions verlagern (1.1/1.3/1.7).
8. Audit-Log serverseitig erzeugen statt client-seitig (1.3).
9. Relationship-Nutzung vereinheitlichen und Pagination für unbegrenzt wachsende Tabellen
   einführen (3.1/3.3).

---

## Testhinweise / Grenzen dieses Reviews

- Dies ist ein reiner **statischer** Code-Review ohne Zugriff auf die Appwrite-Konsole dieses
  Projekts. Alle Aussagen zu „hängt von Collection-Permissions ab“ sind als offene Prüfpunkte zu
  verstehen, nicht als bestätigte Lücken – sie könnten in der Konsole bereits korrekt
  abgesichert sein. Trotzdem: der Code selbst bietet aktuell **keine zweite Verteidigungslinie**
  für diese Fälle.
- Nicht tiefergehend geprüft: `lib/core/widgets/checklist_runner_view.dart` (Unterschriften-
  Workflow, rechtlich ggf. relevant für Nachweis-/Beweiskraft der Checklisten-Signatur),
  Appwrite-Indizes (ob die genutzten `Query.equal`-Felder überhaupt indiziert sind – ohne Index
  sind die vielen N+1-Einzelabfragen zusätzlich langsam), sowie ein Dependency-/CVE-Audit der
  `pubspec.yaml`-Pakete (sollte regelmäßig separat mit `dart pub outdated`/`dart pub audit`
  laufen).
