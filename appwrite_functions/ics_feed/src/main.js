import crypto from 'node:crypto';
import { Client, TablesDB, Query } from 'node-appwrite';

function safeTokenEquals(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || !a || !b) return false;
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

function formatIcsDate(iso) {
  const d = new Date(iso);
  const pad = (n) => String(n).padStart(2, '0');
  return (
    d.getUTCFullYear() +
    pad(d.getUTCMonth() + 1) +
    pad(d.getUTCDate()) +
    'T' +
    pad(d.getUTCHours()) +
    pad(d.getUTCMinutes()) +
    pad(d.getUTCSeconds()) +
    'Z'
  );
}

function formatIcsDateOnly(iso, addDays = 0) {
  const d = new Date(iso);
  if (addDays !== 0) d.setUTCDate(d.getUTCDate() + addDays);
  const pad = (n) => String(n).padStart(2, '0');
  return d.getUTCFullYear() + pad(d.getUTCMonth() + 1) + pad(d.getUTCDate());
}

function escapeIcs(str) {
  return String(str || '')
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r?\n/g, '\\n');
}

function buildIcs(calendarName, events) {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Tragegurt//Season Planner//DE',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    `X-WR-CALNAME:${escapeIcs(calendarName)}`,
  ];

  const stamp = formatIcsDate(new Date().toISOString());

  for (const ev of events) {
    lines.push('BEGIN:VEVENT');
    lines.push(`UID:${ev.$id}@tragegurt.com`);
    lines.push(`DTSTAMP:${stamp}`);
    if (ev.is_all_day) {
      lines.push(`DTSTART;VALUE=DATE:${formatIcsDateOnly(ev.start_time)}`);
      lines.push(`DTEND;VALUE=DATE:${formatIcsDateOnly(ev.end_time, 1)}`);
    } else {
      lines.push(`DTSTART:${formatIcsDate(ev.start_time)}`);
      lines.push(`DTEND:${formatIcsDate(ev.end_time)}`);
    }
    lines.push(`SUMMARY:${escapeIcs(ev.display_name || 'Event')}`);
    if (ev.location) lines.push(`LOCATION:${escapeIcs(ev.location)}`);
    if (ev.notes) lines.push(`DESCRIPTION:${escapeIcs(ev.notes)}`);
    lines.push('END:VEVENT');
  }

  lines.push('END:VCALENDAR');
  return lines.join('\r\n') + '\r\n';
}

