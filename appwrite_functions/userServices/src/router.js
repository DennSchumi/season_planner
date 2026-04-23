import { json, badRequest, notFound, methodNotAllowed, jsonBody } from "./utils/http.js";

import { getUserProfile,createApplication } from "./services/user.service.js";

export async function handleRequest({ req, res, log }) {
  const method = (req.method || "GET").toUpperCase();
  const path = req.path || "/";

  log(`userServices: ${method} ${path}`);

if (path === "/user/profile") {
  if (method !== "GET") {
    return methodNotAllowed(res, ["GET"]);
  }

  const userId = req.headers["x-appwrite-user-id"];

  if (!userId) {
    return badRequest(res, "Missing authenticated user");
  }

  const result = await getUserProfile(userId);
  return json(res, result);
}

  if (path === "/user/events") {
    if (method === "GET") {
      // handle get events
    }

    return methodNotAllowed(res, ["GET"]);
  }


if (path === "/user/applications") {
  const userId = req.headers["x-appwrite-user-id"] || req.query?.userId;

  if (!userId) {
    return badRequest(res, "Missing userId");
  }

  if (method === "GET") {
    const result = await getUserApplications(userId);
    return json(res, result);
  }

  if (method === "POST") {
    const body = await jsonBody(req);

    if (!body.teamAssignmentEventId) {
      return badRequest(res, "teamAssignmentEventId required");
    }

    const result = await createApplication(userId, body.teamAssignmentEventId);
    return json(res, result);
  }

  if (method === "DELETE") {
    const body = await jsonBody(req);

    if (!body.applicationId) {
      return badRequest(res, "applicationId required");
    }

    const result = await withdrawApplication(userId, body.applicationId);
    return json(res, result);
  }

  return methodNotAllowed(res, ["GET", "POST", "DELETE"]);
}

  // =========================
  // /user/assignment-requests
  // =========================
  if (path === "/user/assignment-requests") {
    if (method === "GET") {
      // handle get assignment requests
    }

    return methodNotAllowed(res, ["GET"]);
  }

  // =========================
  // /user/assignment-requests/accept
  // =========================
  if (path === "/user/assignment-requests/accept") {
    if (method === "POST") {
      // handle accept assignment request
    }

    return methodNotAllowed(res, ["POST"]);
  }

  // =========================
  // /user/assignment-requests/decline
  // =========================
  if (path === "/user/assignment-requests/decline") {
    if (method === "POST") {
      // handle decline assignment request
    }

    return methodNotAllowed(res, ["POST"]);
  }

  // =========================
  // /user/assignments
  // =========================
  if (path === "/user/assignments") {
    if (method === "GET") {
      // handle get assignments
    }

    return methodNotAllowed(res, ["GET"]);
  }

  // =========================
  // /user/memberships/accept
  // =========================
  if (path === "/user/memberships/accept") {
    if (method === "POST") {
      // handle accept membership
    }

    return methodNotAllowed(res, ["POST"]);
  }

  // =========================
  // /user/memberships/decline
  // =========================
  if (path === "/user/memberships/decline") {
    if (method === "DELETE") {
      // handle leave membership
    }

    return methodNotAllowed(res, ["DELETE"]);
  }

  // =========================
  // /user/memberships/leave
  // =========================
  if (path === "/user/memberships/leave") {
    if (method === "DELETE") {
      // handle leave membership
    }

    return methodNotAllowed(res, ["DELETE"]);
  }

  return notFound(res, `Unknown route: ${method} ${path}`);
}