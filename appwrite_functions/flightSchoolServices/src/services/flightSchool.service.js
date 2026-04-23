import { createAppwrite } from "../../src/appwrite/client.js";
import { Query } from "node-appwrite";

const MAIN_DATABASE_ID = process.env.MAIN_DATABASE_ID;
const FLIGHT_SCHOOLS_COLLECTION_ID = process.env.FLIGHT_SCHOOLS_COLLECTION_ID;
const MEMBERSHIPS_COLLECTION_ID = process.env.MEMBERSHIPS_COLLECTION_ID;
const USERS_COLLECTION_ID = process.env.USERS_COLLECTION_ID;
const EVENTS_COLLECTION_ID = process.env.EVENTS_COLLECTION_ID;
const TEAM_ASSIGNMENTS_COLLECTION_ID = process.env.TEAM_ASSIGNMENTS_COLLECTION_ID;

const { users, databases } = createAppwrite();

export async function getFlightSchoolAdminView({ flightSchoolId }) {
  if (!flightSchoolId) {
    return { ok: false, error: "FLIGHT_SCHOOL_ID_REQUIRED" };
  }

  try {
    const fsDoc = await databases.getDocument(
      MAIN_DATABASE_ID,
      FLIGHT_SCHOOLS_COLLECTION_ID,
      flightSchoolId
    );

    const fs = getDocumentData(fsDoc);

    const members = await getMembersWithAuth({ flightSchoolId });
    const events = await getFlightSchoolEvents({ flightSchoolId });

    return {
      ok: true,
      flightSchool: {
        id: fsDoc.$id,
        displayName: fs.display_name ?? "",
        displayShortName: fs.display_short_name ?? "",
        databaseId: fs.database_id ?? "",
        teamAssignmentsEventsCollectionId: fs.team_assigments_events_id ?? "",
        eventsCollectionId: fs.events_id ?? "",
        auditLogsCollectionId: fs.audit_logs_id ?? "",
        logoLink: fs.logo_link ?? "",
        logoId: fs.logo_id ?? "",
        adminUserIds: Array.isArray(fs.admin_users) ? fs.admin_users : [],
        settings: fs.settings ?? {},
        members,
        events,
      },
    };
  } catch (error) {
    console.log("getFlightSchoolAdminView error", error?.message);
    return { ok: false, error: "FLIGHT_SCHOOL_LOAD_FAILED" };
  }
}

export async function getMembersWithAuth({ flightSchoolId }) {
  const membershipDocs = await databases.listDocuments(
    MAIN_DATABASE_ID,
    MEMBERSHIPS_COLLECTION_ID,
    [
      Query.equal("flightSchools", [flightSchoolId]),
      Query.limit(500),
    ]
  );

  const result = [];

  for (const membershipDoc of membershipDocs.documents ?? []) {
    const membership = getDocumentData(membershipDoc);
    const userId = extractUserIdFromMembership(membership);

    let authUser = null;
    if (userId) {
      try {
        authUser = await users.get(userId);
      } catch (_) {
        authUser = null;
      }
    }

    result.push({
      userId: userId ?? "",
      name: authUser?.name ?? "",
      email: authUser?.email ?? "",
      phone: authUser?.phone ?? "",
      membership: {
        id: membershipDoc.$id,
        roles: Array.isArray(membership.roles) ? membership.roles : [],
        status: membership.status ?? "",
      },
    });
  }

  return result;
}

export async function inviteUserToFlightSchool({
  flightSchoolId,
  userMail,
  roles,
}) {
  try {
    const userList = await users.list([
      Query.equal("email", [userMail]),
      Query.limit(1),
    ]);

    const authUser = userList.users?.[0];
    if (!authUser) {
      return { ok: false, error: "USER_NOT_FOUND" };
    }

    const existingMemberships = await databases.listDocuments(
      MAIN_DATABASE_ID,
      MEMBERSHIPS_COLLECTION_ID,
      [
        Query.equal("users", [authUser.$id]),
        Query.equal("flightSchools", [flightSchoolId]),
        Query.limit(1),
      ]
    );

    if ((existingMemberships.documents ?? []).isNotEmpty) {
      return { ok: false, error: "MEMBERSHIP_ALREADY_EXISTS" };
    }

    const created = await databases.createDocument(
      MAIN_DATABASE_ID,
      MEMBERSHIPS_COLLECTION_ID,
      "unique()",
      {
        users: authUser.$id,
        flightSchools: flightSchoolId,
        roles: Array.isArray(roles) ? roles : [],
        status: "pending",
      }
    );

    return {
      ok: true,
      membershipId: created.$id,
    };
  } catch (error) {
    console.log("inviteUserToFlightSchool error", error?.message);
    return { ok: false, error: "INVITE_FAILED" };
  }
}

