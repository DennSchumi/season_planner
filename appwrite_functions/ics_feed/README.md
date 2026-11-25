# Tragegurt ICS-Kalender-Abo Function (Appwrite 2.x)

Diese Appwrite Function stellt einen automatisch aktuellen **ICS-Kalender-Feed (`text/calendar`)** für einzelne Nutzer (`?type=user&id=...&token=...`) und Flugschulen (`?type=school&id=...&token=...`) bereit.

## Deployment in Appwrite 2.x
1. Öffne in der Appwrite Console (`https://appwrite.tragegurt.com`) dein Projekt **`tragegurt`** → **Functions → Create function**.
2. **Name:** `ICS Calendar Feed` · **Function ID:** `ics_feed` · **Runtime:** `Node.js 22`.
3. **Execute access:** `Any` (damit Kalender-Apps wie Apple/Google/Outlook den Feed per Token abrufen können).
4. **Environment Variables** in der Function setzen:
   * `APPWRITE_API_KEY`: ein eigener API-Key mit ausschließlich `tables.read` & `rows.read` (Read-Only!).
5. Diesen Ordner (`appwrite_functions/ics_feed`) deployen (via Appwrite CLI oder Git).
6. Die generierte Function-Domain (oder Custom Domain z. B. `https://ics.tragegurt.com`) in `lib/core/appwrite_config.dart` bei `icsFeedBaseUrl` hinterlegen (bzw. beim Build per `--dart-define=ICS_FEED_URL=...` übergeben).
