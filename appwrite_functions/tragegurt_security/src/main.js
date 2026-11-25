import {
  Client,
  TablesDB,
  Storage,
  Teams,
  Users,
  Query,
  ID,
  Permission,
  Role,
} from 'node-appwrite';

const CORE_DB = 'core_db';
const SP_DB = 'season_planner_db';
const INV_DB = 'inventory_db';

const QUAL_DOCS_BUCKET = 'qualification_documents';
const USER_AVATARS_BUCKET = 'user_avatars';

async function listAllRows(tablesDB, databaseId, tableId, baseQueries = []) {
  const all = [];
  let cursor = null;
  while (true) {
    const queries = [...baseQueries, Query.limit(100)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const res = await tablesDB.listRows({ databaseId, tableId, queries });
    const rows = res.rows || [];
    all.push(...rows);
    if (rows.length < 100) break;
    cursor = rows[rows.length - 1].$id;
  }
  return all;
}

async function listAllTeamMemberships(teams, teamId) {
  const all = [];
  let cursor = null;
  while (true) {
    const queries = [Query.limit(100)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const res = await teams.listMemberships({ teamId, queries });
    const rows = res.memberships || [];
    all.push(...rows);
    if (rows.length < 100) break;
    cursor = rows[rows.length - 1].$id;
  }
  return all;
}

async function listAllAuthUsers(usersApi) {
  const all = [];
  let cursor = null;
  while (true) {
    const queries = [Query.limit(100)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const res = await usersApi.list({ queries });
    const rows = res.users || [];
    all.push(...rows);
    if (rows.length < 100) break;
    cursor = rows[rows.length - 1].$id;
  }
  return all;
}

function extractUserAuthId(userField) {
  if (!userField) return '';
  if (typeof userField === 'string') return userField.trim();
  if (typeof userField === 'object') {
    return String(userField.auth_id || userField.$id || '').trim();
  }
  return '';
}

function extractUserRowId(userField) {
  if (!userField) return '';
  if (typeof userField === 'string') return userField.trim();
  if (typeof userField === 'object') {
    return String(userField.$id || '').trim();
  }
  return '';
}

function extractSchoolId(fsField) {
  if (!fsField) return '';
  if (typeof fsField === 'string') return fsField.trim();
  if (typeof fsField === 'object') {
    return String(fsField.$id || '').trim();
  }
  return '';
}

async function getSchoolRow(tablesDB, flightSchoolId) {
  return tablesDB.getRow({
    databaseId: CORE_DB,
    tableId: 'flight_schools',
    rowId: flightSchoolId,
  });
}

async function getUserRowByAuthId(tablesDB, authId) {
  const res = await tablesDB.listRows({
    databaseId: CORE_DB,
    tableId: 'users',
    queries: [
      Query.or([Query.equal('$id', authId), Query.equal('auth_id', authId)]),
      Query.limit(1),
    ],
  });
  return (res.rows || [])[0] || null;
}

async function isSchoolAdmin(tablesDB, flightSchoolId, callerId) {
  if (!flightSchoolId || !callerId) return false;
  try {
    const school = await getSchoolRow(tablesDB, flightSchoolId);
    const admins = Array.isArray(school.admin_users) ? school.admin_users : [];
    if (admins.includes(callerId)) return true;
    const userRow = await getUserRowByAuthId(tablesDB, callerId);
    if (userRow && admins.includes(userRow.$id)) return true;
    return false;
  } catch {
    return false;
  }
}

async function isActiveSchoolMember(tablesDB, flightSchoolId, callerId) {
  if (await isSchoolAdmin(tablesDB, flightSchoolId, callerId)) return true;
  const rows = await listAllRows(tablesDB, CORE_DB, 'memberships', [
    Query.equal('flightSchools', flightSchoolId),
    Query.select(['*', 'users.$id', 'users.auth_id']),
  ]);
  for (const m of rows) {
    if (m.status !== 'active') continue;
    const uid = extractUserAuthId(m.users);
    const rid = extractUserRowId(m.users);
    if (uid === callerId || rid === callerId) return true;
  }
  return false;
}

async function writeAuditLog(tablesDB, { flightSchoolId, userId, action, details }) {
  try {
    await tablesDB.createRow({
      databaseId: SP_DB,
      tableId: 'audit_logs',
      rowId: ID.unique(),
      data: {
        flight_school_id: flightSchoolId,
        user_id: userId,
        action,
        details,
        timestamp: new Date().toISOString(),
      },
      permissions: [Permission.read(Role.team(flightSchoolId, 'admin'))],
    });
  } catch (_) {}
}

/**
 * Aktualisiert die Row-Permissions auf `core_db.users` für einen Benutzer:
 * Nur der Nutzer selbst + Admins der Flugschulen, bei denen er aktiv oder
 * angefragt Mitglied ist, dürfen sein vollständiges Profil lesen.
 */
async function syncUserRowPermissions(tablesDB, authId) {
  const userRow = await getUserRowByAuthId(tablesDB, authId);
  if (!userRow) return;
  const canonicalAuthId = String(userRow.auth_id || userRow.$id).trim();
  const memberships = await listAllRows(tablesDB, CORE_DB, 'memberships', [
    Query.equal('users', userRow.$id),
    Query.select(['*', 'flightSchools.$id']),
  ]);

  const schoolIds = new Set();
  for (const m of memberships) {
    if (m.status === 'inactive') continue;
    const sid = extractSchoolId(m.flightSchools);
    if (sid) schoolIds.add(sid);
  }

  const perms = [
    Permission.read(Role.user(canonicalAuthId)),
    Permission.update(Role.user(canonicalAuthId)),
  ];
  for (const sid of schoolIds) {
    perms.push(Permission.read(Role.team(sid, 'admin')));
  }

  await tablesDB.updateRow({
    databaseId: CORE_DB,
    tableId: 'users',
    rowId: userRow.$id,
    data: {},
    permissions: perms,
  });
}

/**
 * Synchronisiert das Appwrite Team (`teamId = flightSchoolId`) mit allen
 * aktiven Mitgliedern und Admins aus `core_db.flight_schools` & `memberships`.
 */
async function syncSchoolTeam(tablesDB, teams, flightSchoolId) {
  const school = await getSchoolRow(tablesDB, flightSchoolId);
  const schoolName = String(school.display_name || 'Flugschule').slice(0, 128);

  // 1) Team sicherstellen
  try {
    await teams.get({ teamId: flightSchoolId });
  } catch {
    await teams.create({ teamId: flightSchoolId, name: schoolName });
  }

  // 2) Soll-Mitglieder & Admins ermitteln
  const adminIds = new Set(
    (Array.isArray(school.admin_users) ? school.admin_users : [])
      .map((x) => String(x || '').trim())
      .filter(Boolean)
  );

  const memberships = await listAllRows(tablesDB, CORE_DB, 'memberships', [
    Query.equal('flightSchools', flightSchoolId),
    Query.select(['*', 'users.$id', 'users.auth_id']),
  ]);

  // Map authUserId -> Set<roles>
  const desired = new Map();
  const allLinkedAuthIds = new Set();

  for (const aid of adminIds) {
    // Falls admin_users eine Row-ID enthält, auf auth_id normalisieren
    const uRow = await getUserRowByAuthId(tablesDB, aid);
    const resolvedAuthId = String(uRow?.auth_id || uRow?.$id || aid).trim();
    if (!resolvedAuthId) continue;
    desired.set(resolvedAuthId, new Set(['member', 'admin']));
    allLinkedAuthIds.add(resolvedAuthId);
  }

  for (const m of memberships) {
    const authId = extractUserAuthId(m.users);
    const rowId = extractUserRowId(m.users);
    if (!authId) continue;
    if (m.status !== 'inactive') {
      allLinkedAuthIds.add(authId);
    }
    if (m.status === 'active') {
      const roles = desired.get(authId) || new Set(['member']);
      roles.add('member');
      if (adminIds.has(authId) || adminIds.has(rowId)) {
        roles.add('admin');
      }
      desired.set(authId, roles);
    }
  }

  // 3) Ist-Mitgliedschaften im Appwrite Team abgleichen
  const existingTeamMembers = await listAllTeamMemberships(teams, flightSchoolId);
  const existingByUserId = new Map();
  for (const tm of existingTeamMembers) {
    existingByUserId.set(tm.userId, tm);
  }

  for (const [uid, rolesSet] of desired.entries()) {
    const rolesArr = Array.from(rolesSet).sort();
    const existing = existingByUserId.get(uid);
    if (!existing) {
      try {
        await teams.createMembership({
          teamId: flightSchoolId,
          roles: rolesArr,
          userId: uid,
        });
      } catch (_) {}
    } else {
      const currRoles = [...(existing.roles || [])].sort();
      if (JSON.stringify(currRoles) !== JSON.stringify(rolesArr)) {
        try {
          await teams.updateMembership({
            teamId: flightSchoolId,
            membershipId: existing.$id,
            roles: rolesArr,
          });
        } catch (_) {}
      }
    }
  }

  // Nicht mehr aktive Nutzer aus dem Appwrite Team entfernen
  for (const [uid, existing] of existingByUserId.entries()) {
    if (!desired.has(uid)) {
      try {
        await teams.deleteMembership({
          teamId: flightSchoolId,
          membershipId: existing.$id,
        });
      } catch (_) {}
      allLinkedAuthIds.add(uid);
    }
  }

  // 4) Row-Permissions der Schule auf Admins festziehen (read bleibt für Suche)
  try {
    await tablesDB.updateRow({
      databaseId: CORE_DB,
      tableId: 'flight_schools',
      rowId: flightSchoolId,
      data: {},
      permissions: [
        Permission.read(Role.users()),
        Permission.update(Role.team(flightSchoolId, 'admin')),
        Permission.delete(Role.team(flightSchoolId, 'admin')),
      ],
    });
  } catch (_) {}

  // 5) Benutzer-Row-Permissions für alle betroffenen Mitglieder aktualisieren
  for (const uid of allLinkedAuthIds) {
    try {
      await syncUserRowPermissions(tablesDB, uid);
    } catch (_) {}
  }

  return { syncedMembers: desired.size };
}

/**
 * Synchronisiert DB-Row- UND Storage-File-Permissions für ein Qualifikationsdokument:
 * - Besitzer hat read/update/delete
 * - Nur Flugschulen mit aktiver Freigabe (`qualification_approvals`) erhalten
 *   Admin-Leserechte (und DB-Metadaten-Update für Ablaufdatum; Datei bleibt read-only!).
 */
async function syncDocumentPermissions(tablesDB, storage, documentId) {
  const doc = await tablesDB.getRow({
    databaseId: CORE_DB,
    tableId: 'qualification_documents',
    rowId: documentId,
  });
  const ownerId = String(doc.user_id || '').trim();
  const fileId = String(doc.file_id || '').trim();
  if (!ownerId) return { ok: false };

  const approvals = await listAllRows(tablesDB, CORE_DB, 'qualification_approvals', [
    Query.equal('document_id', documentId),
  ]);

  const sharedSchoolIds = new Set();
  for (const a of approvals) {
    const sid = String(a.flight_school_id || '').trim();
    if (sid) sharedSchoolIds.add(sid);
  }

  const rowPerms = [
    Permission.read(Role.user(ownerId)),
    Permission.update(Role.user(ownerId)),
    Permission.delete(Role.user(ownerId)),
  ];
  const filePerms = [
    Permission.read(Role.user(ownerId)),
    Permission.update(Role.user(ownerId)),
    Permission.delete(Role.user(ownerId)),
  ];

  for (const sid of sharedSchoolIds) {
    rowPerms.push(Permission.read(Role.team(sid, 'admin')));
    rowPerms.push(Permission.update(Role.team(sid, 'admin')));
    filePerms.push(Permission.read(Role.team(sid, 'admin')));
  }

  await tablesDB.updateRow({
    databaseId: CORE_DB,
    tableId: 'qualification_documents',
    rowId: documentId,
    data: {},
    permissions: rowPerms,
  });

  if (fileId) {
    try {
      await storage.updateFile({
        bucketId: QUAL_DOCS_BUCKET,
        fileId,
        permissions: filePerms,
      });
    } catch (_) {}
  }

  // Auch die zugehörigen Approval-Zeilen sauber absichern
  for (const a of approvals) {
    const sid = String(a.flight_school_id || '').trim();
    const appPerms = [
      Permission.read(Role.user(ownerId)),
      Permission.update(Role.user(ownerId)),
      Permission.delete(Role.user(ownerId)),
    ];
    if (sid) {
      appPerms.push(Permission.read(Role.team(sid, 'admin')));
      appPerms.push(Permission.update(Role.team(sid, 'admin')));
      appPerms.push(Permission.delete(Role.team(sid, 'admin')));
    }
    try {
      await tablesDB.updateRow({
        databaseId: CORE_DB,
        tableId: 'qualification_approvals',
        rowId: a.$id,
        data: {},
        permissions: appPerms,
      });
    } catch (_) {}
  }

  return { ok: true, sharedSchoolCount: sharedSchoolIds.size };
}

/**
 * Entzieht beim Austritt / Entfernen aus einer Flugschule sofort alle
 * Freigaben, Datei-Leserechte, Team-Rechte und Profil-Leserechte dieser Schule.
 */
async function revokeSchoolAccess(tablesDB, storage, teams, flightSchoolId, targetAuthId) {
  const userRow = await getUserRowByAuthId(tablesDB, targetAuthId);
  const candidateIds = Array.from(
    new Set([targetAuthId, userRow?.$id, userRow?.auth_id].filter(Boolean))
  );

  // 1) Alle Dokument-Freigaben für diese Flugschule löschen & Dokumente neu sperren
  const touchedDocIds = new Set();
  for (const cid of candidateIds) {
    const approvals = await listAllRows(tablesDB, CORE_DB, 'qualification_approvals', [
      Query.equal('user_id', cid),
      Query.equal('flight_school_id', flightSchoolId),
    ]);
    for (const a of approvals) {
      if (a.document_id) touchedDocIds.add(String(a.document_id));
      try {
        await tablesDB.deleteRow({
          databaseId: CORE_DB,
          tableId: 'qualification_approvals',
          rowId: a.$id,
        });
      } catch (_) {}
    }
  }

  for (const docId of touchedDocIds) {
    try {
      await syncDocumentPermissions(tablesDB, storage, docId);
    } catch (_) {}
  }

  // 2) Team-Mitgliedschaft & User-Row-Permissions synchronisieren
  await syncSchoolTeam(tablesDB, teams, flightSchoolId);
  await syncUserRowPermissions(tablesDB, targetAuthId);

  return { ok: true, revokedDocuments: touchedDocIds.size };
}

/**
 * Art. 15 & Art. 20 DSGVO: Vollständiger personenbezogener Datenexport (JSON)
 * für den eingeloggten Nutzer.
 */
async function exportUserData(tablesDB, usersApi, callerId) {
  const authUser = await usersApi.get({ userId: callerId });
  const userRow = await getUserRowByAuthId(tablesDB, callerId);
  const candidateIds = Array.from(
    new Set([callerId, userRow?.$id, userRow?.auth_id].filter(Boolean))
  );

  const memberships = userRow
    ? await listAllRows(tablesDB, CORE_DB, 'memberships', [
        Query.equal('users', userRow.$id),
        Query.select(['*', 'flightSchools.$id', 'flightSchools.display_name']),
      ])
    : [];

  const qualDocs = [];
  const qualApprovals = [];
  const assignments = [];
  const availabilities = [];
  const tandemDuties = [];
  const timesheets = [];
  const checklists = [];
  const inventoryTransactions = [];

  const seenIds = (list) => new Set(list.map((x) => x.$id));

  for (const cid of candidateIds) {
    for (const r of await listAllRows(tablesDB, CORE_DB, 'qualification_documents', [
      Query.equal('user_id', cid),
    ])) {
      if (!seenIds(qualDocs).has(r.$id)) qualDocs.push(r);
    }
    for (const r of await listAllRows(tablesDB, CORE_DB, 'qualification_approvals', [
      Query.equal('user_id', cid),
    ])) {
      if (!seenIds(qualApprovals).has(r.$id)) qualApprovals.push(r);
    }
    for (const r of await listAllRows(tablesDB, SP_DB, 'team_assignments_events', [
      Query.equal('user_id', cid),
      Query.select(['*', 'events.display_name', 'events.start_time', 'events.end_time']),
    ])) {
      if (!seenIds(assignments).has(r.$id)) assignments.push(r);
    }
    for (const r of await listAllRows(tablesDB, SP_DB, 'availability_submissions', [
      Query.equal('user_id', cid),
    ])) {
      if (!seenIds(availabilities).has(r.$id)) availabilities.push(r);
    }
    for (const r of await listAllRows(tablesDB, SP_DB, 'tandem_duties', [
      Query.equal('user_id', cid),
    ])) {
      if (!seenIds(tandemDuties).has(r.$id)) tandemDuties.push(r);
    }
    for (const r of await listAllRows(tablesDB, SP_DB, 'event_timesheets', [
      Query.equal('user_id', cid),
    ])) {
      if (!seenIds(timesheets).has(r.$id)) timesheets.push(r);
    }
    for (const r of await listAllRows(tablesDB, SP_DB, 'checklist_completions', [
      Query.equal('user_id', cid),
    ])) {
      if (!seenIds(checklists).has(r.$id)) checklists.push(r);
    }
    try {
      for (const r of await listAllRows(tablesDB, INV_DB, 'transactions', [
        Query.equal('userId', cid),
      ])) {
        if (!seenIds(inventoryTransactions).has(r.$id)) {
          inventoryTransactions.push(r);
        }
      }
    } catch (_) {}
  }

  return {
    exportMetadata: {
      exportedAt: new Date().toISOString(),
      platform: 'Tragegurt (Season Planner & Inventar Manager)',
      legalBasis: 'Art. 15 & Art. 20 DSGVO (Auskunft & Datenübertragbarkeit)',
    },
    account: {
      id: authUser.$id,
      email: authUser.email,
      name: authUser.name,
      phone: authUser.phone,
      emailVerification: authUser.emailVerification,
      registrationDate: authUser.registration,
      prefs: authUser.prefs || {},
    },
    profile: userRow || null,
    flightSchoolMemberships: memberships,
    qualificationDocuments: qualDocs,
    qualificationApprovals: qualApprovals,
    eventAssignments: assignments,
    availabilitySubmissions: availabilities,
    tandemDuties,
    eventTimesheets: timesheets,
    checklistCompletions: checklists,
    inventoryTransactions,
  };
}

/**
 * Art. 17 DSGVO: Vollständige Kontolöschung inkl. Dateien, Mitgliedschaften,
 * Verfügbarkeiten & Appwrite-Auth-Konto (mit Schutz gegen verwaiste Flugschulen
 * und Wahrung bereits eingereichter gesetzlicher Stundenzettel/Einweisungen).
 */
async function deleteUserAccount(tablesDB, storage, teams, usersApi, callerId, confirmEmail) {
  const authUser = await usersApi.get({ userId: callerId });
  const expectedEmail = String(authUser.email || '').trim().toLowerCase();
  if (!confirmEmail || String(confirmEmail).trim().toLowerCase() !== expectedEmail) {
    return {
      ok: false,
      status: 400,
      error: 'Die eingegebene E-Mail-Adresse stimmt nicht mit deinem Konto überein.',
    };
  }

  const userRow = await getUserRowByAuthId(tablesDB, callerId);
  const candidateIds = Array.from(
    new Set([callerId, userRow?.$id, userRow?.auth_id].filter(Boolean))
  );

  // Prüfen, ob Nutzer einziger Admin einer Flugschule ist
  const schools = await listAllRows(tablesDB, CORE_DB, 'flight_schools', []);
  const soleAdminSchools = [];
  const adminSchoolRows = [];
  for (const s of schools) {
    const admins = Array.isArray(s.admin_users) ? s.admin_users : [];
    const isAdmin = admins.some((a) => candidateIds.includes(String(a)));
    if (!isAdmin) continue;
    adminSchoolRows.push(s);
    const remaining = admins.filter((a) => !candidateIds.includes(String(a)));
    if (remaining.length === 0) {
      soleAdminSchools.push(s.display_name || s.$id);
    }
  }
  if (soleAdminSchools.length > 0) {
    return {
      ok: false,
      status: 409,
      error:
        `Du bist derzeit einziger Admin für: ${soleAdminSchools.join(', ')}. ` +
        'Bitte ernenne dort zuerst einen weiteren Admin, bevor du dein Konto löschst.',
    };
  }

  // 1) Nutzer aus admin_users anderer Schulen austragen
  for (const s of adminSchoolRows) {
    const remaining = (s.admin_users || []).filter(
      (a) => !candidateIds.includes(String(a))
    );
    try {
      await tablesDB.updateRow({
        databaseId: CORE_DB,
        tableId: 'flight_schools',
        rowId: s.$id,
        data: { admin_users: remaining },
      });
    } catch (_) {}
  }

  // 2) Qualifikationsdokumente, Freigaben & zugehörige Storage-Dateien löschen
  for (const cid of candidateIds) {
    const approvals = await listAllRows(tablesDB, CORE_DB, 'qualification_approvals', [
      Query.equal('user_id', cid),
    ]);
    for (const a of approvals) {
      try {
        await tablesDB.deleteRow({
          databaseId: CORE_DB,
          tableId: 'qualification_approvals',
          rowId: a.$id,
        });
      } catch (_) {}
    }

    const docs = await listAllRows(tablesDB, CORE_DB, 'qualification_documents', [
      Query.equal('user_id', cid),
    ]);
    for (const d of docs) {
      if (d.file_id) {
        try {
          await storage.deleteFile({
            bucketId: QUAL_DOCS_BUCKET,
            fileId: d.file_id,
          });
        } catch (_) {}
      }
      try {
        await tablesDB.deleteRow({
          databaseId: CORE_DB,
          tableId: 'qualification_documents',
          rowId: d.$id,
        });
      } catch (_) {}
    }

    // 3) Verfügbarkeiten löschen
    const avails = await listAllRows(tablesDB, SP_DB, 'availability_submissions', [
      Query.equal('user_id', cid),
    ]);
    for (const av of avails) {
      try {
        await tablesDB.deleteRow({
          databaseId: SP_DB,
          tableId: 'availability_submissions',
          rowId: av.$id,
        });
      } catch (_) {}
    }

    // 4) Zukünftige Events: Zuweisung freigeben (offener Slot); vergangene bleiben als Historie ohne Account
    const nowIso = new Date().toISOString();
    const assignments = await listAllRows(tablesDB, SP_DB, 'team_assignments_events', [
      Query.equal('user_id', cid),
      Query.select(['*', 'events.start_time']),
    ]);
    for (const a of assignments) {
      const startTime = a.events?.start_time || '';
      if (startTime && startTime >= nowIso) {
        try {
          await tablesDB.updateRow({
            databaseId: SP_DB,
            tableId: 'team_assignments_events',
            rowId: a.$id,
            data: {
              user_id: '',
              name: '',
              status: 'open',
              swap_offered: false,
              swap_requested_by: '',
              swap_requested_by_name: '',
            },
          });
        } catch (_) {}
      }
    }

    // 5) Zukünftige Tandem-Einsätze entfernen
    const duties = await listAllRows(tablesDB, SP_DB, 'tandem_duties', [
      Query.equal('user_id', cid),
    ]);
    for (const d of duties) {
      if (d.start_date && d.start_date >= nowIso) {
        try {
          await tablesDB.deleteRow({
            databaseId: SP_DB,
            tableId: 'tandem_duties',
            rowId: d.$id,
          });
        } catch (_) {}
      }
    }
  }

  // 6) Profilbild aus user_avatars löschen
  if (userRow?.avatar_file_id) {
    try {
      await storage.deleteFile({
        bucketId: USER_AVATARS_BUCKET,
        fileId: userRow.avatar_file_id,
      });
    } catch (_) {}
  }

  // 7) Mitgliedschaften & Appwrite-Team-Mitgliedschaften entfernen
  const touchedSchools = new Set(adminSchoolRows.map((s) => s.$id));
  if (userRow) {
    const memberships = await listAllRows(tablesDB, CORE_DB, 'memberships', [
      Query.equal('users', userRow.$id),
      Query.select(['*', 'flightSchools.$id']),
    ]);
    for (const m of memberships) {
      const sid = extractSchoolId(m.flightSchools);
      if (sid) touchedSchools.add(sid);
      try {
        await tablesDB.deleteRow({
          databaseId: CORE_DB,
          tableId: 'memberships',
          rowId: m.$id,
        });
      } catch (_) {}
    }

    // 8) core_db.users Profilzeile löschen
    try {
      await tablesDB.deleteRow({
        databaseId: CORE_DB,
        tableId: 'users',
        rowId: userRow.$id,
      });
    } catch (_) {}
  }

  // Aus allen Appwrite Teams entfernen
  for (const sid of touchedSchools) {
    try {
      await syncSchoolTeam(tablesDB, teams, sid);
    } catch (_) {}
  }

  // 9) Appwrite Auth Account endgültig löschen
  await usersApi.delete({ userId: callerId });

  return { ok: true };
}

const LEGACY_ROLE_LABELS = {
  leader: 'Fluglehrer',
  co_leader: 'Anwärter',
  additional_support: 'Sicherheitstrainer',
  trainee: 'Tandempilot',
  camera_crew: 'Kamerateam',
};

function normalizeRoleLabel(raw) {
  const trimmed = String(raw || '').trim();
  if (!trimmed) return '';
  return LEGACY_ROLE_LABELS[trimmed] || trimmed;
}

function parseStringList(raw) {
  if (Array.isArray(raw)) {
    return raw.map((x) => String(x || '').trim()).filter(Boolean);
  }
  if (typeof raw === 'string' && raw.trim().length > 0) {
    const s = raw.trim();
    if (s.startsWith('[')) {
      try {
        const arr = JSON.parse(s);
        if (Array.isArray(arr)) {
          return arr.map((x) => String(x || '').trim()).filter(Boolean);
        }
      } catch (_) {}
    }
    return s
      .split(',')
      .map((x) => x.trim())
      .filter(Boolean);
  }
  return [];
}

function isDefaultTimesheetQualificationName(name) {
  const n = String(name || '').trim().toLowerCase();
  return (
    n.includes('lehrer') ||
    n.includes('trainer') ||
    n.includes('anwärter') ||
    n.includes('anwaerter')
  );
}

function formatShortDateRangeDe(startMs, endMs, isFullDay = false) {
  const s = new Date(startMs);
  const e = new Date(endMs);
  const pad = (n) => String(n).padStart(2, '0');
  const dStr = (d) => `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()}`;
  const tStr = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  const sameDay =
    s.getFullYear() === e.getFullYear() &&
    s.getMonth() === e.getMonth() &&
    s.getDate() === e.getDate();
  if (isFullDay) {
    return sameDay ? dStr(s) : `${dStr(s)} – ${dStr(e)}`;
  }
  return sameDay
    ? `${dStr(s)} ${tStr(s)}–${tStr(e)}`
    : `${dStr(s)} – ${dStr(e)}`;
}

/**
 * Schulübergreifende Doppelbesetzungs-Prüfung (DSGVO-konform & datensparsam):
 * - Für Admins: prüft alle übergebenen Teammitglieder über alle Flugschulen hinweg.
 *   Für fremde Flugschulen werden KEINE Event- oder Schulnamen preisgegeben,
 *   sondern nur ein neutraler Hinweis mit Zeitraum.
 * - Für Nutzer (Selbstprüfung): prüft eigene Events & Tandem-Dienste über alle
 *   Flugschulen hinweg inkl. Eventnamen.
 */
async function checkCrossSchoolConflicts(
  tablesDB,
  {
    flightSchoolId = '',
    userIds = [],
    startTime = '',
    endTime = '',
    ignoreEventId = '',
    ignoreDutyId = '',
    otherSchoolsOnly = false,
    isSelfCheck = false,
  }
) {
  const reqStartMs = Date.parse(startTime);
  const reqEndMs = Date.parse(endTime);
  if (!Number.isFinite(reqStartMs) || !Number.isFinite(reqEndMs)) {
    return { ok: true, conflictsByUserId: {} };
  }

  const cleanedUserIds = Array.from(
    new Set(userIds.map((x) => String(x || '').trim()).filter(Boolean))
  );
  if (cleanedUserIds.length === 0) {
    return { ok: true, conflictsByUserId: {} };
  }

  // Alle ID-Varianten (auth_id & core_db.users.$id) je angefragter userId auflösen
  const canonicalForVariant = new Map();
  const allLookupIds = new Set();
  for (const uid of cleanedUserIds) {
    allLookupIds.add(uid);
    if (!canonicalForVariant.has(uid)) canonicalForVariant.set(uid, new Set());
    canonicalForVariant.get(uid).add(uid);
  }

  const uidArr = Array.from(allLookupIds);
  for (let i = 0; i < uidArr.length; i += 50) {
    const chunk = uidArr.slice(i, i + 50);
    try {
      const uRows = await listAllRows(tablesDB, CORE_DB, 'users', [
        Query.or([Query.equal('$id', chunk), Query.equal('auth_id', chunk)]),
      ]);
      for (const u of uRows) {
        const rid = String(u.$id || '').trim();
        const aid = String(u.auth_id || '').trim();
        const targets = new Set();
        if (rid && canonicalForVariant.has(rid)) {
          for (const t of canonicalForVariant.get(rid)) targets.add(t);
        }
        if (aid && canonicalForVariant.has(aid)) {
          for (const t of canonicalForVariant.get(aid)) targets.add(t);
        }
        for (const variant of [rid, aid].filter(Boolean)) {
          allLookupIds.add(variant);
          if (!canonicalForVariant.has(variant)) {
            canonicalForVariant.set(variant, new Set());
          }
          for (const t of targets) {
            canonicalForVariant.get(variant).add(t);
          }
        }
      }
    } catch (_) {}
  }

  const lookupList = Array.from(allLookupIds);
  const conflictsMap = new Map(); // requestedUserId -> Set<string>
  const addConflict = (variantUid, text) => {
    const targets = canonicalForVariant.get(variantUid);
    if (!targets) return;
    for (const t of targets) {
      if (!conflictsMap.has(t)) conflictsMap.set(t, new Set());
      conflictsMap.get(t).add(text);
    }
  };

  const blockingEventStatuses = isSelfCheck
    ? new Set([
        'accepted_user',
        'accepted_flight_school',
        'user_requests_change',
        'pending_flight_school',
      ])
    : new Set([
        'accepted_user',
        'accepted_flight_school',
        'user_requests_change',
        'pending_user',
        'pending_flight_school',
      ]);

  const blockingTandemStatuses = isSelfCheck
    ? new Set(['confirmed', 'requested_by_pilot', 'cancellation_requested'])
    : new Set([
        'confirmed',
        'requested_by_pilot',
        'requested_by_admin',
        'cancellation_requested',
      ]);

  // 1) Event-Zuweisungen schulübergreifend prüfen
  for (let i = 0; i < lookupList.length; i += 100) {
    const chunk = lookupList.slice(i, i + 100);
    const assignments = await listAllRows(
      tablesDB,
      SP_DB,
      'team_assignments_events',
      [
        Query.equal('user_id', chunk),
        Query.select([
          '*',
          'events.$id',
          'events.display_name',
          'events.start_time',
          'events.end_time',
          'events.status',
          'events.flight_school_id',
        ]),
      ]
    );

    for (const a of assignments) {
      const uid = String(a.user_id || '').trim();
      const st = String(a.status || '').trim().toLowerCase();
      if (!uid || !blockingEventStatuses.has(st)) continue;

      const ev = a.events && typeof a.events === 'object' ? a.events : null;
      if (!ev) continue;
      const evId = String(ev.$id || '').trim();
      if (ignoreEventId && evId === ignoreEventId) continue;

      const evStatus = String(ev.status || '').trim().toLowerCase();
      if (evStatus === 'canceled') continue;

      const evSchoolId = String(ev.flight_school_id || '').trim();
      const isSameSchool = flightSchoolId && evSchoolId === flightSchoolId;
      if (otherSchoolsOnly && isSameSchool) continue;

      const evStartMs = Date.parse(ev.start_time || '');
      const evEndMs = Date.parse(ev.end_time || '');
      if (!Number.isFinite(evStartMs) || !Number.isFinite(evEndMs)) continue;

      if (evStartMs < reqEndMs && reqStartMs < evEndMs) {
        if (isSelfCheck || isSameSchool) {
          const evName = String(ev.display_name || 'Event').trim();
          const label =
            st === 'pending_flight_school'
              ? `Bereits beworben auf „${evName}“`
              : `Event „${evName}“`;
          addConflict(uid, label);
        } else {
          const range = formatShortDateRangeDe(evStartMs, evEndMs, false);
          addConflict(
            uid,
            `Bereits bei anderer Flugschule verplant (${range})`
          );
        }
      }
    }

    // 2) Tandem-Dienste schulübergreifend prüfen
    const duties = await listAllRows(tablesDB, SP_DB, 'tandem_duties', [
      Query.equal('user_id', chunk),
    ]);

    for (const d of duties) {
      if (ignoreDutyId && d.$id === ignoreDutyId) continue;
      const uid = String(d.user_id || '').trim();
      const st = String(d.status || '').trim().toLowerCase();
      if (!uid || !blockingTandemStatuses.has(st)) continue;

      const dSchoolId = String(d.flight_school_id || '').trim();
      const isSameSchool = flightSchoolId && dSchoolId === flightSchoolId;
      if (otherSchoolsOnly && isSameSchool) continue;

      const dStartMs = Date.parse(d.start_date || '');
      const dEndMs = Date.parse(d.end_date || '');
      if (!Number.isFinite(dStartMs) || !Number.isFinite(dEndMs)) continue;

      if (dStartMs < reqEndMs && reqStartMs < dEndMs) {
        const range = formatShortDateRangeDe(
          dStartMs,
          dEndMs,
          d.is_full_day !== false
        );
        if (isSelfCheck || isSameSchool) {
          addConflict(uid, `Tandem-Einsatz (${range})`);
        } else {
          addConflict(
            uid,
            `Tandem-Einsatz bei anderer Flugschule (${range})`
          );
        }
      }
    }
  }

  const conflictsByUserId = {};
  for (const [uid, set] of conflictsMap.entries()) {
    conflictsByUserId[uid] = Array.from(set);
  }
  return { ok: true, conflictsByUserId };
}

/**
 * Prüft beendete Events einer Flugschule (oder ein einzelnes Event) und setzt
 * `status` automatisch auf `done` („Abgeschlossen“), sobald das Event beendet ist
 * UND alle erforderlichen Checklisten unterschrieben sowie alle erforderlichen
 * Stundenzettel abgesendet wurden.
 */
async function evaluateEventAutoCompletion(
  tablesDB,
  flightSchoolId,
  { eventId = '', callerId = '' } = {}
) {
  const school = await getSchoolRow(tablesDB, flightSchoolId);
  const spDbId = String(school.database_id || SP_DB).trim() || SP_DB;
  const eventsTableId = String(school.events_id || 'events').trim() || 'events';
  const assignmentsTableId =
    String(school.team_assigments_events_id || 'team_assignments_events').trim() ||
    'team_assignments_events';

  const nowMs = Date.now();
  const nowIso = new Date(nowMs).toISOString();

  let candidateEvents = [];
  if (eventId) {
    try {
      const ev = await tablesDB.getRow({
        databaseId: spDbId,
        tableId: eventsTableId,
        rowId: eventId,
      });
      if (String(ev.flight_school_id || '').trim() === flightSchoolId) {
        candidateEvents = [ev];
      }
    } catch (_) {
      return { ok: true, completedEventIds: [] };
    }
  } else {
    candidateEvents = await listAllRows(tablesDB, spDbId, eventsTableId, [
      Query.equal('flight_school_id', flightSchoolId),
      Query.lessThan('end_time', nowIso),
    ]);
  }

  candidateEvents = candidateEvents.filter((ev) => {
    const st = String(ev.status || '').trim().toLowerCase();
    if (st === 'done' || st === 'canceled') return false;
    const endMs = Date.parse(ev.end_time || '');
    return Number.isFinite(endMs) && endMs <= nowMs;
  });

  if (candidateEvents.length === 0) {
    return { ok: true, completedEventIds: [] };
  }

  const timesheetEnabled = school.timesheet_enabled !== false;
  const configuredTsQualIds = parseStringList(school.timesheet_qualification_ids);

  const [teamRoles, qualifications, memberships, completions, timesheets] =
    await Promise.all([
      listAllRows(tablesDB, CORE_DB, 'team_roles', [
        Query.equal('flight_school_id', flightSchoolId),
      ]),
      listAllRows(tablesDB, CORE_DB, 'qualifications', [
        Query.equal('flight_school_id', flightSchoolId),
      ]),
      listAllRows(tablesDB, CORE_DB, 'memberships', [
        Query.equal('flightSchools', flightSchoolId),
        Query.select(['*', 'users.$id', 'users.auth_id']),
      ]),
      listAllRows(
        tablesDB,
        spDbId,
        'checklist_completions',
        eventId
          ? [Query.equal('event_id', eventId)]
          : [Query.equal('flight_school_id', flightSchoolId)]
      ),
      timesheetEnabled
        ? listAllRows(
            tablesDB,
            spDbId,
            'event_timesheets',
            eventId
              ? [Query.equal('event_id', eventId)]
              : [Query.equal('flight_school_id', flightSchoolId)]
          )
        : Promise.resolve([]),
    ]);

  // Rollen -> Checklist-ID Mapping
  const roleChecklistMap = new Map();
  for (const r of teamRoles) {
    const name = String(r.name || '').trim().toLowerCase();
    const cid = String(r.checklist_id || '').trim();
    if (name && cid) {
      roleChecklistMap.set(name, cid);
    }
  }
  const roleHasChecklist = (rawRole) => {
    const lower = String(rawRole || '').trim().toLowerCase();
    const labelLower = normalizeRoleLabel(rawRole).toLowerCase();
    return roleChecklistMap.has(lower) || roleChecklistMap.has(labelLower);
  };

  // Effektive Stundenzettel-Qualifikationen
  const effectiveTsQualIds = new Set(
    configuredTsQualIds.length > 0
      ? configuredTsQualIds
      : qualifications
          .filter((q) => isDefaultTimesheetQualificationName(q.name))
          .map((q) => String(q.$id || '').trim())
          .filter(Boolean)
  );

  // Mitglieder-ID-Mapping (sowohl auth_id als auch users.$id) -> Qualifikations-IDs + alle ID-Varianten
  const memberInfoByAnyId = new Map();
  for (const m of memberships) {
    if (m.status === 'inactive') continue;
    const authId = extractUserAuthId(m.users);
    const rowId = extractUserRowId(m.users);
    const qualIds = parseStringList(m.qualifications);
    const ids = Array.from(new Set([authId, rowId].filter(Boolean)));
    const info = { ids, qualIds };
    for (const id of ids) {
      memberInfoByAnyId.set(id, info);
    }
  }

  const memberRequiresTimesheet = (userId) => {
    if (!timesheetEnabled) return false;
    const info = memberInfoByAnyId.get(userId);
    if (!info || info.qualIds.length === 0) return false;
    for (const qId of info.qualIds) {
      if (effectiveTsQualIds.has(qId)) return true;
    }
    if (configuredTsQualIds.length === 0 && qualifications.length === 0) {
      return info.qualIds.some(isDefaultTimesheetQualificationName);
    }
    return false;
  };

  // Signierte Checklisten indizieren
  const signedAssignmentIds = new Set();
  const signedEventUserPairs = new Set();
  for (const c of completions) {
    if (String(c.status || '').trim().toLowerCase() !== 'signed') continue;
    const aid = String(c.assignment_id || '').trim();
    const eid = String(c.event_id || '').trim();
    const uid = String(c.user_id || '').trim();
    if (aid) signedAssignmentIds.add(aid);
    if (eid && uid) signedEventUserPairs.add(`${eid}|${uid}`);
  }

  // Abgesendete Stundenzettel indizieren
  const submittedAssignmentIds = new Set();
  const submittedEventUserPairs = new Set();
  for (const s of timesheets) {
    if (String(s.status || '').trim().toLowerCase() !== 'submitted') continue;
    const aid = String(s.assignment_id || '').trim();
    const eid = String(s.event_id || '').trim();
    const uid = String(s.user_id || '').trim();
    if (aid) submittedAssignmentIds.add(aid);
    if (eid && uid) submittedEventUserPairs.add(`${eid}|${uid}`);
  }

  // Team-Zuweisungen für alle Kandidaten-Events in 100er-Chunks laden
  const assignmentsByEventId = new Map();
  const candidateIds = candidateEvents.map((e) => e.$id);
  for (let i = 0; i < candidateIds.length; i += 100) {
    const chunk = candidateIds.slice(i, i + 100);
    const rows = await listAllRows(tablesDB, spDbId, assignmentsTableId, [
      Query.equal('events', chunk),
      Query.select(['*', 'events.$id']),
    ]);
    for (const row of rows) {
      const rawEv = row.events;
      const evId =
        rawEv && typeof rawEv === 'object'
          ? String(rawEv.$id || '').trim()
          : String(rawEv || '').trim();
      if (!evId) continue;
      if (!assignmentsByEventId.has(evId)) assignmentsByEventId.set(evId, []);
      assignmentsByEventId.get(evId).push(row);
    }
  }

  const bindingStatuses = new Set([
    'accepted_user',
    'accepted_flight_school',
    'user_requests_change',
  ]);

  const completedEventIds = [];

  for (const ev of candidateEvents) {
    const assignments = assignmentsByEventId.get(ev.$id) || [];
    let allSatisfied = true;

    for (const a of assignments) {
      const uid = String(a.user_id || '').trim();
      const st = String(a.status || '').trim().toLowerCase();
      if (!uid || uid.startsWith('slot_') || !bindingStatuses.has(st)) {
        continue;
      }

      const memberIds = memberInfoByAnyId.get(uid)?.ids || [uid];

      // 1) Checkliste prüfen
      if (roleHasChecklist(a.role)) {
        const hasChecklist =
          signedAssignmentIds.has(a.$id) ||
          memberIds.some((mid) => signedEventUserPairs.has(`${ev.$id}|${mid}`));
        if (!hasChecklist) {
          allSatisfied = false;
          break;
        }
      }

      // 2) Stundenzettel prüfen
      if (memberRequiresTimesheet(uid)) {
        const hasTimesheet =
          submittedAssignmentIds.has(a.$id) ||
          memberIds.some((mid) =>
            submittedEventUserPairs.has(`${ev.$id}|${mid}`)
          );
        if (!hasTimesheet) {
          allSatisfied = false;
          break;
        }
      }
    }

    if (allSatisfied) {
      try {
        await tablesDB.updateRow({
          databaseId: spDbId,
          tableId: eventsTableId,
          rowId: ev.$id,
          data: { status: 'done' },
        });
        completedEventIds.push(ev.$id);
        await writeAuditLog(tablesDB, {
          flightSchoolId,
          userId: callerId || 'system',
          action: 'Event automatisch abgeschlossen',
          details: `Event „${ev.display_name || ev.$id}“ beendet – alle Checklisten und Stundenzettel vollständig.`,
        });
      } catch (_) {}
    }
  }

  return { ok: true, completedEventIds };
}

/**
 * Monatlicher DSGVO-Löschlauf (Retention nach Art. 5 Abs. 1 lit. e DSGVO):
 * - Audit-Logs älter als 24 Monate löschen
 * - Unbestätigte, verwaiste OTP-Auth-Accounts älter als 30 Tage ohne Profil bereinigen
 */
async function runRetentionCleanup(tablesDB, usersApi, log) {
  const now = Date.now();
  const auditCutoff = new Date(now - 730 * 24 * 60 * 60 * 1000).toISOString();
  const staleUserCutoffMs = now - 30 * 24 * 60 * 60 * 1000;

  let deletedAuditLogs = 0;
  try {
    const oldLogs = await listAllRows(tablesDB, SP_DB, 'audit_logs', [
      Query.lessThan('timestamp', auditCutoff),
    ]);
    for (const row of oldLogs) {
      try {
        await tablesDB.deleteRow({
          databaseId: SP_DB,
          tableId: 'audit_logs',
          rowId: row.$id,
        });
        deletedAuditLogs++;
      } catch (_) {}
    }
  } catch (e) {
    log(`audit_logs retention warning: ${e}`);
  }

  let deletedStaleAccounts = 0;
  try {
    const authUsers = await listAllAuthUsers(usersApi);
    for (const u of authUsers) {
      if (u.emailVerification === true) continue;
      if (u.passwordUpdate && String(u.passwordUpdate).trim() !== '') continue;
      const regMs = Date.parse(u.registration || u.$createdAt || '');
      if (!Number.isFinite(regMs) || regMs > staleUserCutoffMs) continue;
      const profileRow = await getUserRowByAuthId(tablesDB, u.$id);
      if (profileRow) continue;
      try {
        await usersApi.delete({ userId: u.$id });
        deletedStaleAccounts++;
      } catch (_) {}
    }
  } catch (e) {
    log(`stale auth users retention warning: ${e}`);
  }

  return { ok: true, deletedAuditLogs, deletedStaleAccounts };
}

export default async ({ req, res, log, error }) => {
  try {
    const apiKey =
      req.headers?.['x-appwrite-key'] || process.env.APPWRITE_API_KEY || '';
    const client = new Client()
      .setEndpoint(
        process.env.APPWRITE_FUNCTION_API_ENDPOINT ||
          'https://appwrite.tragegurt.com/v1'
      )
      .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || 'tragegurt')
      .setKey(apiKey);

    const tablesDB = new TablesDB(client);
    const storage = new Storage(client);
    const teams = new Teams(client);
    const usersApi = new Users(client);

    // Geplanter Cron-Trigger (Retention Cleanup)
    const trigger = (req.headers?.['x-appwrite-trigger'] || '').toLowerCase();
    if (trigger === 'schedule') {
      const result = await runRetentionCleanup(tablesDB, usersApi, log);
      log(`Retention cleanup done: ${JSON.stringify(result)}`);
      return res.json(result, 200);
    }

    const payload =
      typeof req.body === 'string'
        ? JSON.parse(req.body || '{}')
        : (req.body || {});
    const action = String(payload.action || '').trim();
    const callerId = String(req.headers?.['x-appwrite-user-id'] || '').trim();

    if (!callerId) {
      return res.json({ ok: false, error: 'Nicht authentifiziert.' }, 401);
    }

    switch (action) {
      case 'syncSchoolTeam': {
        const flightSchoolId = String(payload.flightSchoolId || '').trim();
        if (!flightSchoolId) {
          return res.json({ ok: false, error: 'flightSchoolId fehlt.' }, 400);
        }
        const allowed = await isActiveSchoolMember(tablesDB, flightSchoolId, callerId);
        // Auch erlauben, wenn der Nutzer gerade erst eine Beitrittsanfrage gestellt hat
        if (!allowed) {
          await syncUserRowPermissions(tablesDB, callerId);
          return res.json({ ok: true, syncedUserOnly: true }, 200);
        }
        const result = await syncSchoolTeam(tablesDB, teams, flightSchoolId);
        return res.json({ ok: true, ...result }, 200);
      }

      case 'syncDocumentPermissions': {
        const documentId = String(payload.documentId || '').trim();
        if (!documentId) {
          return res.json({ ok: false, error: 'documentId fehlt.' }, 400);
        }
        const doc = await tablesDB.getRow({
          databaseId: CORE_DB,
          tableId: 'qualification_documents',
          rowId: documentId,
        });
        const ownerId = String(doc.user_id || '').trim();
        const userRow = await getUserRowByAuthId(tablesDB, callerId);
        const isOwner = ownerId === callerId || ownerId === userRow?.$id;
        if (!isOwner) {
          return res.json({ ok: false, error: 'Keine Berechtigung für dieses Dokument.' }, 403);
        }
        const result = await syncDocumentPermissions(tablesDB, storage, documentId);
        return res.json(result, 200);
      }

      case 'revokeSchoolAccess': {
        const flightSchoolId = String(payload.flightSchoolId || '').trim();
        const targetUserId = String(payload.targetUserId || callerId).trim();
        if (!flightSchoolId || !targetUserId) {
          return res.json({ ok: false, error: 'flightSchoolId/targetUserId fehlt.' }, 400);
        }
        const userRow = await getUserRowByAuthId(tablesDB, callerId);
        const isSelf = targetUserId === callerId || targetUserId === userRow?.$id;
        const isAdmin = await isSchoolAdmin(tablesDB, flightSchoolId, callerId);
        if (!isSelf && !isAdmin) {
          return res.json({ ok: false, error: 'Keine Berechtigung.' }, 403);
        }
        const result = await revokeSchoolAccess(
          tablesDB,
          storage,
          teams,
          flightSchoolId,
          targetUserId
        );
        return res.json(result, 200);
      }

      case 'getTeamPublicProfiles': {
        const flightSchoolIds = Array.isArray(payload.flightSchoolIds)
          ? payload.flightSchoolIds.map((x) => String(x || '').trim()).filter(Boolean)
          : [];
        if (flightSchoolIds.length === 0) {
          return res.json({ ok: true, profiles: {} }, 200);
        }
        const profiles = {};
        for (const sid of flightSchoolIds) {
          const allowed = await isActiveSchoolMember(tablesDB, sid, callerId);
          if (!allowed) continue;
          const memberships = await listAllRows(tablesDB, CORE_DB, 'memberships', [
            Query.equal('flightSchools', sid),
            Query.select(['*', 'users.$id', 'users.auth_id', 'users.name', 'users.avatar_url']),
          ]);
          for (const m of memberships) {
            if (m.status !== 'active') continue;
            const u = m.users;
            if (!u || typeof u !== 'object') continue;
            const entry = {
              name: String(u.name || '').trim(),
              avatarUrl: String(u.avatar_url || '').trim(),
            };
            if (u.$id) profiles[String(u.$id)] = entry;
            if (u.auth_id) profiles[String(u.auth_id)] = entry;
          }
        }
        return res.json({ ok: true, profiles }, 200);
      }

      case 'adminAction': {
        const flightSchoolId = String(payload.flightSchoolId || '').trim();
        const operation = String(payload.operation || '').trim();
        if (!flightSchoolId || !operation) {
          return res.json({ ok: false, error: 'flightSchoolId/operation fehlt.' }, 400);
        }
        const adminOk = await isSchoolAdmin(tablesDB, flightSchoolId, callerId);
        if (!adminOk) {
          return res.json({ ok: false, error: 'Nur Flugschul-Admins erlaubt.' }, 403);
        }
        const school = await getSchoolRow(tablesDB, flightSchoolId);
        const subActive = String(school.subscription_status || 'active') === 'active';

        if (operation === 'updateAdmins') {
          const adminUserIds = Array.isArray(payload.adminUserIds)
            ? payload.adminUserIds.map((x) => String(x || '').trim()).filter(Boolean)
            : [];
          if (adminUserIds.length === 0) {
            return res.json({ ok: false, error: 'Mindestens ein Admin erforderlich.' }, 400);
          }
          await tablesDB.updateRow({
            databaseId: CORE_DB,
            tableId: 'flight_schools',
            rowId: flightSchoolId,
            data: { admin_users: adminUserIds },
          });
          await syncSchoolTeam(tablesDB, teams, flightSchoolId);
          await writeAuditLog(tablesDB, {
            flightSchoolId,
            userId: callerId,
            action: 'Admins aktualisiert',
            details: `${adminUserIds.length} Admin(s) hinterlegt`,
          });
          return res.json({ ok: true }, 200);
        }

        if (operation === 'approveJoinRequest') {
          if (!subActive) {
            return res.json({ ok: false, error: 'Flugschul-Abo nicht aktiv.' }, 403);
          }
          const membershipId = String(payload.membershipId || '').trim();
          const memberName = String(payload.memberName || '').trim();
          await tablesDB.updateRow({
            databaseId: CORE_DB,
            tableId: 'memberships',
            rowId: membershipId,
            data: { status: 'active' },
          });
          await syncSchoolTeam(tablesDB, teams, flightSchoolId);
          await writeAuditLog(tablesDB, {
            flightSchoolId,
            userId: callerId,
            action: 'Beitrittsanfrage angenommen',
            details: `Teammitglied „${memberName}“ aufgenommen`,
          });
          return res.json({ ok: true }, 200);
        }

        if (operation === 'rejectJoinRequest') {
          if (!subActive) {
            return res.json({ ok: false, error: 'Flugschul-Abo nicht aktiv.' }, 403);
          }
          const membershipId = String(payload.membershipId || '').trim();
          const memberName = String(payload.memberName || '').trim();
          const targetUserId = String(payload.targetUserId || '').trim();
          await tablesDB.deleteRow({
            databaseId: CORE_DB,
            tableId: 'memberships',
            rowId: membershipId,
          });
          if (targetUserId) {
            await revokeSchoolAccess(tablesDB, storage, teams, flightSchoolId, targetUserId);
          }
          await writeAuditLog(tablesDB, {
            flightSchoolId,
            userId: callerId,
            action: 'Beitrittsanfrage abgelehnt',
            details: `Anfrage von „${memberName}“ abgelehnt`,
          });
          return res.json({ ok: true }, 200);
        }

        if (operation === 'reviewApproval') {
          const approvalId = String(payload.approvalId || '').trim();
          const decision = String(payload.decision || '').trim();
          const comment = String(payload.comment || '').trim();
          if (!['approved', 'rejected'].includes(decision)) {
            return res.json({ ok: false, error: 'Ungültige Entscheidung.' }, 400);
          }
          const approval = await tablesDB.getRow({
            databaseId: CORE_DB,
            tableId: 'qualification_approvals',
            rowId: approvalId,
          });
          if (String(approval.flight_school_id || '') !== flightSchoolId) {
            return res.json({ ok: false, error: 'Freigabe gehört zu einer anderen Schule.' }, 403);
          }
          await tablesDB.updateRow({
            databaseId: CORE_DB,
            tableId: 'qualification_approvals',
            rowId: approvalId,
            data: {
              status: decision,
              reviewed_by: callerId,
              reviewed_at: new Date().toISOString(),
              comment,
            },
          });
          await writeAuditLog(tablesDB, {
            flightSchoolId,
            userId: callerId,
            action: decision === 'approved' ? 'Qualifikation bestätigt' : 'Qualifikation abgelehnt',
            details: `Dokumenttyp „${approval.document_type || ''}“ für Nutzer ${approval.user_id || ''}${comment ? ` (${comment})` : ''}`,
          });
          return res.json({ ok: true }, 200);
        }

        if (operation === 'approveSwap') {
          if (!subActive) {
            return res.json({ ok: false, error: 'Flugschul-Abo nicht aktiv.' }, 403);
          }
          const assignmentId = String(payload.assignmentId || '').trim();
          const newUserId = String(payload.newUserId || '').trim();
          const newUserName = String(payload.newUserName || '').trim();
          const eventName = String(payload.eventName || '').trim();
          await tablesDB.updateRow({
            databaseId: school.database_id || SP_DB,
            tableId: school.team_assigments_events_id || 'team_assignments_events',
            rowId: assignmentId,
            data: {
              user_id: newUserId,
              name: newUserName,
              status: 'accepted_flight_school',
              swap_offered: false,
              swap_requested_by: '',
              swap_requested_by_name: '',
            },
          });
          await writeAuditLog(tablesDB, {
            flightSchoolId,
            userId: callerId,
            action: 'Platztausch genehmigt',
            details: `Event „${eventName}“ an ${newUserName} übergeben`,
          });
          return res.json({ ok: true }, 200);
        }

        return res.json({ ok: false, error: `Unbekannte Admin-Aktion: ${operation}` }, 400);
      }

      case 'checkCrossSchoolConflicts': {
        const flightSchoolId = String(payload.flightSchoolId || '').trim();
        const userIds = Array.isArray(payload.userIds)
          ? payload.userIds.map((x) => String(x || '').trim()).filter(Boolean)
          : [];
        const startTime = String(payload.startTime || '').trim();
        const endTime = String(payload.endTime || '').trim();
        const ignoreEventId = String(payload.ignoreEventId || '').trim();
        const ignoreDutyId = String(payload.ignoreDutyId || '').trim();
        const otherSchoolsOnly = payload.otherSchoolsOnly === true;

        const callerRow = await getUserRowByAuthId(tablesDB, callerId);
        const callerIds = new Set(
          [callerId, callerRow?.$id, callerRow?.auth_id].filter(Boolean)
        );
        const isSelfCheck =
          userIds.length > 0 && userIds.every((id) => callerIds.has(id));

        if (!isSelfCheck) {
          if (!flightSchoolId) {
            return res.json({ ok: false, error: 'flightSchoolId fehlt.' }, 400);
          }
          const adminOk = await isSchoolAdmin(tablesDB, flightSchoolId, callerId);
          if (!adminOk) {
            return res.json(
              { ok: false, error: 'Nur Flugschul-Admins erlaubt.' },
              403
            );
          }
        }

        const result = await checkCrossSchoolConflicts(tablesDB, {
          flightSchoolId,
          userIds,
          startTime,
          endTime,
          ignoreEventId,
          ignoreDutyId,
          otherSchoolsOnly: isSelfCheck ? false : otherSchoolsOnly,
          isSelfCheck,
        });
        return res.json(result, 200);
      }

      case 'checkEventCompletion': {
        const flightSchoolId = String(payload.flightSchoolId || '').trim();
        const eventId = String(payload.eventId || '').trim();
        if (!flightSchoolId) {
          return res.json({ ok: false, error: 'flightSchoolId fehlt.' }, 400);
        }
        const allowed = await isActiveSchoolMember(
          tablesDB,
          flightSchoolId,
          callerId
        );
        if (!allowed) {
          return res.json({ ok: false, error: 'Keine Berechtigung.' }, 403);
        }
        const result = await evaluateEventAutoCompletion(
          tablesDB,
          flightSchoolId,
          { eventId, callerId }
        );
        return res.json(result, 200);
      }

      case 'exportMyData': {
        const data = await exportUserData(tablesDB, usersApi, callerId);
        return res.json({ ok: true, data }, 200);
      }

      case 'deleteMyAccount': {
        const confirmEmail = String(payload.confirmEmail || '').trim();
        const result = await deleteUserAccount(
          tablesDB,
          storage,
          teams,
          usersApi,
          callerId,
          confirmEmail
        );
        return res.json(result, result.status || (result.ok ? 200 : 400));
      }

      default:
        return res.json({ ok: false, error: `Unbekannte Aktion: ${action}` }, 400);
    }
  } catch (e) {
    error(String(e?.stack || e));
    return res.json({ ok: false, error: e?.message || 'Interner Serverfehler.' }, 500);
  }
};
