# Appwrite Function: `push_notifier`

Sendet echte Hintergrund-Push-Benachrichtigungen über **Appwrite Messaging** (FCM für Android/Web, APNs für iOS), sobald sich relevante Datensätze in der Datenbank ändern – und berücksichtigt dabei automatisch die in der App gesetzten Benachrichtigungs-Einstellungen (`account.prefs.notif_prefs`).

## Einrichtung in der Appwrite Console

1. **Messaging-Provider anlegen** (*Messaging → Providers*):
   - **Firebase Cloud Messaging (FCM)** für Android & Web-Push (Service-Account-JSON aus der Firebase Console).
   - **Apple Push Notification Service (APNs)** für iOS (`.p8` Key, Key ID, Team ID, Bundle ID).
2. **Function deployen**:
   - Ordner `appwrite_functions/push_notifier` als Node.js-20-Function in Appwrite anlegen.
   - Umgebungsvariable `APPWRITE_API_KEY` mit Scopes `users.read` und `messages.write` setzen.
3. **Events abonnieren** (*Function → Settings → Events*):
   - `databases.season_planner_db.tables.team_assignments_events.rows.*.create`
   - `databases.season_planner_db.tables.team_assignments_events.rows.*.update`
   - `databases.core_db.tables.memberships.rows.*.create`
   - `databases.core_db.tables.memberships.rows.*.update`
