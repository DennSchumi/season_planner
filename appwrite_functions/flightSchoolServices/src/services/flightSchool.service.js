import { ID, Query } from "node-appwrite";
import { createAppwrite } from "../../src/appwrite/client.js";

const MAIN_DATABASE_ID = process.env.MAIN_DATABASE_ID;
const FLIGHT_SCHOOLS_COLLECTION_ID = process.env.FLIGHT_SCHOOLS_COLLECTION_ID;
const MEMBERSHIPS_COLLECTION_ID = process.env.MEMBERSHIPS_COLLECTION_ID;
const EVENTS_COLLECTION_ID = process.env.EVENTS_COLLECTION_ID;
const TEAM_ASSIGNMENTS_COLLECTION_ID = process.env.TEAM_ASSIGNMENTS_COLLECTION_ID;

const { users, databases } = createAppwrite();

export async function getFlightSchoolAdminView({ flightSchoolId, context } = {}) {
  logInfo(context, "getFlightSchoolAdminView:start");

  logJson(context, "env", {
    MAIN_DATABASE_ID,
    FLIGHT_SCHOOLS_COLLECTION_ID,
    MEMBERSHIPS_COLLECTION_ID,
    EVENTS_COLLECTION_ID,
    TEAM_ASSIGNMENTS_COLLECTION_ID,
    flightSchoolId,
  });

  if (!flightSchoolId) {
    logErrorMessage(context, "FLIGHT_SCHOOL_ID_REQUIRED");
    return { ok: false, error: "FLIGHT_SCHOOL_ID_REQUIRED" };
  }

  try {
    requireEnv(MAIN_DATABASE_ID, "MAIN_DATABASE_ID");
    requireEnv(FLIGHT_SCHOOLS_COLLECTION_ID, "FLIGHT_SCHOOLS_COLLECTION_ID");

    const fsDoc = await databases.getDocument(
      MAIN_DATABASE_ID,
      FLIGHT_SCHOOLS_COLLECTION_ID,
      flightSchoolId
    );

    logJson(context, "fsDoc_meta", {
      id: fsDoc?.$id ?? null,
      keys: Object.keys(fsDoc ?? {}),
    });

    const fs = getDocumentData(fsDoc);

    const members = await getMembersWithAuth({ flightSchoolId, context });
    const events = await getFlightSchoolEvents({ flightSchoolId, context });

    const result = {
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
        settings: isPlainObject(fs.settings) ? fs.settings : {},
        members,
        events,
      },
    };

    logJson(context, "getFlightSchoolAdminView:success", {
      flightSchoolId: result.flightSchool.id,
      membersCount: result.flightSchool.members.length,
      eventsCount: result.flightSchool.events.length,
    });

    return result;
  } catch (error) {
    logError(context, "getFlightSchoolAdminView:error", error);
    return { ok: false, error: "FLIGHT_SCHOOL_LOAD_FAILED" };
  }
}

export async function getMembersWithAuth({ flightSchoolId, context } = {}) {
  logJson(context, "getMembersWithAuth:start", {
    flightSchoolId,
    MAIN_DATABASE_ID,
    MEMBERSHIPS_COLLECTION_ID,
  });

  try {
    requireEnv(MAIN_DATABASE_ID, "MAIN_DATABASE_ID");
    requireEnv(MEMBERSHIPS_COLLECTION_ID, "MEMBERSHIPS_COLLECTION_ID");

    const membershipDocs = await databases.listDocuments(
      MAIN_DATABASE_ID,
      MEMBERSHIPS_COLLECTION_ID,
      [
        Query.equal("flightSchools", [flightSchoolId]),
        Query.limit(500),
      ]
    );

    const memberships = membershipDocs?.documents ?? [];

    logJson(context, "getMembersWithAuth:listDocuments:result", {
      total: memberships.length,
    });

    const result = await Promise.all(
      memberships.map(async (membershipDoc, index) => {
        const membership = getDocumentData(membershipDoc);
        const userId = extractUserIdFromMembership(membership);

        logJson(context, "getMembersWithAuth:membership_item", {
          index,
          membershipId: membershipDoc?.$id ?? null,
          userId,
          roles: Array.isArray(membership.roles) ? membership.roles : [],
          status: membership.status ?? "",
        });

        let authUser = null;

        if (userId) {
          try {
            authUser = await users.get(userId);
          } catch (error) {
            logError(context, "getMembersWithAuth:users.get:error", error);
            authUser = null;
          }
        }

        return {
          userId: userId ?? "",
          name: authUser?.name ?? "",
          email: authUser?.email ?? "",
          phone: authUser?.phone ?? "",
          membership: {
            id: membershipDoc.$id,
            roles: Array.isArray(membership.roles) ? membership.roles : [],
            status: membership.status ?? "",
          },
        };
      })
    );

    logJson(context, "getMembersWithAuth:success", {
      count: result.length,
    });

    return result;
  } catch (error) {
    logError(context, "getMembersWithAuth:error", error);
    return [];
  }
}

