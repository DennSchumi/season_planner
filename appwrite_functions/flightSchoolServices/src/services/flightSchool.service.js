import { createAppwrite } from "../appwrite/client.js";
import { requireString } from "../utils/validate.js";
import { Query, ID } from "node-appwrite";


export async function inviteUserToFlightSchool({ flightSchoolId, userMail }) {
  const fsId = requireString(flightSchoolId, "flightSchoolId");
  const mail = requireString(userMail, "userMail").toLowerCase().trim();

  const MAIN_DATABASE_ID = process.env.MAIN_DATABASE_ID;
  const MEMBERSHIPS_COLLECTION_ID = process.env.MEMBERSHIPS_COLLECTION_ID;

  if (!MAIN_DATABASE_ID || !MEMBERSHIPS_COLLECTION_ID) {
    throw new Error("Missing MAIN_DATABASE_ID / MEMBERSHIPS_COLLECTION_ID in function variables.");
  }

  const { databases, users } = createAppwrite();

  // 1) Auth user by email suchen
  // Appwrite Users API: users.list([Query.equal("email", [mail])])
  const list = await users.list([
    Query.equal("email", [mail]),
    Query.limit(1),
  ]);

  if (!list.users || list.users.length === 0) {
    // Du wolltest "User-ID herausfinden" -> wenn nicht gefunden: Fehler
    throw new Error(`No Auth user found for email: ${mail}`);
    // Alternative (wenn du Invite ohne bestehenden User erlauben willst):
    // userId = null und invitedEmail speichern (kannst du später easy erweitern)
  }

  const authUser = list.users[0];
  const userId = authUser.$id;

  // 2) Optional: duplizierte Membership verhindern
  // Achtung: bei Relations ist der Query je nach Schema:
  // meistens Query.equal("users", [userId]) und Query.equal("flightSchools", [fsId])
  // (genau so wie dein membershipsRes zeigt: "users": { ... }, "flightSchools": { ... })
  const existing = await databases.listDocuments(
    MAIN_DATABASE_ID,
    MEMBERSHIPS_COLLECTION_ID,
    [
      Query.equal("users", [userId]),
      Query.equal("flightSchools", [fsId]),
      Query.limit(1),
    ]
  );

  if (existing.total && existing.total > 0) {
    return {
      ok: true,
      alreadyExists: true,
      membershipId: existing.documents[0].$id,
      userId,
      email: authUser.email ?? mail,
    };
  }

  // 3) Membership anlegen
  // Relations: einfach die IDs setzen
  const created = await databases.createDocument(
    MAIN_DATABASE_ID,
    MEMBERSHIPS_COLLECTION_ID,
    ID.unique(),
    {
      users: userId,
      flightSchools: fsId,
      roles: [],
      status: "invited",
    }
  );

  return {
    ok: true,
    membershipId: created.$id,
    userId,
    email: authUser.email ?? mail,
    name: authUser.name ?? "",
  };
}

export async function getMembersWithAuth({ flightSchoolId }) {
  const fsId = requireString(flightSchoolId, "flightSchoolId");

  const MAIN_DATABASE_ID = process.env.MAIN_DATABASE_ID;
  const MEMBERSHIPS_COLLECTION_ID = process.env.MEMBERSHIPS_COLLECTION_ID;

  if (!MAIN_DATABASE_ID || !MEMBERSHIPS_COLLECTION_ID) {
    throw new Error("Missing MAIN_DATABASE_ID / MEMBERSHIPS_COLLECTION_ID in function variables.");
  }

  const { databases, users } = createAppwrite();

  const membershipsRes = await databases.listDocuments(
    MAIN_DATABASE_ID,
    MEMBERSHIPS_COLLECTION_ID,
    [
      Query.equal("flightSchools", [fsId]),
      Query.limit(200),
    ]
  );

  const memberships = membershipsRes.documents.map((d) => {
    const userRel = d.users;          
    const fsRel = d.flightSchools;    

    const authUserId = userRel?.$id ? String(userRel.$id) : "";

    return {
      membershipId: d.$id,
      authUserId,
      userDocId: userRel?.$id ? String(userRel.$id) : null,
      flightSchoolDocId: fsRel?.$id ? String(fsRel.$id) : null,
      roles: Array.isArray(d.roles) ? d.roles.map(String) : [],
      status: String(d.status ?? ""),
    };
  });

  const uniqueAuthIds = [...new Set(memberships.map(m => m.authUserId).filter(Boolean))];

  const authUsersArr = await Promise.all(
    uniqueAuthIds.map(async (uid) => {
      try {
        const u = await users.get(uid);
        return {
          id: u.$id,
          name: u.name ?? "",
          email: u.email ?? "",
          phone: u.phone ?? "",
        };
      } catch {
        return { id: uid, name: "", email: "", phone: "", missing: true };
      }
    })
  );

  const authById = new Map(authUsersArr.map(u => [u.id, u]));

  const result = memberships.map((m) => {
    const auth = m.authUserId ? authById.get(m.authUserId) : null;

    return {
      userId: m.authUserId,
      name: auth?.name ?? "",
      email: auth?.email ?? "",
      phone: auth?.phone ?? "",
      membership: {
        id: m.membershipId,
        roles: m.roles,
        status: m.status,
      },
      flags: {
        missingAuthUser: Boolean(auth?.missing),
      },
    };
  });

  return result;
}
