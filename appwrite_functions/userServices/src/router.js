import { json, badRequest, notFound, methodNotAllowed,jsonBody } from "./utils/http.js";

export async function handleRequest({ req, res, log }) {
  const method = (req.method || "GET").toUpperCase();
  const path = req.path || "/";

  log(`userServices: ${method} ${path}`);



  return notFound(res, `Unknown route: ${method} ${path}`);
}
