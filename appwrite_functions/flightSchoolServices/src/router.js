import {
  json,
  badRequest,
  notFound,
  methodNotAllowed,
  jsonBody,
} from "./utils/http.js";

import {
  getMembersWithAuth,
  inviteUserToFlightSchool,
  getFlightSchoolAdminView,
  updateFlightSchoolAdmins,
  removeMemberFromFlightSchool,
  updateMemberRoles,
} from "./services/flightSchool.service.js";

export async function handleRequest({ req, res, log }) {
  const method = (req.method || "GET").toUpperCase();
  const path = req.path || "/";

  log(`flightSchoolServices: ${method} ${path}`);

  if (path === "/admin/flight-school") {
    if (method !== "GET") {
      return methodNotAllowed(res, ["GET"]);
    }

    const flightSchoolId = req.query?.flightSchoolId;
    if (!flightSchoolId) {
      return badRequest(res, "Missing query param: flightSchoolId");
    }

    const result = await getFlightSchoolAdminView({ flightSchoolId });
    return json(res, result);
  }

  if (path === "/admin/members") {
    if (method === "GET") {
      const flightSchoolId = req.query?.flightSchoolId;
      if (!flightSchoolId) {
        return badRequest(res, "Missing query param: flightSchoolId");
      }

      const members = await getMembersWithAuth({ flightSchoolId });
      return json(res, { ok: true, members });
    }

    if (method === "DELETE") {
      const body = await jsonBody(req);

      if (!body.membershipId) {
        return badRequest(res, "membershipId required");
      }

      const result = await removeMemberFromFlightSchool({
        membershipId: body.membershipId,
      });

      return json(res, result);
    }

    return methodNotAllowed(res, ["GET", "DELETE"]);
  }

  if (path === "/admin/members/invite") {
    if (method !== "POST") {
      return methodNotAllowed(res, ["POST"]);
    }

    const body = await jsonBody(req);

    if (!body.flightSchoolId || !body.userMail) {
      return badRequest(res, "flightSchoolId and userMail required");
    }

    const result = await inviteUserToFlightSchool({
      flightSchoolId: body.flightSchoolId,
      userMail: body.userMail,
      roles: body.roles ?? [],
    });

    return json(res, result);
  }

  if (path === "/admin/members/roles") {
    if (method !== "POST") {
      return methodNotAllowed(res, ["POST"]);
    }

    const body = await jsonBody(req);

    if (!body.membershipId || !Array.isArray(body.roles)) {
      return badRequest(res, "membershipId and roles required");
    }

    const result = await updateMemberRoles({
      membershipId: body.membershipId,
      roles: body.roles,
    });

    return json(res, result);
  }

  if (path === "/admin/admins") {
    if (method !== "POST") {
      return methodNotAllowed(res, ["POST"]);
    }

    const body = await jsonBody(req);

    if (!body.flightSchoolId || !Array.isArray(body.adminUserIds)) {
      return badRequest(res, "flightSchoolId and adminUserIds required");
    }

    const result = await updateFlightSchoolAdmins({
      flightSchoolId: body.flightSchoolId,
      adminUserIds: body.adminUserIds,
    });

    return json(res, result);
  }

  return notFound(res, `Unknown route: ${method} ${path}`);
}