# Leaderboard

Reusable Supabase leaderboard modules for Flutter and React apps and games.

This repository is designed like a building block: configure a Supabase project,
choose a unique app namespace, and add either the ready-made leaderboard screen
or only the data client to an existing app.

## Modules

- [`flutter/`](flutter/): Flutter package, widget, client, example, and tests.
- [`react/`](react/): React component, hook, client, demo, and tests.
- [`flutter/supabase/leaderboard.sql`](flutter/supabase/leaderboard.sql):
  shared database schema and RLS policies.

Both modules use the same database contract and can share one Supabase project.
The `namespace` value keeps each app's leaderboard data separate.

## Included behavior

- Anonymous local player ID without sign-up or social login.
- Rankings reset at every UTC month boundary, regardless of participant count.
- Ranking, country flag, editable name, and formatted score.
- Current-player rank displayed separately above the Top list.
- Reserved, case-insensitive unique player names per app and scope across periods.
- Replaceable profanity filter.
- Higher-score and lower-score ranking modes.
- Multiple boards inside one app through `scope`.
- Custom score formatting, including duration scores like `03:51`.
- Optional server endpoint mode for apps that should not talk to Supabase
  directly.
- When scores match, the most recently achieved score ranks first.
- Cached reads and a one-minute refresh cooldown.
- Errors are reported directly instead of being replaced with fallback data.

## Database setup

1. Open Supabase SQL Editor.
2. Run [`flutter/supabase/leaderboard.sql`](flutter/supabase/leaderboard.sql).
3. Give every app a different `namespace`.

One table can then serve multiple apps:

```text
my-space-game
my-puzzle-game
my-web-game
```

Use `scope` when one app needs more than one board:

```text
subway-master / toronto-line-1
subway-master / toronto-line-2
subway-master / new-york-a
```

## Flutter install

```yaml
dependencies:
  leaderboard_flutter:
    git:
      url: https://github.com/ivyparc/leaderboard.git
      path: flutter
```

See [`flutter/README.md`](flutter/README.md) for configuration and usage.

## React install

```bash
npm install github:ivyparc/leaderboard
```

```jsx
import {
  createLeaderboardClient,
  Leaderboard,
} from "@ivyparc/leaderboard-react";
import "@ivyparc/leaderboard-react/styles.css";
```

See [`react/README.md`](react/README.md) for configuration and usage.

## Security boundary

This lightweight module accepts scores sent by the client. It is appropriate
for casual games, prototypes, and low-stakes leaderboards. Competitive or
prize-based games should validate score submissions in a trusted server or
Supabase Edge Function.

## Monthly reset migration

Apply `react/supabase/leaderboard.sql` (identical to the Flutter copy), then enable
Supabase Cron and run `react/supabase/monthly-cron.sql`. The cron job is required
so expired scores are deleted even with no connected clients. Check the job's run
history after deployment. The period RPC also purges expired scores on access;
RLS immediately hides them at the UTC boundary. There is no score archive.

Only gameplay completed after reset may be submitted. Pass `completedAt` when
submitting a delayed result (React: `submitScore(score, {completedAt})`; Flutter:
`submitScore(score, completedAt: completedAt)`). Capture it at gameplay completion. Never pass an all-time
best or replay an offline result from an earlier month to `submitScore`.
`activateCurrentPeriod` is now read-only, including when activationScore is set.
Opening the board or editing a name does not register a score.

The clients retain a private personal comparison in local storage (one previous
best plus the current period best), never upload it, and never add it to Top rows.
After reset, the personal card says **Your Previous Record** and has no rank.
A new worse result shows its current rank and **Previous: old score** below it;
a better or equal result shows only the current result. Both score orders work.
This requires the record to have been observed/submitted by the updated client
before reset. A new device cannot retrieve deleted records from the server.

Names remain reserved separately across resets. Migration deletes historical
score rows; deploy it before the updated clients. Do not restore an old SQL copy
that retains historical score rows or the former participant threshold behavior.

New names are reserved in PostgreSQL using column A + column B + two digits
(`00`–`99`) from [the supplied word list](https://docs.google.com/spreadsheets/d/1rWnv_2oI662TNBFDXsbGGtDg_PWXUxNPeYjME_TCSSM/edit?gid=1764333573).
`shared/username-words.csv` is the source snapshot (2026-09-09); SQL embeds both
columns independently, ignoring blank cells. Sheet edits require updating the SQL
arrays and deploying the migration. Names support up to 32 characters to avoid
truncating longer combinations. Generation checks availability before reserving;
a case-insensitive unique index also prevents concurrent duplicate reservations.
Names remain reserved across resets. Historical duplicate names across months
are resolved on the affected player's next name request; historical score rows are deleted by the monthly reset migration.

Custom endpoint servers must implement period and name reservation actions:

- `{action: "leaderboard_period", namespace, scope}` → `{period: "YYYY-MM"}`.
- `{action: "leaderboard_name", namespace, scope, playerId}` → `{playerName: "AzureBison53"}`.

Score POSTs include `period`; reject expired periods rather than assigning an old
submission to a new month. Read/write only the active month, delete expired rows,
and update name reservations atomically on PATCH. The endpoint implementation is
outside this repository. Anonymous clients are not authoritative proof of when
gameplay occurred; competitive games need server-validated gameplay sessions.

## Future administrator page

Existing users can be moderated later using `(app_id, scope, player_id)`, even
after a ranking reset. Usernames are mutable and must not be the moderation key.
A future administrator backend should persist bans separately from period scores,
filter banned users from ranking reads, reject their writes, and support forced
renames. No admin page or ban enforcement is added by this migration.

The current anonymous ID is stored locally, and existing anonymous RLS allows broad
score updates. It does not prove player identity. Before relying on bans, introduce
authenticated ownership (or a trusted server identity), restrictive RLS, and an
admin-only authorization boundary. Clearing local app data can create a new ID;
reliable account-wide bans need a durable account identity.

Validation: `node --test react/test/*.test.js`. Database integration tests:
install `@electric-sql/pglite` in a temporary directory, then run
`PGLITE_MODULE=/absolute/path/to/pglite/dist/index.js node --test test/database.mjs`.