export async function inviteUserToFlightSchool({
  flightSchoolId,
  userMail,
  roles,
  context,
} = {}) {
  logJson(context, "inviteUserToFlightSchool:start", {
    flightSchoolId,
    userMail,
    roles,
  });

  if (!flightSchoolId) {
    return { ok: false, error: "FLIGHT_SCHOOL_ID_REQUIRED" };
  }

  if (!userMail) {
    return { ok: false, error: "USER_MAIL_REQUIRED" };
  }

  try {
    const userList = await users.list([
      Query.equal("email", [userMail]),
      Query.limit(1),
    ]);

    const authUser = userList?.users?.[0];

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

    if ((existingMemberships?.documents ?? []).length > 0) {
      return { ok: false, error: "MEMBERSHIP_ALREADY_EXISTS" };
    }

    const created = await databases.createDocument(
      MAIN_DATABASE_ID,
      MEMBERSHIPS_COLLECTION_ID,
      ID.unique(),
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
    logError(context, "inviteUserToFlightSchool:error", error);
    return { ok: false, error: "INVITE_FAILED" };
  }
}

export async function createNewEvent({context,
  event
} = {}){
  try{
  const created = await databases.createDocument(
    MAIN_DATABASE_ID,
    EVENTS_COLLECTION_ID,
    ID.unique(),
    {
      flight_school_id: event.flightSchoolId,
      identifier: event.identifier ,
      status: event.status,
      display_name: event.displayName,
      start_time: event.startTime,
      end_time: event.endTime,
      notes: event.notes,
      location: event.location
    }
  );

  for (const tm of event.team ?? []) {
      context?.log?.(`team item: ${JSON.stringify(tm)}`);

      await databases.createDocument(
        MAIN_DATABASE_ID,
        TEAM_ASSIGNMENTS_COLLECTION_ID,
        ID.unique(),
        {
          user_id: tm.user_id ?? "",
          role: tm.role ?? "",
          status: tm.status ?? "",
          events: created.$id,
        }
      );
    }

  return{
    ok: true,
    eventID: created.$id
  }

  }catch(error){
    logError(context, "createNewEvent:error", error);
    return { ok: false, error: "CREATE_EVENT_FAILED" };
  }
 
}

export async function updateFlightSchoolAdmins({
  flightSchoolId,
  adminUserIds,
  context,
} = {}) {
  logJson(context, "updateFlightSchoolAdmins:start", {
    flightSchoolId,
    adminUserIds,
  });

  if (!flightSchoolId) {
    return { ok: false, error: "FLIGHT_SCHOOL_ID_REQUIRED" };
  }

  try {
    const updated = await databases.updateDocument(
      MAIN_DATABASE_ID,
      FLIGHT_SCHOOLS_COLLECTION_ID,
      flightSchoolId,
      {
        admin_users: Array.isArray(adminUserIds) ? adminUserIds : [],
      }
    );

    return {
      ok: true,
      flightSchoolId: updated.$id,
    };
  } catch (error) {
    logError(context, "updateFlightSchoolAdmins:error", error);
    return { ok: false, error: "UPDATE_ADMINS_FAILED" };
  }
}

export async function removeMemberFromFlightSchool({ membershipId, context } = {}) {
  logJson(context, "removeMemberFromFlightSchool:start", { membershipId });

  if (!membershipId) {
    return { ok: false, error: "MEMBERSHIP_ID_REQUIRED" };
  }

  try {
    await databases.deleteDocument(
      MAIN_DATABASE_ID,
      MEMBERSHIPS_COLLECTION_ID,
      membershipId
    );

    return { ok: true };
  } catch (error) {
    logError(context, "removeMemberFromFlightSchool:error", error);
    return { ok: false, error: "REMOVE_MEMBER_FAILED" };
  }
}

export async function updateMemberRoles({ membershipId, roles, context } = {}) {
  logJson(context, "updateMemberRoles:start", {
    membershipId,
    roles,
  });

  if (!membershipId) {
    return { ok: false, error: "MEMBERSHIP_ID_REQUIRED" };
  }

  try {
    const updated = await databases.updateDocument(
      MAIN_DATABASE_ID,
      MEMBERSHIPS_COLLECTION_ID,
      membershipId,
      {
        roles: Array.isArray(roles) ? roles : [],
      }
    );

    return {
      ok: true,
      membershipId: updated.$id,
    };
  } catch (error) {
    logError(context, "updateMemberRoles:error", error);
    return { ok: false, error: "UPDATE_MEMBER_ROLES_FAILED" };
  }
}

export async function updateEvent({ event, context } = {}) {
  try {
    if (!event) throw new Error("EVENT_REQUIRED");

    const eventId = event.id ?? event.$id;
    if (!eventId) throw new Error("EVENT_ID_REQUIRED");

    requireEnv(MAIN_DATABASE_ID, "MAIN_DATABASE_ID");
    requireEnv(EVENTS_COLLECTION_ID, "EVENTS_COLLECTION_ID");
    requireEnv(TEAM_ASSIGNMENTS_COLLECTION_ID, "TEAM_ASSIGNMENTS_COLLECTION_ID");

    logJson(context, "updateEvent:start", {
      eventId,
      flightSchoolId: event.flightSchoolId,
      teamCount: Array.isArray(event.team) ? event.team.length : 0,
    });

    const updated = await databases.updateDocument(
      MAIN_DATABASE_ID,
      EVENTS_COLLECTION_ID,
      eventId,
      {
        identifier: event.identifier ?? "",
        status: event.status ?? "",
        start_time: event.startTime ?? null,
        end_time: event.endTime ?? null,
        notes: event.notes ?? "",
        display_name: event.displayName ?? "",
        location: event.location ?? "",
        flight_school_id: event.flightSchoolId ?? "",
      }
    );

    const existingTeamResult = await databases.listDocuments(
      MAIN_DATABASE_ID,
      TEAM_ASSIGNMENTS_COLLECTION_ID,
      [
        Query.equal("events", [eventId]),
        Query.limit(500),
      ]
    );

    const existingTeamDocs = existingTeamResult?.documents ?? [];
    const existingById = new Map(existingTeamDocs.map((doc) => [doc.$id, doc]));

    const incomingTeam = Array.isArray(event.team) ? event.team : [];
    const touchedIds = new Set();

    for (const tm of incomingTeam) {
      const assignmentId = tm.id ?? tm.$id ?? "";

      const data = {
        events: eventId,
        user_id: tm.userId ?? tm.user_id ?? "",
        role: tm.role ?? "",
        status: tm.status ?? "",
      };

      if (assignmentId && existingById.has(assignmentId)) {
        await databases.updateDocument(
          MAIN_DATABASE_ID,
          TEAM_ASSIGNMENTS_COLLECTION_ID,
          assignmentId,
          data
        );

        touchedIds.add(assignmentId);

        logJson(context, "updateEvent:team:update", {
          assignmentId,
          role: data.role,
          status: data.status,
          userId: data.user_id,
        });
      } else {
        const createdTeam = await databases.createDocument(
          MAIN_DATABASE_ID,
          TEAM_ASSIGNMENTS_COLLECTION_ID,
          ID.unique(),
          data
        );

        touchedIds.add(createdTeam.$id);

        logJson(context, "updateEvent:team:create", {
          assignmentId: createdTeam.$id,
          role: data.role,
          status: data.status,
          userId: data.user_id,
        });
      }
    }

    for (const existingDoc of existingTeamDocs) {
      if (!touchedIds.has(existingDoc.$id)) {
        await databases.updateDocument(
          MAIN_DATABASE_ID,
          TEAM_ASSIGNMENTS_COLLECTION_ID,
          existingDoc.$id,
          {
            status: "removed",
          }
        );

        logJson(context, "updateEvent:team:mark_removed", {
          assignmentId: existingDoc.$id,
        });
      }
    }

    logJson(context, "updateEvent:success", {
      eventId: updated.$id,
      incomingTeamCount: incomingTeam.length,
      existingTeamCount: existingTeamDocs.length,
    });

    return {
      ok: true,
      eventId: updated.$id,
    };
  } catch (error) {
    logError(context, "updateEvent:error", error);
    return { ok: false, error: "UPDATE_EVENT_FAILED" };
  }
}

export async function getFlightSchoolEvents({ flightSchoolId, context } = {}) {
  logJson(context, "getFlightSchoolEvents:start", {
    flightSchoolId,
    MAIN_DATABASE_ID,
    EVENTS_COLLECTION_ID,
    TEAM_ASSIGNMENTS_COLLECTION_ID,
  });

  if (!flightSchoolId) {
    return [];
  }

  try {
    requireEnv(MAIN_DATABASE_ID, "MAIN_DATABASE_ID");
    requireEnv(EVENTS_COLLECTION_ID, "EVENTS_COLLECTION_ID");
    requireEnv(TEAM_ASSIGNMENTS_COLLECTION_ID, "TEAM_ASSIGNMENTS_COLLECTION_ID");

    const eventsResult = await databases.listDocuments(
      MAIN_DATABASE_ID,
      EVENTS_COLLECTION_ID,
      [
        Query.equal("flight_school_id", [flightSchoolId]),
        Query.orderDesc("start_time"),
        Query.limit(200),
      ]
    );

    const eventDocs = eventsResult?.documents ?? [];

    logJson(context, "getFlightSchoolEvents:eventDocs", {
      count: eventDocs.length,
    });

    const events = await Promise.all(
      eventDocs.map(async (eventDoc) => {
        const eventData = getDocumentData(eventDoc);

        const teamDocs = await databases.listDocuments(
          MAIN_DATABASE_ID,
          TEAM_ASSIGNMENTS_COLLECTION_ID,
          [
            Query.equal("events", [eventDoc.$id]),
            Query.notEqual("status", "removed"),
            Query.limit(200),
          ]
        );

        const team = (teamDocs?.documents ?? []).map((doc) => {
          const d = getDocumentData(doc);
          return {
            id: doc.$id,
            userId: d.user_id ?? "",
            role: d.role ?? "",
            status: d.status ?? "",
            name: d.name ?? "",
          };
        });

        return {
          id: eventDoc.$id,
          flightSchoolId,
          identifier: eventData.identifier ?? "",
          status: eventData.status ?? "",
          startTime: eventData.start_time ?? null,
          endTime: eventData.end_time ?? null,
          displayName: eventData.display_name ?? "",
          location: eventData.location ?? "",
          notes: eventData.notes ?? "",
          team,
        };
      })
    );

    logJson(context, "getFlightSchoolEvents:success", {
      count: events.length,
    });

    return events;
  } catch (error) {
    logError(context, "getFlightSchoolEvents:error", error);
    return [];
  }
}

function getDocumentData(doc) {
  return doc?.data ?? doc ?? {};
}

function extractUserIdFromMembership(membership) {
  const usersField = membership?.users;

  if (!usersField) return null;
  if (typeof usersField === "string") return usersField;
  if (typeof usersField === "object" && usersField.$id) return usersField.$id;

  return null;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requireEnv(value, name) {
  if (!value || String(value).trim() === "") {
    throw new Error(`${name}_MISSING`);
  }
}

function logInfo(context, message) {
  if (context?.log && typeof context.log === "function") {
    context.log(message);
    return;
  }
  console.log(message);
}

function logErrorMessage(context, message) {
  if (context?.error && typeof context.error === "function") {
    context.error(message);
    return;
  }
  console.error(message);
}

function logError(context, message, error) {
  const payload = {
    message,
    errorMessage: error?.message ?? "UNKNOWN_ERROR",
    errorName: error?.name ?? null,
    errorCode: error?.code ?? null,
    errorType: error?.type ?? null,
    errorResponse: error?.response ?? null,
  };

  if (context?.error && typeof context.error === "function") {
    context.error(JSON.stringify(payload));
    return;
  }

  console.error(payload);
}

function logJson(context, label, value) {
  const payload = `${label}: ${JSON.stringify(value)}`;

  if (context?.log && typeof context.log === "function") {
    context.log(payload);
    return;
  }

  console.log(payload);
}