export function monthlyPeriod(date = new Date()) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
}

export function createAnonymousPlayerId() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  throw new Error("This browser cannot create a secure anonymous player ID.");
}

export function normalizeCountryCode(code) {
  const normalized = code?.trim().toUpperCase();
  return /^[A-Z]{2}$/.test(normalized ?? "") ? normalized : null;
}

export function flagEmoji(countryCode) {
  const code = normalizeCountryCode(countryCode);
  if (!code) return "--";
  return String.fromCodePoint(
    ...[...code].map((letter) => letter.charCodeAt(0) - 65 + 0x1f1e6),
  );
}

export function formatLeaderboardScore(score) {
  return new Intl.NumberFormat("en-US").format(score);
}