export async function updateFlightSchoolAdmins({
  flightSchoolId,
  adminUserIds,
}) {
  try {
    const updated = await databases.updateDocument(
      MAIN_DATABASE_ID,
      FLIGHT_SCHOOLS_COLLECTION_ID,
      flightSchoolId,
      {
        admin_users: adminUserIds,
      }
    );

    return {
      ok: true,
      flightSchoolId: updated.$id,
    };
  } catch (error) {
    console.log("updateFlightSchoolAdmins error", error?.message);
    return { ok: false, error: "UPDATE_ADMINS_FAILED" };
  }
}

export async function removeMemberFromFlightSchool({ membershipId }) {
  try {
    await databases.deleteDocument(
      MAIN_DATABASE_ID,
      MEMBERSHIPS_COLLECTION_ID,
      membershipId
    );

    return { ok: true };
  } catch (error) {
    console.log("removeMemberFromFlightSchool error", error?.message);
    return { ok: false, error: "REMOVE_MEMBER_FAILED" };
  }
}

export async function updateMemberRoles({ membershipId, roles }) {
  try {
    const updated = await databases.updateDocument(
      MAIN_DATABASE_ID,
      MEMBERSHIPS_COLLECTION_ID,
      membershipId,
      {
        roles,
      }
    );

    return {
      ok: true,
      membershipId: updated.$id,
    };
  } catch (error) {
    console.log("updateMemberRoles error", error?.message);
    return { ok: false, error: "UPDATE_MEMBER_ROLES_FAILED" };
  }
}

export async function getFlightSchoolEvents({ flightSchoolId }) {
  try {
    const eventsResult = await databases.listDocuments(
      MAIN_DATABASE_ID,
      EVENTS_COLLECTION_ID,
      [
        Query.equal("flightSchoolId", [flightSchoolId]),
        Query.orderDesc("start_time"),
        Query.limit(200),
      ]
    );

    const events = [];

    for (const eventDoc of eventsResult.documents ?? []) {
      const eventData = getDocumentData(eventDoc);

      const teamDocs = await databases.listDocuments(
        MAIN_DATABASE_ID,
        TEAM_ASSIGNMENTS_COLLECTION_ID,
        [
          Query.equal("flightSchoolId", [flightSchoolId]),
          Query.equal("events", [eventDoc.$id]),
          Query.limit(200),
        ]
      );

      const team = (teamDocs.documents ?? []).map((doc) => {
        const d = getDocumentData(doc);
        return {
          id: doc.$id,
          userId: d.user_id ?? "",
          role: d.role ?? "",
          status: d.status ?? "",
          name: d.name ?? "",
        };
      });

      events.push({
        id: eventDoc.$id,
        flightSchoolId,
        identifier: eventData.identifier ?? "",
        status: eventData.status ?? "",
        startTime: eventData.start_time ?? null,
        endTime: eventData.end_time ?? null,
        displayName: eventData.display_name ?? "",
        location: eventData.location ?? "",
        notes: eventData.notes ?? "",
        team: team,
      });
    }

    return events;
  } catch (error) {
    console.log("getFlightSchoolEvents error", error?.message);
    return [];
  }
}

function getDocumentData(doc) {
  return doc?.data ?? doc ?? {};
}

function extractUserIdFromMembership(membership) {
  const usersField = membership.users;

  if (!usersField) return null;
  if (typeof usersField === "string") return usersField;
  if (typeof usersField === "object" && usersField.$id) return usersField.$id;

  return null;
}