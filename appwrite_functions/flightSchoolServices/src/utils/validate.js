export function requireString(value, name) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`Missing/invalid "${name}"`);
  }
  return value.trim();
}
