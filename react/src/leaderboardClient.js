import { createNamePolicy } from "./namePolicy.js";
import {
  createAnonymousPlayerId,
  isBetterScore,
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
  let cache = null;

  const headers = {
    apikey: supabaseAnonKey,
    Authorization: `Bearer ${supabaseAnonKey}`,
    "Content-Type": "application/json",
  };

  async function rpc(action, params) {
    if (endpointUrl) {
      const payload = await requestEndpointJson({}, {
        method: "POST", body: JSON.stringify({ action, namespace, scope, ...params }),
      });
      const value = payload?.[action === "leaderboard_name" ? "playerName" : "period"];
      if (typeof value !== "string" || !value) throw new Error("Endpoint must implement name reservation and ranking periods.");
      return value;
    }
    const response = await request(`${projectUrl}/rest/v1/rpc/${action}`, {
      method: "POST", body: JSON.stringify({ p_app_id: namespace, p_scope: scope, ...params }),
    });
    return response.json();
  }

  async function currentPeriod() {
    return rpc("leaderboard_period", {});
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

  async function getOrCreatePlayerName() {
    const name = await rpc("leaderboard_name", endpointUrl
      ? { playerId: getOrCreatePlayerId() }
      : { p_player_id: getOrCreatePlayerId() });
    storage.setItem(playerNameKey, name);
    return name;
  }

  async function resolveCountryCode() {
    return normalizeCountryCode(await countryCodeResolver?.());
  }

  async function upsert(score, period) {
    if (endpointUrl) {
      await requestEndpointJson(
        {},
        {
          method: "POST",
          body: JSON.stringify({
            period,
            countryCode: await resolveCountryCode(),
            namespace,
            playerId: getOrCreatePlayerId(),
            playerName: await getOrCreatePlayerName(),
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
          period,
          scope,
          name: await getOrCreatePlayerName(),
          country_code: await resolveCountryCode(),
          score,
          updated_at: new Date().toISOString(),
        }),
      },
    );
    invalidateCache();
  }

  // Kept for source compatibility. Opening a board never creates a score.
  async function activateCurrentPeriod() { await currentPeriod(); }

  async function submitScore(totalScore, { completedAt = new Date().toISOString() } = {}) {
    const playedMonth = new Date(completedAt).toISOString().slice(0, 7);
    const period = await currentPeriod();
    if (playedMonth !== period) throw new Error("Gameplay belongs to an expired ranking period.");
    if (!Number.isSafeInteger(totalScore) || totalScore < 0) {
      throw new Error("Score must be a non-negative integer.");
    }
    if (endpointUrl) {
      await upsert(totalScore, period);
      rememberScore(period, totalScore);
      return;
    }

    const rows = await requestList({
      select: "score",
      app_id: `eq.${namespace}`,
      scope: `eq.${scope}`,
      player_id: `eq.${getOrCreatePlayerId()}`,
      period: `eq.${period}`,
      limit: "1",
    });
    if (!isBetterScore(totalScore, rows[0]?.score, normalizedScoreOrder)) return;
    await upsert(totalScore, period);
      rememberScore(period, totalScore);
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

    await rpc('leaderboard_rename', { p_player_id: playerId, p_name: name });
    storage.setItem(playerNameKey, name);
    invalidateCache();
    return name;
  }

  async function fetchSnapshot({ forceRefresh = false } = {}) {
    if (endpointUrl) {
      return fetchEndpointSnapshot({ forceRefresh });
    }

    const period = await currentPeriod();
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
    decorateSnapshot(snapshot, period);
    cache = { period, createdAt: Date.now(), snapshot };
    return snapshot;
  }

  async function fetchEndpointSnapshot({ forceRefresh = false } = {}) {
    const period = await currentPeriod();
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
    decorateSnapshot(snapshot, period);
    cache = { period, createdAt: Date.now(), snapshot };
    return snapshot;
  }

  function personalRecord(period) {
    const key = `${storagePrefix}.${getOrCreatePlayerId()}.personal.v1`;
    const state = JSON.parse(storage.getItem(key) || 'null') || { period, current: null, previous: null };
    if (state.period !== period) {
      if (state.current !== null && isBetterScore(state.current, state.previous, normalizedScoreOrder)) state.previous = state.current;
      state.current = null;
      state.period = period;
    }
    return { key, state };
  }
  function rememberScore(period, score) {
    const { key, state } = personalRecord(period);
    if (isBetterScore(score, state.current, normalizedScoreOrder)) state.current = score;
    storage.setItem(key, JSON.stringify(state));
  }
  function decorateSnapshot(snapshot, period) {
    const { key, state } = personalRecord(period);
    if (snapshot.currentPlayer && isBetterScore(snapshot.currentPlayer.score, state.current, normalizedScoreOrder)) state.current = snapshot.currentPlayer.score;
    storage.setItem(key, JSON.stringify(state));
    snapshot.previousScore = state.previous;
    snapshot.showPrevious = !!snapshot.currentPlayer && state.previous !== null &&
      isBetterScore(state.previous, snapshot.currentPlayer.score, normalizedScoreOrder);
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
