export const DEFAULT_BLOCKED_TERMS = new Set([
  "fuck",
  "fuk",
  "fck",
  "shit",
  "bitch",
  "asshole",
  "bastard",
  "cunt",
  "dick",
  "pussy",
  "slut",
  "whore",
  "nigger",
  "nigga",
  "faggot",
  "retard",
  "porn",
  "sibal",
  "ssibal",
  "jiral",
  "jonna",
  "byungsin",
  "gaesae",
  "saekki",
  "시발",
  "씨발",
  "병신",
  "지랄",
  "염병",
  "개새",
  "새끼",
  "좆",
  "존나",
  "씹",
  "강간",
  "ㅅㅂ",
  "ㅂㅅ",
  "ㅈㄹ",
]);

export function createNamePolicy({
  blockedTerms = DEFAULT_BLOCKED_TERMS,
  maxLength = 16,
} = {}) {
  function isBlocked(name) {
    const normalized = name
      .toLocaleLowerCase()
      .replace(/[\s_\-.,!@#$%^&*()[\]{}:;`~+=|\\/<>?]+/g, "");
    const leet = normalized
      .replaceAll("0", "o")
      .replaceAll("1", "i")
      .replaceAll("3", "e")
      .replaceAll("4", "a")
      .replaceAll("5", "s")
      .replaceAll("7", "t")
      .replaceAll("8", "b");
    return [...blockedTerms].some(
      (term) => normalized.includes(term) || leet.includes(term),
    );
  }

  function sanitize(rawName) {
    const compact = rawName.trim().replace(/\s+/g, " ");
    if (!compact) throw new Error("Name cannot be empty.");
    const name = [...compact].slice(0, maxLength).join("");
    if (isBlocked(name)) throw new Error("Please choose another name.");
    return name;
  }

  return { isBlocked, sanitize };
}
