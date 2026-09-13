import { useState } from "react";

import { useLeaderboard } from "./useLeaderboard.js";
import { flagEmoji, formatLeaderboardScore } from "./utils.js";
import "./styles.css";

export function Leaderboard({
  client,
  title = "Leaderboard",
  scoreLabel = "Score",
  formatScore = formatLeaderboardScore,
  onBack,
  className = "",
}) {
  const {
    error,
    loading,
    playerName,
    refresh,
    refreshLocked,
    snapshot,
    updateName,
  } = useLeaderboard(client);
  const [editing, setEditing] = useState(false);
  const [draftName, setDraftName] = useState(playerName);
  const [nameError, setNameError] = useState(null);

  async function saveName(event) {
    event.preventDefault();
    setNameError(null);
    try {
      await updateName(draftName);
      setEditing(false);
    } catch (saveError) {
      setNameError(saveError.message);
    }
  }

  return (
    <section className={`leaderboard ${className}`}>
      <header className="leaderboard__toolbar">
        <button
          type="button"
          className="leaderboard__icon-button"
          onClick={onBack}
          aria-label="Back"
        >
          ←
        </button>
        <h1>{title}</h1>
        <button
          type="button"
          className="leaderboard__icon-button"
          onClick={refresh}
          disabled={refreshLocked}
          aria-label="Refresh"
        >
          ↻
        </button>
      </header>

      <div className="leaderboard__name-area">
        <button
          type="button"
          className="leaderboard__name-button"
          onClick={() => {
            setDraftName(playerName);
            setEditing(true);
          }}
        >
          ✎ {playerName}
        </button>
      </div>

      {loading && <Status title="Loading leaderboard" />}
      {error && (
        <Status title="Leaderboard unavailable" body={error.message} />
      )}
      {!loading &&
        !error &&
        snapshot?.entries.length === 0 &&
        !snapshot.currentPlayer && (
          <Status
            title="No scores yet"
            body="Play once to enter this period ranking."
          />
        )}

      {!loading && !error && snapshot && (
        <div className="leaderboard__content">
          {snapshot.currentPlayer && (
            <Entry
              entry={snapshot.currentPlayer}
              formatScore={formatScore}
              label="Your Rank"
              previousScore={snapshot.showPrevious ? snapshot.previousScore : null}
              highlighted
            />
          )}
          {!snapshot.currentPlayer && snapshot.previousScore !== null && (
            <Entry entry={{ rank: null, name: playerName, score: snapshot.previousScore }}
              label="Your Previous Record" formatScore={formatScore} highlighted />
          )}
          <div className="leaderboard__header leaderboard__grid">
            <span>Rank</span>
            <span aria-hidden="true" />
            <span>Name</span>
            <span>{scoreLabel}</span>
          </div>
          <div className="leaderboard__list">
            {snapshot.entries.map((entry) => (
              <Entry
                key={entry.playerId}
                entry={entry}
                formatScore={formatScore}
                highlighted={entry.rank <= 3}
              />
            ))}
          </div>
        </div>
      )}

      {editing && (
        <div className="leaderboard__modal-backdrop" role="presentation">
          <form className="leaderboard__modal" onSubmit={saveName}>
            <h2>Edit Name</h2>
            <input
              autoFocus
              maxLength={32}
              value={draftName}
              onChange={(event) => setDraftName(event.target.value)}
            />
            {nameError && <p className="leaderboard__error">{nameError}</p>}
            <div className="leaderboard__modal-actions">
              <button type="button" onClick={() => setEditing(false)}>
                Cancel
              </button>
              <button type="submit">Save</button>
            </div>
          </form>
        </div>
      )}
    </section>
  );
}

function Entry({
  entry,
  formatScore = formatLeaderboardScore,
  highlighted = false,
  label,
  previousScore = null,
}) {
  return (
    <article
      className={`leaderboard__entry ${highlighted ? "is-highlighted" : ""}`}
    >
      {label && <strong className="leaderboard__entry-label">{label}</strong>}
      <div className="leaderboard__grid">
        <strong>{entry.rank == null ? "" : `#${entry.rank}`}</strong>
        <span className="leaderboard__flag">
          {flagEmoji(entry.countryCode)}
        </span>
        <strong className="leaderboard__player-name">{entry.name}</strong>
        <strong className="leaderboard__score">
          {formatScore(entry.score)}
        </strong>
      </div>
      {previousScore !== null && <small>Previous: {formatScore(previousScore)}</small>}
    </article>
  );
}

function Status({ title, body }) {
  return (
    <div className="leaderboard__status">
      <strong>{title}</strong>
      {body && <span>{body}</span>}
    </div>
  );
}
