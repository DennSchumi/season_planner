import { createAppwrite } from "../../src/appwrite/client.js";
import { Query, ID } from "node-appwrite";

const MAIN_DATABASE_ID = process.env.MAIN_DATABASE_ID;
const USERS_COLLECTION_ID = process.env.USERS_COLLECTION_ID;
const EVENTS_COLLECTION_ID = process.env.EVENTS_COLLECTION_ID;
const TEAM_ASSIGNMENTS_COLLECTION_ID = process.env.TEAM_ASSIGNMENTS_COLLECTION_ID;
const POSITION_APPLICATIONS_COLLECTION_ID = process.env.POSITION_APPLICATIONS_COLLECTION_ID;

const { users, databases } = createAppwrite();

export async function getUserProfile(userId, context) {
  try {
    if (!userId || typeof userId !== "string") {
      throw new Error("USER_ID_REQUIRED");
    }

    requireEnv(MAIN_DATABASE_ID, "MAIN_DATABASE_ID");
    requireEnv(USERS_COLLECTION_ID, "USERS_COLLECTION_ID");
    requireEnv(EVENTS_COLLECTION_ID, "EVENTS_COLLECTION_ID");
    requireEnv(TEAM_ASSIGNMENTS_COLLECTION_ID, "TEAM_ASSIGNMENTS_COLLECTION_ID");

    const authUser = await getAuthUserById(userId);
    if (!authUser) {
      return { ok: false, error: "USER_NOT_FOUND" };
    }

    const mainUserDoc = await getMainUserDocument(userId);
    if (!mainUserDoc) {
      return { ok: false, error: "USER_DOCUMENT_NOT_FOUND" };
    }

    const memberships = getMembershipsFromUserDocument(mainUserDoc);
    const flightSchools = [];

    for (const membership of memberships) {
      const flightSchoolResult = await buildFlightSchoolProfile({
        membership,
        currentUserId: userId,
        context,
      });

      if (flightSchoolResult) {
        flightSchools.push(flightSchoolResult);
      }
    }

    return {
      ok: true,
      user: mapAuthUser(authUser),
      flightSchools,
    };
  } catch (error) {
    logError(context, "getUserProfile:error", error);
    return { ok: false, error: "GET_USER_PROFILE_FAILED" };
  }
}

export async function getUserApplications(userId, context) {
  try {
    if (!userId || typeof userId !== "string") {
      throw new Error("USER_ID_REQUIRED");
    }

    requireEnv(MAIN_DATABASE_ID, "MAIN_DATABASE_ID");
    requireEnv(POSITION_APPLICATIONS_COLLECTION_ID, "POSITION_APPLICATIONS_COLLECTION_ID");

    const mainUserDoc = await getMainUserDocument(userId);
    if (!mainUserDoc) {
      return { ok: false, error: "USER_DOCUMENT_NOT_FOUND" };
    }

    const applications = await loadUserApplications({
      currentUserId: userId,
    });

    return {
      ok: true,
      applications,
    };
  } catch (error) {
    logError(context, "getUserApplications:error", error);
    return { ok: false, error: "GET_USER_APPLICATIONS_FAILED" };
  }
}

