import { createNamePolicy } from "./namePolicy.js";
import {
  createAnonymousPlayerId,
  isBetterScore,
  monthlyPeriod,
  normalizeCountryCode,
  normalizeScoreOrder,
} from "./utils.js";

export function createLeaderboardClient({
  endpoint,
  supabaseUrl,
  supabaseAnonKey,
  table = "app_leaderboard_scores",
  namespace,
  scope = "default",
  scoreOrder = "higher",
  activationScore = 0,
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
  if (!endpoint && (!supabaseUrl || !supabaseAnonKey)) {
    throw new Error(
      "Either endpoint or supabaseUrl and supabaseAnonKey are required.",
    );
  }
  if (!namespace) throw new Error("namespace is required.");
  if (!scope) throw new Error("scope is required.");
  if (!storage) throw new Error("A storage implementation is required.");
  if (!fetchImpl) throw new Error("A fetch implementation is required.");

  const projectUrl = supabaseUrl
    ?.trim()
    .replace(/\/rest\/v1\/?$/, "")
    .replace(/\/$/, "");
  const endpointUrl = endpoint?.trim().replace(/\/$/, "");
  const normalizedScoreOrder = normalizeScoreOrder(scoreOrder);
  const storagePrefix = `${namespace}.${scope}.leaderboard`;
  const playerIdKey = `${storagePrefix}.playerId.v1`;
  const playerNameKey = `${storagePrefix}.playerName.v1`;
  const legacyPlayerIdKey = `${namespace}.leaderboard.playerId.v1`;
  const legacyPlayerNameKey = `${namespace}.leaderboard.playerName.v1`;
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

  function endpointUrlWithParams(params = {}) {
    const url = new URL(
      endpointUrl,
      globalThis.location?.origin ?? "http://localhost",
    );
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        url.searchParams.set(key, value);
      }
    });
    return url;
  }

  async function request(url, options = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), requestTimeoutMs);
    try {
      const response = await fetchImpl(url, {
        ...options,
        headers: {
          ...(endpointUrl ? { "Content-Type": "application/json" } : headers),
          ...options.headers,
        },
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

  async function requestEndpointJson(params = {}, options = {}) {
    const response = await request(endpointUrlWithParams(params), options);
    const text = await response.text();
    if (!text.trim()) return null;
    return JSON.parse(text);
  }

  function getOrCreatePlayerId() {
    const saved = storage.getItem(playerIdKey);
    if (saved) return saved;
    const legacy =
      scope === "default" ? storage.getItem(legacyPlayerIdKey) : null;
    if (legacy) {
      storage.setItem(playerIdKey, legacy);
      return legacy;
    }
    const id = createAnonymousPlayerId();
    storage.setItem(playerIdKey, id);
    return id;
  }

  function getOrCreatePlayerName() {
    const saved = storage.getItem(playerNameKey)?.trim();
    if (saved) return saved;
    const legacy =
      scope === "default" ? storage.getItem(legacyPlayerNameKey)?.trim() : null;
    if (legacy) {
      storage.setItem(playerNameKey, legacy);
      return legacy;
    }
    const suffix = getOrCreatePlayerId().replaceAll("-", "").slice(0, 4);
    const name = `Player-${suffix.toUpperCase()}`;
    storage.setItem(playerNameKey, name);
    return name;
  }

  async function resolveCountryCode() {
    return normalizeCountryCode(await countryCodeResolver?.());
  }

  async function upsert(score) {
    if (endpointUrl) {
      await requestEndpointJson(
        {},
        {
          method: "POST",
          body: JSON.stringify({
            countryCode: await resolveCountryCode(),
            namespace,
            playerId: getOrCreatePlayerId(),
            playerName: getOrCreatePlayerName(),
            score,
            scope,
          }),
        },
      );
      invalidateCache();
      return;
    }

    await request(
      tableUrl({ on_conflict: "app_id,scope,player_id,period" }),
      {
        method: "POST",
        headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
        body: JSON.stringify({
          app_id: namespace,
          player_id: getOrCreatePlayerId(),
          period: currentPeriod(),
          scope,
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
    if (activationScore === null || activationScore === undefined) {
      return;
    }

    if (endpointUrl) {
      await requestEndpointJson(
        {},
        {
          method: "POST",
          body: JSON.stringify({
            countryCode: await resolveCountryCode(),
            namespace,
            playerId: getOrCreatePlayerId(),
            playerName: getOrCreatePlayerName(),
            score: activationScore,
            scope,
          }),
        },
      );
      invalidateCache();
      return;
    }

    const rows = await requestList({
      select: "player_id",
      app_id: `eq.${namespace}`,
      scope: `eq.${scope}`,
      player_id: `eq.${getOrCreatePlayerId()}`,
      period: `eq.${currentPeriod()}`,
      limit: "1",
    });
    if (rows.length === 0) await upsert(activationScore);
  }

  async function submitScore(totalScore) {
    if (!Number.isSafeInteger(totalScore) || totalScore < 0) {
      throw new Error("Score must be a non-negative integer.");
    }
    if (endpointUrl) {
      await upsert(totalScore);
      return;
    }

    const rows = await requestList({
      select: "score",
      app_id: `eq.${namespace}`,
      scope: `eq.${scope}`,
      player_id: `eq.${getOrCreatePlayerId()}`,
      period: `eq.${currentPeriod()}`,
      limit: "1",
    });
    if (!isBetterScore(totalScore, rows[0]?.score, normalizedScoreOrder)) return;
    await upsert(totalScore);
  }

  async function updatePlayerName(rawName) {
    const name = namePolicy.sanitize(rawName);
    const playerId = getOrCreatePlayerId();

    if (endpointUrl) {
      const payload = await requestEndpointJson(
        {},
        {
          method: "PATCH",
          body: JSON.stringify({
            namespace,
            playerId,
            playerName: name,
            scope,
          }),
        },
      );
      const savedName = payload?.playerName ?? name;
      storage.setItem(playerNameKey, savedName);
      invalidateCache();
      return savedName;
    }

    const rows = await requestList({
      select: "player_id,name",
      app_id: `eq.${namespace}`,
      scope: `eq.${scope}`,
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
        scope: `eq.${scope}`,
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
    if (endpointUrl) {
      return fetchEndpointSnapshot({ forceRefresh });
    }

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
      scope: `eq.${scope}`,
      period: `eq.${period}`,
      order: `score.${normalizedScoreOrder === "lower" ? "asc" : "desc"},updated_at.desc`,
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

  async function fetchEndpointSnapshot({ forceRefresh = false } = {}) {
    const period = currentPeriod();
    if (
      !forceRefresh &&
      cache?.period === period &&
      Date.now() - cache.createdAt < cacheDurationMs
    ) {
      return cache.snapshot;
    }

    const payload = await requestEndpointJson({
      limit: String(topLimit),
      namespace,
      playerId: getOrCreatePlayerId(),
      scope,
    });
    if (!payload || !Array.isArray(payload.entries)) {
      throw new Error("Leaderboard returned invalid data.");
    }
    const mapEntry = (entry) => ({
      rank: Number(entry.rank) || 0,
      playerId: entry.playerId ?? entry.player_id ?? "",
      name: entry.name ?? entry.playerName ?? entry.player_name ?? "Player",
      score: Number(entry.score ?? entry.elapsedSeconds) || 0,
      countryCode: normalizeCountryCode(
        entry.countryCode ?? entry.country_code,
      ),
      updatedAt: entry.updatedAt ?? entry.updated_at ?? entry.submittedAt,
    });
    const snapshot = {
      entries: payload.entries.map(mapEntry),
      currentPlayer: payload.currentPlayer
        ? mapEntry(payload.currentPlayer)
        : payload.playerEntry
          ? mapEntry(payload.playerEntry)
          : null,
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
    fetchEndpointSnapshot,
    getOrCreatePlayerId,
    getOrCreatePlayerName,
    invalidateCache,
    submitScore,
    updatePlayerName,
  };
}
