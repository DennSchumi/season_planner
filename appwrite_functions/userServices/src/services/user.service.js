import { createAppwrite } from "../../src/appwrite/client.js";
import { Query } from "node-appwrite";

const MAIN_DATABASE_ID = process.env.MAIN_DATABASE_ID;
const USERS_COLLECTION_ID = process.env.USERS_COLLECTION_ID;

const { users, databases } = createAppwrite();

export async function getUserProfile(userId) {
  if (!userId || typeof userId !== "string") {
    throw new Error("userId is required");
  }

  const authUser = await getAuthUserById(userId);
  if (!authUser) {
    return {
      ok: false,
      error: "USER_NOT_FOUND",
    };
  }

  const mainUserDoc = await getMainUserDocument(userId);
  if (!mainUserDoc) {
    return {
      ok: false,
      error: "USER_DOCUMENT_NOT_FOUND",
    };
  }

  const memberships = getMembershipsFromUserDocument(mainUserDoc);
  const flightSchools = [];

  for (const membership of memberships) {
    const flightSchoolResult = await buildFlightSchoolProfile({
      membership,
      currentUserId: userId,
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
}

// User laden

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
    [Query.equal("$id", [userId]), Query.limit(1)]
  );

  if (!result.documents || result.documents.length === 0) {
    return null;
  }

  return result.documents[0];
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

// Flight school aufbauen

async function buildFlightSchoolProfile({ membership, currentUserId }) {
  const fs = membership?.flightSchools;
  if (!fs) return null;

  const flightSchoolMeta = mapFlightSchoolMeta(membership);
  const fsDatabaseId = flightSchoolMeta.databaseId;
  const teamAssignmentsCollectionId =
    flightSchoolMeta.teamAssignmentsEventsCollectionId;
  const positionApplicationsCollectionId =
    flightSchoolMeta.positionApplicationsCollectionId;

  if (!fsDatabaseId || !teamAssignmentsCollectionId) {
    return {
      ...flightSchoolMeta,
      events: [],
      assignments: [],
      openOpportunities: [],
      assignmentRequests: [],
      applications: [],
    };
  }

  const visibleTeamAssignments = await loadVisibleTeamAssignments({
    databaseId: fsDatabaseId,
    teamAssignmentsCollectionId,
    currentUserId,
    allowedRoles: flightSchoolMeta.availableRoles,
  });

  const eventIds = collectEventIdsFromAssignments(visibleTeamAssignments);

  const eventTeamsByEventId = await loadTeamsForEvents({
    databaseId: fsDatabaseId,
    teamAssignmentsCollectionId,
    eventIds,
  });

  const categorized = categorizeAssignments({
    teamAssignments: visibleTeamAssignments,
    currentUserId,
    eventTeamsByEventId,
    flightSchoolId: flightSchoolMeta.id,
  });

  const applications = positionApplicationsCollectionId
    ? await loadUserApplications({
        databaseId: fsDatabaseId,
        positionApplicationsCollectionId,
        currentUserId,
      })
    : [];

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
    databaseId: fs.database_id ?? null,
    teamAssignmentsEventsCollectionId: fs.team_assigments_events_id ?? null,
    eventsCollectionId: fs.events_id ?? null,
    auditLogsCollectionId: fs.audit_logs_id ?? null,
    positionApplicationsCollectionId: fs.position_applications_id ?? null,
    adminUserIds: Array.isArray(fs.admin_users) ? fs.admin_users : [],
    logoLink: fs.logo_link ?? "",
  };
}

// team_assignments_events laden

async function loadVisibleTeamAssignments({
  databaseId,
  teamAssignmentsCollectionId,
  currentUserId,
  allowedRoles,
}) {
  const allowedRolesSet = new Set((allowedRoles ?? []).map(String));

  const result = await databases.listDocuments(
    databaseId,
    teamAssignmentsCollectionId,
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

  return docs.filter((doc) => {
    const data = getDocumentData(doc);
    const assignmentUserId = normalizeUserId(data.user_id);
    const role = String(data.role ?? "");
    const status = String(data.status ?? "");

    const isOwnAssignment = assignmentUserId === currentUserId;
    const isOpenSlotForAllowedRole =
      isOpenOpportunity(assignmentUserId, status) && allowedRolesSet.has(role);

    if (isOwnAssignment) return true;
    if (isOpenSlotForAllowedRole) return true;

    return false;
  });
}

function collectEventIdsFromAssignments(teamAssignments) {
  const ids = new Set();

  for (const doc of teamAssignments) {
    const data = getDocumentData(doc);
    const eventRef = data.events;

    if (eventRef && typeof eventRef === "object" && eventRef.$id) {
      ids.add(eventRef.$id);
    }
  }

  return Array.from(ids);
}

async function loadTeamsForEvents({
  databaseId,
  teamAssignmentsCollectionId,
  eventIds,
}) {
  const map = new Map();

  for (const eventId of eventIds) {
    const result = await databases.listDocuments(
      databaseId,
      teamAssignmentsCollectionId,
      [Query.equal("events", [eventId]), Query.limit(500)]
    );

    const team = (result.documents ?? []).map((doc) => {
      const data = getDocumentData(doc);
      const userId = normalizeUserId(data.user_id);

      return {
        id: doc.$id,
        userId,
        role: String(data.role ?? ""),
        status: String(data.status ?? ""),
        isSlot: userId === "",
      };
    });

    map.set(eventId, team);
  }

  return map;
}

function categorizeAssignments({
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
    const eventRef = data.events;

    if (!eventRef || typeof eventRef !== "object" || !eventRef.$id) {
      continue;
    }

    const eventId = eventRef.$id;
    const userId = normalizeUserId(data.user_id);
    const role = String(data.role ?? "");
    const status = String(data.status ?? "");

    if (!eventsMap.has(eventId)) {
      eventsMap.set(
        eventId,
        mapEventWithTeam({
          eventRef,
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

function mapEventWithTeam({ eventRef, flightSchoolId, team }) {
  return {
    id: eventRef.$id,
    flightSchoolId,
    identifier: eventRef.identifier ?? "",
    status: eventRef.status ?? "",
    startTime: eventRef.start_time ?? null,
    endTime: eventRef.end_time ?? null,
    displayName: eventRef.display_name ?? "",
    location: eventRef.location ?? "",
    notes: eventRef.notes ?? "",
    team,
  };
}

// position_applications laden

async function loadUserApplications({
  databaseId,
  positionApplicationsCollectionId,
  currentUserId,
}) {
  const result = await databases.listDocuments(
    databaseId,
    positionApplicationsCollectionId,
    [Query.equal("user_id", [currentUserId]), Query.limit(500)]
  );

  return (result.documents ?? []).map(mapApplicationDocument);
}

function mapApplicationDocument(doc) {
  const data = getDocumentData(doc);
  const teamAssignmentRef =
    data.team_assignment_event ?? data.teamAssignmentEvent;

  const role =
    teamAssignmentRef && typeof teamAssignmentRef === "object"
      ? String(teamAssignmentRef.role ?? "")
      : "";

  const eventRef =
    teamAssignmentRef &&
    typeof teamAssignmentRef === "object" &&
    teamAssignmentRef.events &&
    typeof teamAssignmentRef.events === "object"
      ? teamAssignmentRef.events
      : null;

  return {
    id: doc.$id,
    userId: normalizeUserId(data.user_id),
    status: String(data.status ?? ""),
    teamAssignmentEventId:
      teamAssignmentRef && typeof teamAssignmentRef === "object"
        ? teamAssignmentRef.$id ?? null
        : null,
    role,
    eventId: eventRef?.$id ?? null,
    eventDisplayName: eventRef?.display_name ?? "",
    createdAt: doc.$createdAt ?? null,
    updatedAt: doc.$updatedAt ?? null,
  };
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

  return ["accepted_user", "accepted_flight_school"].includes(normalized);
}

function isRejectedAssignmentStatus(status) {
  const normalized = String(status ?? "").toLowerCase();

  return ["denied_user", "denied_flight_school"].includes(normalized);
}

function isOpenOpportunity(userId, status) {
  const normalizedUserId = normalizeUserId(userId);
  const normalizedStatus = String(status ?? "").toLowerCase();

  return normalizedUserId === "" && normalizedStatus === "open";
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