export async function createApplication(userId, teamAssignmentEventId, context) {
  try {
    if (!userId || typeof userId !== "string") {
      throw new Error("USER_ID_REQUIRED");
    }

    if (!teamAssignmentEventId || typeof teamAssignmentEventId !== "string") {
      throw new Error("TEAM_ASSIGNMENT_EVENT_ID_REQUIRED");
    }

    requireEnv(MAIN_DATABASE_ID, "MAIN_DATABASE_ID");
    requireEnv(TEAM_ASSIGNMENTS_COLLECTION_ID, "TEAM_ASSIGNMENTS_COLLECTION_ID");
    requireEnv(POSITION_APPLICATIONS_COLLECTION_ID, "POSITION_APPLICATIONS_COLLECTION_ID");

    const authUser = await getAuthUserById(userId);
    if (!authUser) {
      return { ok: false, error: "USER_NOT_FOUND" };
    }

    const mainUserDoc = await getMainUserDocument(userId);
    if (!mainUserDoc) {
      return { ok: false, error: "USER_DOCUMENT_NOT_FOUND" };
    }

    const slot = await findTeamAssignmentById(teamAssignmentEventId);
    if (!slot) {
      return { ok: false, error: "TEAM_ASSIGNMENT_NOT_FOUND" };
    }

    const slotData = getDocumentData(slot);
    const slotRole = String(slotData.role ?? "");
    const slotStatus = String(slotData.status ?? "");
    const slotUserId = normalizeUserId(slotData.user_id);

    if (!isOpenOpportunity(slotUserId, slotStatus)) {
      return { ok: false, error: "POSITION_NOT_OPEN" };
    }

    const eventDoc = await resolveEventFromAssignment(slotData);
    if (!eventDoc) {
      return { ok: false, error: "EVENT_NOT_FOUND" };
    }

    const eventData = getDocumentData(eventDoc);
    const flightSchoolId = getFlightSchoolIdFromEvent(eventDoc, eventData);

    if (!flightSchoolId) {
      return { ok: false, error: "FLIGHT_SCHOOL_ID_NOT_FOUND" };
    }

    const memberships = getMembershipsFromUserDocument(mainUserDoc);
    const membership = findMembershipForFlightSchool(memberships, flightSchoolId);

    if (!membership) {
      return { ok: false, error: "MEMBERSHIP_NOT_FOUND" };
    }

    const allowedRoles = Array.isArray(membership.roles)
      ? membership.roles.map(String)
      : [];

    if (!allowedRoles.includes(slotRole)) {
      return { ok: false, error: "ROLE_NOT_ALLOWED" };
    }

    const existingApplications = await databases.listDocuments(
      MAIN_DATABASE_ID,
      POSITION_APPLICATIONS_COLLECTION_ID,
      [
        Query.equal("user_id", [userId]),
        Query.equal("teamAssignmentsEvents", [teamAssignmentEventId]),
        Query.limit(10),
      ]
    );

    const activeDuplicate = (existingApplications.documents ?? []).find((doc) => {
      const data = getDocumentData(doc);
      const status = String(data.status ?? "").toLowerCase();
      return status !== "withdrawn" && status !== "rejected";
    });

    if (activeDuplicate) {
      return { ok: false, error: "APPLICATION_ALREADY_EXISTS" };
    }

    const created = await databases.createDocument(
      MAIN_DATABASE_ID,
      POSITION_APPLICATIONS_COLLECTION_ID,
      ID.unique(),
      {
        user_id: userId,
        teamAssignmentsEvents: teamAssignmentEventId,
        status: "pending",
      }
    );

    return {
      ok: true,
      application: mapApplicationDocument(created),
    };
  } catch (error) {
    logError(context, "createApplication:error", error);
    return { ok: false, error: "CREATE_APPLICATION_FAILED" };
  }
}

export async function withdrawApplication(userId, applicationId, context) {
  try {
    if (!userId || typeof userId !== "string") {
      throw new Error("USER_ID_REQUIRED");
    }

    if (!applicationId || typeof applicationId !== "string") {
      throw new Error("APPLICATION_ID_REQUIRED");
    }

    requireEnv(MAIN_DATABASE_ID, "MAIN_DATABASE_ID");
    requireEnv(POSITION_APPLICATIONS_COLLECTION_ID, "POSITION_APPLICATIONS_COLLECTION_ID");

    const application = await findApplicationById(applicationId);
    if (!application) {
      return { ok: false, error: "APPLICATION_NOT_FOUND" };
    }

    const appData = getDocumentData(application);
    const ownerId = normalizeUserId(appData.user_id);

    if (ownerId !== userId) {
      return { ok: false, error: "APPLICATION_NOT_OWNED_BY_USER" };
    }

    const updated = await databases.updateDocument(
      MAIN_DATABASE_ID,
      POSITION_APPLICATIONS_COLLECTION_ID,
      applicationId,
      {
        status: "withdrawn",
      }
    );

    return {
      ok: true,
      application: mapApplicationDocument(updated),
    };
  } catch (error) {
    logError(context, "withdrawApplication:error", error);
    return { ok: false, error: "WITHDRAW_APPLICATION_FAILED" };
  }
}

// User

async function getAuthUserById(userId) {
  try {
    return await users.get(userId);
  } catch (_) {
    return null;
  }
}

async function getMainUserDocument(userId) {
  const result = await databases.listDocuments(
    MAIN_DATABASE_ID,
    USERS_COLLECTION_ID,
    [
      Query.equal("$id", [userId]),
      Query.limit(1),
    ]
  );

  return result.documents?.[0] ?? null;
}

function getMembershipsFromUserDocument(userDoc) {
  const data = getDocumentData(userDoc);
  return Array.isArray(data.memberships) ? data.memberships : [];
}

