import { useCallback, useEffect, useState } from "react";

export function useLeaderboard(client, { refreshCooldownMs = 60_000 } = {}) {
  const [snapshot, setSnapshot] = useState(null);
  const [playerName, setPlayerName] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [refreshLocked, setRefreshLocked] = useState(false);

  const load = useCallback(
    async ({ forceRefresh = false } = {}) => {
      setLoading(true);
      setError(null);
      try {
        setPlayerName(await client.getOrCreatePlayerName());
        await client.activateCurrentPeriod();
        setSnapshot(await client.fetchSnapshot({ forceRefresh }));
      } catch (loadError) {
        setError(loadError);
      } finally {
        setLoading(false);
      }
    },
    [client],
  );

  useEffect(() => {
    load();
  }, [load]);

  const refresh = useCallback(async () => {
    if (refreshLocked) return;
    setRefreshLocked(true);
    window.setTimeout(() => setRefreshLocked(false), refreshCooldownMs);
    await load({ forceRefresh: true });
  }, [load, refreshCooldownMs, refreshLocked]);

  const updateName = useCallback(
    async (name) => {
      const saved = await client.updatePlayerName(name);
      setPlayerName(saved);
      await load({ forceRefresh: true });
    },
    [client, load],
  );

  return {
    error,
    loading,
    playerName,
    refresh,
    refreshLocked,
    snapshot,
    updateName,
  };
}
