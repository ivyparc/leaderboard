import { createNamePolicy } from "./namePolicy.js";
import {
  createAnonymousPlayerId,
  monthlyPeriod,
  normalizeCountryCode,
} from "./utils.js";

export function createLeaderboardClient({
  supabaseUrl,
  supabaseAnonKey,
  table = "app_leaderboard_scores",
  namespace,
  topLimit = 100,
  rankScanLimit = 500,
  cacheDurationMs = 45_000,
  requestTimeoutMs = 8_000,
  periodResolver = monthlyPeriod,
  countryCodeResolver,
  storage = globalThis.localStorage,
  namePolicy = createNamePolicy(),
  fetchImpl = globalThis.fetch,
}) {
  if (!supabaseUrl || !supabaseAnonKey || !namespace) {
    throw new Error(
      "supabaseUrl, supabaseAnonKey, and namespace are required.",
    );
  }
  if (!storage) throw new Error("A storage implementation is required.");
  if (!fetchImpl) throw new Error("A fetch implementation is required.");

  const projectUrl = supabaseUrl
    .trim()
    .replace(/\/rest\/v1\/?$/, "")
    .replace(/\/$/, "");
  const playerIdKey = `${namespace}.leaderboard.playerId.v1`;
  const playerNameKey = `${namespace}.leaderboard.playerName.v1`;
  let cache = null;

  const headers = {
    apikey: supabaseAnonKey,
    Authorization: `Bearer ${supabaseAnonKey}`,
    "Content-Type": "application/json",
  };

  function currentPeriod() {
    return periodResolver(new Date());
  }

  function tableUrl(params = {}) {
    const url = new URL(`${projectUrl}/rest/v1/${table}`);
    Object.entries(params).forEach(([key, value]) => {
      url.searchParams.set(key, value);
    });
    return url;
  }

  async function request(url, options = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), requestTimeoutMs);
    try {
      const response = await fetchImpl(url, {
        ...options,
        headers: { ...headers, ...options.headers },
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new Error(`Leaderboard request failed (${response.status}).`);
      }
      return response;
    } finally {
      clearTimeout(timer);
    }
  }

  async function requestList(params) {
    const response = await request(tableUrl(params));
    const rows = await response.json();
    if (!Array.isArray(rows)) {
      throw new Error("Leaderboard returned invalid data.");
    }
    return rows;
  }

  function getOrCreatePlayerId() {
    const saved = storage.getItem(playerIdKey);
    if (saved) return saved;
    const id = createAnonymousPlayerId();
    storage.setItem(playerIdKey, id);
    return id;
  }

  function getOrCreatePlayerName() {
    const saved = storage.getItem(playerNameKey)?.trim();
    if (saved) return saved;
    const suffix = getOrCreatePlayerId().replaceAll("-", "").slice(0, 4);
    const name = `Player-${suffix.toUpperCase()}`;
    storage.setItem(playerNameKey, name);
    return name;
  }

  async function resolveCountryCode() {
    return normalizeCountryCode(await countryCodeResolver?.());
  }

  async function upsert(score) {
    await request(
      tableUrl({ on_conflict: "app_id,player_id,period" }),
      {
        method: "POST",
        headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
        body: JSON.stringify({
          app_id: namespace,
          player_id: getOrCreatePlayerId(),
          period: currentPeriod(),
          name: getOrCreatePlayerName(),
          country_code: await resolveCountryCode(),
          score,
          updated_at: new Date().toISOString(),
        }),
      },
    );
    invalidateCache();
  }

  async function activateCurrentPeriod() {
    const rows = await requestList({
      select: "player_id",
      app_id: `eq.${namespace}`,
      player_id: `eq.${getOrCreatePlayerId()}`,
      period: `eq.${currentPeriod()}`,
      limit: "1",
    });
    if (rows.length === 0) await upsert(0);
  }

  async function submitScore(totalScore) {
    if (!Number.isSafeInteger(totalScore) || totalScore < 0) {
      throw new Error("Score must be a non-negative integer.");
    }
    const rows = await requestList({
      select: "score",
      app_id: `eq.${namespace}`,
      player_id: `eq.${getOrCreatePlayerId()}`,
      period: `eq.${currentPeriod()}`,
      limit: "1",
    });
    if (rows[0]?.score >= totalScore) return;
    await upsert(totalScore);
  }

  async function updatePlayerName(rawName) {
    const name = namePolicy.sanitize(rawName);
    const playerId = getOrCreatePlayerId();
    const rows = await requestList({
      select: "player_id,name",
      app_id: `eq.${namespace}`,
      period: `eq.${currentPeriod()}`,
      name: `ilike.${name}`,
      limit: "2",
    });
    if (rows.some((row) => row.player_id !== playerId)) {
      throw new Error("That name is already taken.");
    }

    storage.setItem(playerNameKey, name);
    await activateCurrentPeriod();
    await request(
      tableUrl({
        app_id: `eq.${namespace}`,
        player_id: `eq.${playerId}`,
        period: `eq.${currentPeriod()}`,
      }),
      {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({
          name,
          updated_at: new Date().toISOString(),
        }),
      },
    );
    invalidateCache();
    return name;
  }

  async function fetchSnapshot({ forceRefresh = false } = {}) {
    const period = currentPeriod();
    if (
      !forceRefresh &&
      cache?.period === period &&
      Date.now() - cache.createdAt < cacheDurationMs
    ) {
      return cache.snapshot;
    }

    const rows = await requestList({
      select: "player_id,name,score,country_code,updated_at",
      app_id: `eq.${namespace}`,
      period: `eq.${period}`,
      order: "score.desc,updated_at.desc",
      limit: String(rankScanLimit),
    });
    const ranked = rows.map((row, index) => ({
      rank: index + 1,
      playerId: row.player_id ?? "",
      name: row.name?.trim() || "Player",
      score: Number(row.score) || 0,
      countryCode: normalizeCountryCode(row.country_code),
      updatedAt: row.updated_at,
    }));
    const snapshot = {
      entries: ranked.slice(0, topLimit),
      currentPlayer:
        ranked.find((row) => row.playerId === getOrCreatePlayerId()) ?? null,
    };
    cache = { period, createdAt: Date.now(), snapshot };
    return snapshot;
  }

  function invalidateCache() {
    cache = null;
  }

  return {
    activateCurrentPeriod,
    currentPeriod,
    fetchSnapshot,
    getOrCreatePlayerId,
    getOrCreatePlayerName,
    invalidateCache,
    submitScore,
    updatePlayerName,
  };
}