function mapAuthUser(authUser) {
  return {
    id: authUser.$id,
    name: authUser.name ?? "",
    email: authUser.email ?? "",
    phone: authUser.phone ?? "",
  };
}

// FlightSchool-Profil

async function buildFlightSchoolProfile({ membership, currentUserId, context }) {
  const fs = membership?.flightSchools;
  if (!fs) return null;

  const flightSchoolMeta = mapFlightSchoolMeta(membership);

  const visibleTeamAssignments = await loadVisibleTeamAssignments({
    currentUserId,
    flightSchoolId: flightSchoolMeta.id,
    allowedRoles: flightSchoolMeta.availableRoles,
    context,
  });

  const eventIds = collectEventIdsFromAssignments(visibleTeamAssignments);

  const eventTeamsByEventId = await loadTeamsForEvents({
    eventIds,
  });

  const categorized = await categorizeAssignments({
    teamAssignments: visibleTeamAssignments,
    currentUserId,
    eventTeamsByEventId,
    flightSchoolId: flightSchoolMeta.id,
  });

  const applications = await loadUserApplications({
    currentUserId,
    flightSchoolId: flightSchoolMeta.id,
  });

  return {
    ...flightSchoolMeta,
    events: categorized.events,
    assignments: categorized.assignments,
    openOpportunities: categorized.openOpportunities,
    assignmentRequests: categorized.assignmentRequests,
    applications,
  };
}

function mapFlightSchoolMeta(membership) {
  const fs = membership.flightSchools;

  const availableRoles = Array.isArray(membership.roles)
    ? membership.roles.map((r) => String(r))
    : [];

  return {
    id: fs.$id,
    displayName: fs.display_name ?? "",
    displayShortName: fs.display_short_name ?? "",
    membershipStatus: membership.status ?? null,
    availableRoles,

    databaseId: MAIN_DATABASE_ID,
    teamAssignmentsEventsCollectionId: TEAM_ASSIGNMENTS_COLLECTION_ID,
    eventsCollectionId: EVENTS_COLLECTION_ID,
    positionApplicationsCollectionId: POSITION_APPLICATIONS_COLLECTION_ID,

    auditLogsCollectionId: fs.audit_logs_id ?? null,
    adminUserIds: Array.isArray(fs.admin_users) ? fs.admin_users : [],
    logoLink: fs.logo_link ?? "",
  };
}

// Team Assignments

async function loadVisibleTeamAssignments({
  currentUserId,
  flightSchoolId,
  allowedRoles,
  context,
}) {
  const allowedRolesSet = new Set((allowedRoles ?? []).map(String));

  const result = await databases.listDocuments(
    MAIN_DATABASE_ID,
    TEAM_ASSIGNMENTS_COLLECTION_ID,
    [
      Query.or([
        Query.equal("user_id", [currentUserId]),
        Query.equal("user_id", [""]),
        Query.isNull("user_id"),
      ]),
      Query.limit(500),
    ]
  );

  const docs = result.documents ?? [];
  const visible = [];

  for (const doc of docs) {
    const data = getDocumentData(doc);

    if (isRemovedStatus(data.status)) {
      continue;
    }

    const eventDoc = await resolveEventFromAssignment(data);
    if (!eventDoc) {
      continue;
    }

    const eventData = getDocumentData(eventDoc);
    const assignmentFlightSchoolId = getFlightSchoolIdFromEvent(eventDoc, eventData);

    if (assignmentFlightSchoolId !== flightSchoolId) {
      continue;
    }

    const assignmentUserId = normalizeUserId(data.user_id);
    const role = String(data.role ?? "");
    const status = String(data.status ?? "");

    const isOwnAssignment = assignmentUserId === currentUserId;
    const isOpenSlotForAllowedRole =
      isOpenOpportunity(assignmentUserId, status) && allowedRolesSet.has(role);

    if (isOwnAssignment || isOpenSlotForAllowedRole) {
      visible.push(doc);
    }
  }

  logJson(context, "loadVisibleTeamAssignments:result", {
    flightSchoolId,
    count: visible.length,
  });

  return visible;
}

function collectEventIdsFromAssignments(teamAssignments) {
  const ids = new Set();

  for (const doc of teamAssignments) {
    const data = getDocumentData(doc);
    const eventId = getEventIdFromAssignment(data);

    if (eventId) {
      ids.add(eventId);
    }
  }

  return Array.from(ids);
}

