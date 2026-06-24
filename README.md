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
- Monthly ranking periods.
- Ranking, country flag, editable name, and formatted score.
- Current-player rank displayed separately above the Top list.
- Unique player names per app and month.
- Replaceable profanity filter.
- Higher scores rank first.
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
