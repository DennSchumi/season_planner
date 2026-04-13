export function json(res, data, status = 200, headers = {}) {
  return res.send(JSON.stringify(data), status, {
    "content-type": "application/json",
    ...headers,
  });
}

export function text(res, body, status = 200, headers = {}) {
  return res.send(String(body ?? ""), status, {
    "content-type": "text/plain; charset=utf-8",
    ...headers,
  });
}

export function badRequest(res, message = "Bad Request") {
  return json(res, { ok: false, error: message }, 400);
}

export function notFound(res, message = "Not Found") {
  return json(res, { ok: false, error: message }, 404);
}

export function methodNotAllowed(res, allowed = []) {
  return json(
    res,
    { ok: false, error: "Method not allowed", allowed },
    405,
    { "allow": allowed.join(", ") }
  );
}

export async function jsonBody(req) {
  try {
    // Appwrite liefert POST Body hier:
    if (req.body) return req.body;

    // Fallback (manche Runtimes)
    if (req.bodyRaw) return JSON.parse(req.bodyRaw);

    return {};
  } catch (e) {
    return {};
  }
}