async function loadTeamsForEvents({ eventIds }) {
  const map = new Map();

  for (const eventId of eventIds) {
    const result = await databases.listDocuments(
      MAIN_DATABASE_ID,
      TEAM_ASSIGNMENTS_COLLECTION_ID,
      [
        Query.equal("events", [eventId]),
        Query.limit(500),
      ]
    );

    const team = (result.documents ?? [])
      .filter((doc) => !isRemovedStatus(getDocumentData(doc).status))
      .map((doc) => {
        const data = getDocumentData(doc);
        const userId = normalizeUserId(data.user_id);

        return {
          id: doc.$id,
          userId,
          role: String(data.role ?? ""),
          status: String(data.status ?? ""),
          name: String(data.name ?? ""),
          isSlot: isSlotUserId(userId),
        };
      });

    map.set(eventId, team);
  }

  return map;
}

async function categorizeAssignments({
  teamAssignments,
  currentUserId,
  eventTeamsByEventId,
  flightSchoolId,
}) {
  const eventsMap = new Map();
  const assignments = [];
  const openOpportunities = [];
  const assignmentRequests = [];

  for (const doc of teamAssignments) {
    const data = getDocumentData(doc);

    if (isRemovedStatus(data.status)) {
      continue;
    }

    const eventDoc = await resolveEventFromAssignment(data);
    if (!eventDoc) {
      continue;
    }

    const eventData = getDocumentData(eventDoc);
    const eventId = eventDoc.$id;
    const userId = normalizeUserId(data.user_id);
    const role = String(data.role ?? "");
    const status = String(data.status ?? "");

    if (!eventsMap.has(eventId)) {
      eventsMap.set(
        eventId,
        mapEventWithTeam({
          eventDoc,
          eventData,
          flightSchoolId,
          team: eventTeamsByEventId.get(eventId) ?? [],
        })
      );
    }

    const assignmentItem = {
      id: doc.$id,
      eventId,
      flightSchoolId,
      role,
      status,
      flowType: getAssignmentFlowType(status),
      userId,
    };

    const isOwnAssignment = userId === currentUserId;

    if (isOwnAssignment) {
      if (isAssignmentRequestStatus(status)) {
        assignmentRequests.push(assignmentItem);
      } else if (isFinalAssignmentStatus(status)) {
        assignments.push(assignmentItem);
      }
    } else if (isOpenOpportunity(userId, status)) {
      openOpportunities.push(assignmentItem);
    }
  }

  return {
    events: Array.from(eventsMap.values()),
    assignments,
    openOpportunities,
    assignmentRequests,
  };
}

function mapEventWithTeam({ eventDoc, eventData, flightSchoolId, team }) {
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
}

// Applications

async function loadUserApplications({ currentUserId, flightSchoolId = null }) {
  const result = await databases.listDocuments(
    MAIN_DATABASE_ID,
    POSITION_APPLICATIONS_COLLECTION_ID,
    [
      Query.equal("user_id", [currentUserId]),
      Query.limit(500),
    ]
  );

  const mapped = [];

  for (const doc of result.documents ?? []) {
    const item = await mapApplicationDocumentWithContext(doc);

    if (flightSchoolId && item.flightSchoolId !== flightSchoolId) {
      continue;
    }

    mapped.push(item);
  }

  return mapped;
}

async function mapApplicationDocumentWithContext(doc) {
  const base = mapApplicationDocument(doc);

  const data = getDocumentData(doc);
  const teamAssignmentId = base.teamAssignmentEventId;

  let eventId = null;
  let flightSchoolId = null;

  if (teamAssignmentId) {
    const teamAssignment = await findTeamAssignmentById(teamAssignmentId);

    if (teamAssignment) {
      const assignmentData = getDocumentData(teamAssignment);
      const eventDoc = await resolveEventFromAssignment(assignmentData);

      if (eventDoc) {
        const eventData = getDocumentData(eventDoc);
        eventId = eventDoc.$id;
        flightSchoolId = getFlightSchoolIdFromEvent(eventDoc, eventData);
      }
    }
  }

  return {
    ...base,
    eventId,
    flightSchoolId,
  };
}

function mapApplicationDocument(doc) {
  const data = getDocumentData(doc);
  const teamAssignmentRef =
    data.teamAssignmentsEvents ?? data.teamAssignmentEvent;

  return {
    id: doc.$id,
    userId: normalizeUserId(data.user_id),
    status: String(data.status ?? ""),
    teamAssignmentEventId:
      teamAssignmentRef && typeof teamAssignmentRef === "object"
        ? teamAssignmentRef.$id ?? null
        : typeof teamAssignmentRef === "string"
          ? teamAssignmentRef
          : null,
    createdAt: doc.$createdAt ?? null,
    updatedAt: doc.$updatedAt ?? null,
  };
}

