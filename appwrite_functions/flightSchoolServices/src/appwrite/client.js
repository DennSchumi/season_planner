// src/appwrite/client.js
import { Client, Users, Databases } from "node-appwrite";

function requireEnv(name) {
  const v = process.env[name];
  if (!v || String(v).trim() === "") {
    throw new Error(`Missing ${name} in function variables.`);
  }
  return v;
}

export function createAppwrite(overrides = {}) {
  // entweder aus overrides oder aus env
  const endpoint =
    overrides.endpoint ??
    process.env.APPWRITE_ENDPOINT ??
    process.env.APPWRITE_FUNCTION_API_ENDPOINT; // je nach Runtime

  const projectId =
    overrides.projectId ??
    process.env.APPWRITE_PROJECT_ID ??
    process.env.APPWRITE_FUNCTION_PROJECT_ID;

  const apiKey =
    overrides.apiKey ??
    process.env.APPWRITE_API_KEY ??
    process.env.APPWRITE_FUNCTION_API_KEY;

  if (!endpoint) throw new Error("Missing APPWRITE_ENDPOINT (or APPWRITE_FUNCTION_API_ENDPOINT).");
  if (!projectId) throw new Error("Missing APPWRITE_PROJECT_ID (or APPWRITE_FUNCTION_PROJECT_ID).");
  if (!apiKey) throw new Error("Missing APPWRITE_API_KEY (or APPWRITE_FUNCTION_API_KEY).");

  const client = new Client()
    .setEndpoint(endpoint)
    .setProject(projectId)
    .setKey(apiKey);

  return {
    client,
    users: new Users(client),
    databases: new Databases(client),
  };
}
