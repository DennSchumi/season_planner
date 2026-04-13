import { json, badRequest, notFound, methodNotAllowed,jsonBody } from "./utils/http.js";
import { getMembersWithAuth,inviteUserToFlightSchool } from "./services/flightSchool.service.js";

export async function handleRequest({ req, res, log }) {
  const method = (req.method || "GET").toUpperCase();
  const path = req.path || "/";

  log(`flightSchoolServices: ${method} ${path}`);

// GET 
if (path === "admin/members") {
  if (method !== "GET") return methodNotAllowed(res, ["GET"]);

  const flightSchoolId = req.query?.flightSchoolId;
  if (!flightSchoolId) return badRequest(res, "Missing query param: flightSchoolId");

  const members = await getMembersWithAuth({ flightSchoolId });
  return json(res, { ok: true, members });
}

//POST 
if (path === "admin/members/invite") {
  if (method !== "POST") {
    return methodNotAllowed(res, ["POST"]);
  }
  console.log("REQ", {
  method,
  path,
  body: req.body,
  bodyRaw: req.bodyRaw,
});

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



  return notFound(res, `Unknown route: ${method} ${path}`);
}
