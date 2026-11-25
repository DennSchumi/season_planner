import { Client, ID, Messaging, Users } from 'node-appwrite';

/**
 * Prüft anhand der in Appwrite `user.prefs.notif_prefs` gespeicherten
 * Einstellungen (identisch zur Flutter-App), ob der Nutzer diese Kategorie
 * aktiviert hat.
 */
function isCategoryAllowed(userPrefs, categoryKey) {
  try {
    const raw = userPrefs?.notif_prefs;
    if (!raw) return true; // Standard: aktiviert
    const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (parsed.enabled === false) return false;
    if (parsed[categoryKey] === false) return false;
    return true;
  } catch {
    return true;
  }
}

export default async ({ req, res, log, error }) => {
  const endpoint =
    process.env.APPWRITE_FUNCTION_API_ENDPOINT ||
    process.env.APPWRITE_ENDPOINT ||
    'https://appwrite.tragegurt.com/v1';
  const projectId =
    process.env.APPWRITE_FUNCTION_PROJECT_ID || process.env.APPWRITE_PROJECT_ID;
  const apiKey = process.env.APPWRITE_API_KEY;

  if (!projectId || !apiKey) {
    error('APPWRITE_FUNCTION_PROJECT_ID oder APPWRITE_API_KEY fehlt.');
    return res.json({ ok: false, reason: 'missing_env' }, 500);
  }

  const client = new Client()
    .setEndpoint(endpoint)
    .setProject(projectId)
    .setKey(apiKey);

  const users = new Users(client);
  const messaging = new Messaging(client);

  const eventName = req.headers['x-appwrite-trigger-event'] || '';
  const payload =
    typeof req.body === 'string' && req.body.trim().length > 0
      ? JSON.parse(req.body)
      : req.body || {};

  // Ermittelt Empfänger, Kategorie, Titel & Text je nach Appwrite-Datenbank-Event
  let recipientUserIds = [];
  let categoryKey = 'assignmentRequests';
  let title = '';
  let body = '';

  if (eventName.includes('team_assignments_events')) {
    const status = String(payload.status || '');
    const userId = String(payload.user_id || '').trim();
    const role = String(payload.role || 'Einsatz');

    if (status === 'pending_user' && userId) {
      recipientUserIds = [userId];
      categoryKey = 'assignmentRequests';
      title = 'Neue Einsatz-Anfrage';
      body = `Du wurdest für die Position „${role}“ angefragt. Bitte bestätige oder lehne ab.`;
    } else if (status === 'accepted_flight_school' && userId) {
      recipientUserIds = [userId];
      categoryKey = 'assignmentRequests';
      title = 'Einsatz bestätigt';
      body = `Deine Zuteilung als „${role}“ wurde bestätigt.`;
    } else if (payload.swap_requested_by && userId) {
      recipientUserIds = [userId];
      categoryKey = 'swapRequests';
      title = 'Neue Tauschanfrage';
      body = `Für deine Position „${role}“ liegt ein Tauschwunsch vor.`;
    }
  } else if (eventName.includes('memberships')) {
    const status = String(payload.status || '');
    const userId = String(payload.user_id || '').trim();
    if (status === 'invited' && userId) {
      recipientUserIds = [userId];
      categoryKey = 'flightSchoolInvites';
      title = 'Flugschul-Einladung';
      body = 'Du wurdest in das Team einer Flugschule eingeladen.';
    }
  }

  if (recipientUserIds.length === 0 || !title) {
    log(`Kein Push erforderlich für Event: ${eventName}`);
    return res.json({ ok: true, skipped: true });
  }

  const allowedUsers = [];
  for (const uid of recipientUserIds) {
    try {
      const user = await users.get(uid);
      if (isCategoryAllowed(user.prefs, categoryKey)) {
        allowedUsers.push(uid);
      }
    } catch (e) {
      error(`Benutzer ${uid} konnte nicht geladen werden: ${e.message}`);
    }
  }

  if (allowedUsers.length === 0) {
    log(`Alle Empfänger haben Kategorie ${categoryKey} deaktiviert.`);
    return res.json({ ok: true, skipped: true, reason: 'muted_by_user' });
  }

  try {
    await messaging.createPush(
      ID.unique(),
      title,
      body,
      [], // topics
      allowedUsers, // users
      [], // targets
      { category: categoryKey, event: eventName }
    );
    log(`Push gesendet an ${allowedUsers.length} Empfänger (${categoryKey}).`);
    return res.json({ ok: true, sentTo: allowedUsers.length });
  } catch (e) {
    error(`Push-Versand fehlgeschlagen: ${e.message}`);
    return res.json({ ok: false, error: e.message }, 500);
  }
};
