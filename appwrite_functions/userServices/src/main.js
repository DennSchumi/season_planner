import { handleRequest } from "./router.js";

export default async ({ req, res, log, error }) => {
  try {
    return await handleRequest({ req, res, log });
  } catch (e) {
    error(e);
    return res.json({ ok: false, message: e?.message ?? String(e) }, 500);
  }
};
