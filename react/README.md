# Leaderboard React

Drop-in monthly Supabase leaderboard for React apps and browser games.

## Features

- Anonymous browser player ID with no sign-up.
- Separate rankings per app through `namespace`.
- Monthly ranking periods.
- Ranking, flag, name, and formatted score.
- Current-player rank above the Top list.
- Editable unique names and replaceable profanity policy.
- Higher-score and lower-score ranking modes.
- Multiple boards inside one app through `scope`.
- Custom score formatting, including duration scores like `03:51`.
- Optional server endpoint mode for apps that should not talk to Supabase
  directly.
- Most recent player ranks first when scores are tied.
- Request cache and one-minute refresh cooldown.
- Hook, client, and ready-made UI can be used independently.
- Errors are displayed instead of hidden behind fallback data.

## 1. Create the database

Run [`supabase/leaderboard.sql`](supabase/leaderboard.sql) in Supabase SQL Editor.
The same table can serve multiple apps.

## 2. Install

```bash
npm install github:ivyparc/leaderboard
```

## 3. Configure

```jsx
import {
  createLeaderboardClient,
  Leaderboard,
} from "@ivyparc/leaderboard-react";
import "@ivyparc/leaderboard-react/styles.css";

const client = createLeaderboardClient({
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL,
  supabaseAnonKey: import.meta.env.VITE_SUPABASE_ANON_KEY,
  namespace: "my-game",
  scope: "global",
  countryCodeResolver: async () => "CA",
});

export function LeaderboardScreen() {
  return <Leaderboard client={client} onBack={() => history.back()} />;
}
```

Use a unique `namespace` for each app or game so their data never mixes. Use
`scope` for separate boards inside the same app, such as `toronto-line-1` and
`toronto-line-2`.

For time-attack games where a lower score is better:

```jsx
import {
  Leaderboard,
  createLeaderboardClient,
  formatDurationScore,
} from "@ivyparc/leaderboard-react";

const client = createLeaderboardClient({
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL,
  supabaseAnonKey: import.meta.env.VITE_SUPABASE_ANON_KEY,
  namespace: "subway-master",
  scope: "toronto-line-1",
  scoreOrder: "lower",
  activationScore: null,
});

export function LeaderboardScreen() {
  return (
    <Leaderboard
      client={client}
      scoreLabel="Time"
      formatScore={formatDurationScore}
    />
  );
}
```

## 4. Submit the total score

```js
await client.submitScore(totalMissionScore);
```

To make a player appear in the current month after opening the app once:

```js
await client.activateCurrentPeriod();
```

## Use only the data layer

```js
const snapshot = await client.fetchSnapshot();
console.log(snapshot.entries, snapshot.currentPlayer);
```

Or use `useLeaderboard(client)` and build your own screen.

## Server endpoint mode

If a production app should send requests to your own server instead of using a
Supabase anon key directly, configure `endpoint`:

```js
const client = createLeaderboardClient({
  endpoint: "https://example.com/api/leaderboard",
  namespace: "my-game",
  scope: "global",
});
```

The endpoint should accept:

- `GET ?namespace=&scope=&playerId=&limit=` and return `{ entries, currentPlayer }`
  or `{ entries, playerEntry }`.
- `POST` with `{ namespace, scope, playerId, playerName, score, countryCode }`.
- `PATCH` with `{ namespace, scope, playerId, playerName }`.

For React Native or Expo apps, use this data client with a storage object that
implements `getItem` and `setItem`, such as a small `AsyncStorage` adapter, then
build a native screen with `useLeaderboard(client)`.

## Environment

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Supabase anon keys are client-side keys. RLS policies remain responsible for
database access control.

## Important security boundary

This module accepts scores from the client. Use it for low-stakes games and
prototypes. Prize-based or competitive games should validate score submissions
in a trusted server or Supabase Edge Function.