async function findTeamAssignmentById(teamAssignmentEventId) {
  const result = await databases.listDocuments(
    MAIN_DATABASE_ID,
    TEAM_ASSIGNMENTS_COLLECTION_ID,
    [
      Query.equal("$id", [teamAssignmentEventId]),
      Query.limit(1),
    ]
  );

  return result.documents?.[0] ?? null;
}

async function findApplicationById(applicationId) {
  const result = await databases.listDocuments(
    MAIN_DATABASE_ID,
    POSITION_APPLICATIONS_COLLECTION_ID,
    [
      Query.equal("$id", [applicationId]),
      Query.limit(1),
    ]
  );

  return result.documents?.[0] ?? null;
}

// Event helpers

async function resolveEventFromAssignment(assignmentData) {
  const eventRef = assignmentData.events;

  if (eventRef && typeof eventRef === "object" && eventRef.$id) {
    return eventRef;
  }

  if (typeof eventRef === "string" && eventRef.trim() !== "") {
    try {
      return await databases.getDocument(
        MAIN_DATABASE_ID,
        EVENTS_COLLECTION_ID,
        eventRef
      );
    } catch (_) {
      return null;
    }
  }

  return null;
}

function getEventIdFromAssignment(assignmentData) {
  const eventRef = assignmentData.events;

  if (eventRef && typeof eventRef === "object" && eventRef.$id) {
    return eventRef.$id;
  }

  if (typeof eventRef === "string") {
    return eventRef;
  }

  return null;
}

function getFlightSchoolIdFromEvent(eventDoc, eventData) {
  const raw =
    eventData.flight_school_id ??
    eventData.flightSchoolId ??
    eventDoc.flight_school_id ??
    eventDoc.flightSchoolId;

  if (!raw) return "";

  if (typeof raw === "object" && raw.$id) {
    return raw.$id;
  }

  return String(raw);
}

function findMembershipForFlightSchool(memberships, flightSchoolId) {
  return (memberships ?? []).find((membership) => {
    const fs = membership?.flightSchools;
    if (!fs) return false;

    if (typeof fs === "object" && fs.$id === flightSchoolId) {
      return true;
    }

    if (typeof fs === "string" && fs === flightSchoolId) {
      return true;
    }

    return false;
  });
}

// Statuslogik

function isAssignmentRequestStatus(status) {
  const normalized = String(status ?? "").toLowerCase();

  return [
    "pending_user",
    "pending_flight_school",
    "user_requests_change",
  ].includes(normalized);
}

function isFinalAssignmentStatus(status) {
  const normalized = String(status ?? "").toLowerCase();

  return [
    "accepted_user",
    "accepted_flight_school",
  ].includes(normalized);
}

function isOpenOpportunity(userId, status) {
  const normalizedUserId = normalizeUserId(userId);
  const normalizedStatus = String(status ?? "").toLowerCase();

  if (normalizedStatus !== "open") return false;

  return normalizedUserId === "" || isSlotUserId(normalizedUserId);
}

function isSlotUserId(userId) {
  return String(userId ?? "").startsWith("slot_");
}

function isRemovedStatus(status) {
  return String(status ?? "").toLowerCase() === "removed";
}

function getAssignmentFlowType(status) {
  const normalized = String(status ?? "").toLowerCase();

  if (normalized === "pending_user") return "direct_request";
  if (normalized === "pending_flight_school") return "application_review";
  if (normalized === "user_requests_change") return "change_request";
  if (normalized === "accepted_user") return "direct_request";
  if (normalized === "accepted_flight_school") return "application_review";
  if (normalized === "open") return "open_opportunity";
  if (normalized === "denied_user") return "direct_request";
  if (normalized === "denied_flight_school") return "application_review";
  if (normalized === "removed") return "removed";

  return "unknown";
}

// Helpers

function getDocumentData(doc) {
  return doc?.data ?? doc ?? {};
}

function normalizeUserId(value) {
  if (value === null || value === undefined) return "";
  return String(value).trim();
}

function requireEnv(value, name) {
  if (!value || String(value).trim() === "") {
    throw new Error(`${name}_MISSING`);
  }
}

function logJson(context, label, value) {
  const payload = `${label}: ${JSON.stringify(value)}`;

  if (context?.log && typeof context.log === "function") {
    context.log(payload);
    return;
  }

  console.log(payload);
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