export default async ({ req, res, error }) => {
  try {
    const type = req.query?.type || '';
    const id = req.query?.id || '';
    const token = req.query?.token || '';

    if (!type || !id || !token) {
      return res.text('Fehlende Parameter (type, id, token).', 400);
    }

    const apiKey =
      req.headers?.['x-appwrite-key'] || process.env.APPWRITE_API_KEY || '';
    const client = new Client()
      .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT || 'https://appwrite.tragegurt.com/v1')
      .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || 'tragegurt')
      .setKey(apiKey);

    const tablesDB = new TablesDB(client);

    if (type === 'school') {
      const school = await tablesDB.getRow({
        databaseId: 'core_db',
        tableId: 'flight_schools',
        rowId: id,
      });
      if (!safeTokenEquals(school.ics_token, token)) {
        return res.text('Ungültiger Token.', 403);
      }

      const eventsRes = await tablesDB.listRows({
        databaseId: school.database_id || 'season_planner_db',
        tableId: school.events_id || 'events',
        queries: [Query.limit(500)],
      });

      const events = (eventsRes.rows || []).filter(
        (e) => !e.flight_school_id || e.flight_school_id === id
      );

      // Bestätigte Tandem-Dienste der Flugschule ebenfalls in den ICS-Feed aufnehmen
      if (school.tandem_enabled !== false) {
        try {
          const tandemRes = await tablesDB.listRows({
            databaseId: school.database_id || 'season_planner_db',
            tableId: 'tandem_duties',
            queries: [
              Query.equal('flight_school_id', id),
              Query.equal('status', 'confirmed'),
              Query.limit(500),
            ],
          });
          const duties = tandemRes.rows || [];
          const pilotNames = new Map();
          const userIds = Array.from(new Set(duties.map((d) => d.user_id).filter(Boolean)));
          if (userIds.length > 0) {
            try {
              const usersRes = await tablesDB.listRows({
                databaseId: 'core_db',
                tableId: 'users',
                queries: [Query.limit(500)],
              });
              for (const u of usersRes.rows || []) {
                const name = u.name || u.mail || 'Tandempilot';
                if (u.auth_id) pilotNames.set(u.auth_id, name);
                if (u.$id) pilotNames.set(u.$id, name);
              }
            } catch (_) {}
          }
          for (const d of duties) {
            const pName = pilotNames.get(d.user_id) || 'Tandempilot';
            events.push({
              $id: `tandem_${d.$id}`,
              start_time: d.start_date,
              end_time: d.end_date,
              is_all_day: d.is_full_day !== false,
              display_name: `Tandem: ${pName}`,
              notes: d.notes || '',
            });
          }
        } catch (_) {}
      }

      const ics = buildIcs(`Season Planner – ${school.display_name || 'Flugschule'}`, events);
      return res.send(ics, 200, {
        'Content-Type': 'text/calendar; charset=utf-8',
        'Content-Disposition': 'inline; filename="season-planner.ics"',
        'Cache-Control': 'public, max-age=300',
      });
    }

    if (type === 'user') {
      const usersRes = await tablesDB.listRows({
        databaseId: 'core_db',
        tableId: 'users',
        queries: [
          Query.or([
            Query.equal('$id', id),
            Query.equal('auth_id', id),
          ]),
          Query.limit(1),
        ],
      });
      const userRow = (usersRes.rows || [])[0];
      if (!userRow || !safeTokenEquals(userRow.ics_token, token)) {
        return res.text('Ungültiger Token.', 403);
      }

      const candidateIds = Array.from(
        new Set([userRow.auth_id, userRow.$id].filter(Boolean))
      );

      const assignmentsRes = await tablesDB.listRows({
        databaseId: 'season_planner_db',
        tableId: 'team_assignments_events',
        queries: [
          candidateIds.length > 1
            ? Query.or(candidateIds.map((uid) => Query.equal('user_id', uid)))
            : Query.equal('user_id', candidateIds[0] || id),
          Query.select(['*', 'events.*']),
          Query.limit(500),
        ],
      });

      const acceptedStatuses = new Set(['accepted_user', 'accepted_flight_school']);
      const seen = new Set();
      const events = [];

      for (const a of assignmentsRes.rows || []) {
        if (!acceptedStatuses.has(a.status)) continue;
        const ev = a.events;
        if (!ev || !ev.$id || seen.has(ev.$id)) continue;
        seen.add(ev.$id);
        events.push(ev);
      }

      // Eigene bestätigte Tandem-Einsätze des Nutzers in den persönlichen Feed aufnehmen
      try {
        const tandemRes = await tablesDB.listRows({
          databaseId: 'season_planner_db',
          tableId: 'tandem_duties',
          queries: [
            candidateIds.length > 1
              ? Query.or(candidateIds.map((uid) => Query.equal('user_id', uid)))
              : Query.equal('user_id', candidateIds[0] || id),
            Query.equal('status', 'confirmed'),
            Query.limit(500),
          ],
        });
        const duties = tandemRes.rows || [];
        const schoolInfo = new Map();
        const schoolIds = Array.from(new Set(duties.map((d) => d.flight_school_id).filter(Boolean)));
        for (const sid of schoolIds) {
          try {
            const sRow = await tablesDB.getRow({
              databaseId: 'core_db',
              tableId: 'flight_schools',
              rowId: sid,
            });
            schoolInfo.set(sid, {
              enabled: sRow.tandem_enabled !== false,
              label: sRow.short_name || sRow.display_name || '',
            });
          } catch (_) {}
        }
        for (const d of duties) {
          const info = schoolInfo.get(d.flight_school_id);
          if (info && info.enabled === false) continue;
          const schoolSuffix = info && info.label ? ` (${info.label})` : '';
          events.push({
            $id: `tandem_${d.$id}`,
            start_time: d.start_date,
            end_time: d.end_date,
            is_all_day: d.is_full_day !== false,
            display_name: `Tandempilot${schoolSuffix}`,
            notes: d.notes || '',
          });
        }
      } catch (_) {}

      const ics = buildIcs(`Season Planner – ${userRow.name || 'Meine Events'}`, events);
      return res.send(ics, 200, {
        'Content-Type': 'text/calendar; charset=utf-8',
        'Content-Disposition': 'inline; filename="meine-events.ics"',
        'Cache-Control': 'public, max-age=300',
      });
    }

    return res.text('Unbekannter type (erwartet: user oder school).', 400);
  } catch (e) {
    error(String(e));
    return res.text('Fehler beim Erzeugen des Kalender-Feeds.', 500);
  }
};
