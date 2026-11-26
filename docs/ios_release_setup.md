# iOS Release & TestFlight Setup (Anleitung für Apple Developer Account)

Die App **Tragegurt – Season Planner** ist bereits vollständig für iOS vorbereitet (`com.tragegurt.seasonplanner`, iOS 15+, Privacy-Hinweise, Push-Entitlements, automatischer GitHub-Actions-Build `.github/workflows/build_ios.yml`).

Damit GitHub Actions automatisch signierte `.ipa`-Builds erstellt und direkt nach **TestFlight / App Store Connect** hochlädt, sind einmalig diese 5 Schritte im Apple Developer Portal, in App Store Connect und in Firebase nötig (~10–15 Minuten):

---

## Schritt 1: Bundle ID (App ID) anlegen
1. Öffne https://developer.apple.com/account/resources/identifiers/list
2. Klicke auf **+** → **App IDs** → **App** → **Continue**.
3. Ausfüllen:
   - **Description:** `Tragegurt Season Planner`
   - **Bundle ID (Explicit):** `com.tragegurt.seasonplanner`
   - **Capabilities anhaken:**
     - ✅ **Push Notifications**
     - ✅ **Sign in with Apple** *(falls Apple-Login über Appwrite genutzt wird)*
4. **Continue → Register**.

---

## Schritt 2: App in App Store Connect anlegen
1. Öffne https://appstoreconnect.apple.com → **Meine Apps** → **+** → **Neue App**.
2. Ausfüllen:
   - **Plattform:** iOS
   - **Name:** `Tragegurt – Season Planner`
   - **Primäre Sprache:** Deutsch
   - **Bundle-ID:** `com.tragegurt.seasonplanner`
   - **SKU:** `tragegurt-season-planner`
   - **Benutzerzugriff:** Vollzugriff

---

## Schritt 3: Apple Distribution Zertifikat (`.p12`) & Provisioning Profile (`.mobileprovision`)

### A) Distribution-Zertifikat (`.p12`)
- Falls auf deinem Mac bereits ein gültiges **Apple Distribution** Zertifikat in der **Schlüsselbundverwaltung** liegt:
  - Schlüsselbundverwaltung öffnen → **Meine Zertifikate** → `Apple Distribution: ...` (inkl. privatem Schlüssel darunter) markieren → Rechtsklick → **Exportieren…** → Format **`.p12`** wählen → sicheres Passwort vergeben.
- Falls noch keines existiert:
  - In der Schlüsselbundverwaltung → *Zertifikatsassistent → Zertifikat von einer Zertifizierungsstelle anfordern* (CSR auf Festplatte speichern)
  - Im Apple Developer Portal unter **Certificates → + → Apple Distribution** die CSR hochladen, `.cer` herunterladen, Doppelklick (importiert in Schlüsselbund) und dann wie oben als **`.p12`** exportieren.

### B) App Store Distribution Provisioning Profile (`.mobileprovision`)
1. Öffne https://developer.apple.com/account/resources/profiles/list → **+**.
2. Wähle unter *Distribution*: **App Store Connect** → **Continue**.
3. App ID wählen: **`com.tragegurt.seasonplanner`** → **Continue**.
4. Das **Apple Distribution** Zertifikat aus Schritt 3A auswählen → **Continue**.
5. Profilname z. B. `Season Planner App Store` → **Generate → Download** (`.mobileprovision`).

---

## Schritt 4: App Store Connect API Key (`.p8`) für automatischen TestFlight-Upload
1. Öffne https://appstoreconnect.apple.com/access/integrations/api (Team Keys).
2. Klicke auf **+** *(API-Schlüssel generieren)*:
   - **Name:** `GitHub Actions CI`
   - **Zugriff:** `App-Manager` *(oder `Admin`)*
3. Nach dem Erstellen:
   - **Issuer ID** (steht ganz oben auf der Seite) notieren
   - **Key ID** (steht in der Tabellenzeile) notieren
   - **API-Schlüssel laden** (`AuthKey_XXXXXXXXXX.p8` — kann nur einmal heruntergeladen werden!)

---

## Schritt 5: Push-Benachrichtigungen für iOS (Firebase ↔ APNs)
1. Im Apple Developer Portal unter **Keys** (https://developer.apple.com/account/resources/authkeys/list) → **+**:
   - **Key Name:** `Tragegurt APNs Push`
   - ✅ **Apple Push Notifications service (APNs)** anhaken → **Continue → Register**.
   - **Key ID** & **Team ID** notieren und die `.p8`-Datei herunterladen.
2. In der **Firebase Console** (Projekt `tragegurt-season-planner`):
   - **App hinzufügen → iOS** → Bundle-ID: `com.tragegurt.seasonplanner` → **`GoogleService-Info.plist`** herunterladen.
   - Unter **Projekteinstellungen → Cloud Messaging → Apple-App-Konfiguration → APNs-Authentifizierungsschlüssel** die APNs-`.p8`-Datei + Key ID + Team ID hochladen.

---

## Schritt 6: GitHub Secrets eintragen (einmalig)
Alle Dateien auf dem Mac kurz als Base64 ausgeben (im Terminal):
```bash
base64 -i dist_cert.p12 | pbcopy
base64 -i Season_Planner_App_Store.mobileprovision | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
base64 -i GoogleService-Info.plist | pbcopy
```

Und im GitHub-Repository unter **Settings → Secrets and variables → Actions → New repository secret** eintragen:

| GitHub Secret | Wert |
|---|---|
| `IOS_DIST_CERT_P12_BASE64` | Base64 der `.p12`-Datei |
| `IOS_DIST_CERT_PASSWORD` | Export-Passwort der `.p12`-Datei |
| `IOS_PROVISION_PROFILE_BASE64` | Base64 der `.mobileprovision`-Datei |
| `IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64` | Base64 der `GoogleService-Info.plist` aus Firebase |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID aus Schritt 4 |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID aus Schritt 4 |
| `APP_STORE_CONNECT_API_KEY_P8_BASE64` | Base64 der `AuthKey_XXXX.p8` aus Schritt 4 |

Sobald diese Secrets eingetragen sind, reicht ein Klick auf **Actions → Build iOS (IPA & TestFlight) → Run workflow** (oder ein neuer Git-Tag `v1.0.x`): GitHub baut die signierte iOS-App und lädt sie automatisch direkt in **TestFlight** hoch!

*(Die fertigen Store-Texte, Datenschutzerklärung, Konto-löschen-URL und Reviewer-Zugangsdaten aus `play_store_assets/03_store_texte_und_eintraege.md` können 1:1 auch für App Store Connect verwendet werden.)*
