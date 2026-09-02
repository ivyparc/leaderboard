export function monthlyPeriod(date = new Date()) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
}

export function normalizeScoreOrder(order) {
  return order === "lower" ? "lower" : "higher";
}

export function isBetterScore(nextScore, previousScore, scoreOrder = "higher") {
  if (previousScore === null || previousScore === undefined) return true;
  return normalizeScoreOrder(scoreOrder) === "lower"
    ? nextScore < previousScore
    : nextScore > previousScore;
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

export function formatDurationScore(totalSeconds) {
  const seconds = Math.max(0, Math.round(Number(totalSeconds) || 0));
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(remainder).padStart(2, "0")}`;
}
