# Leaderboard Flutter

Drop-in monthly leaderboard for Flutter apps and games using Supabase.

## Features

- Anonymous local player ID. No sign-up, Apple login, or Google login.
- App-specific data isolation through `namespace`.
- Monthly ranking periods.
- Ranking, flag, name, and formatted score.
- Current-player rank above the Top list.
- Editable unique names with a replaceable profanity policy.
- Score tie-breaker: most recently achieved score ranks first.
- 45-second cache and one-minute refresh cooldown.
- UI widget and data client can be used independently.
- Errors are surfaced. The package does not invent fallback data.

## 1. Create the database

Run [`supabase/leaderboard.sql`](supabase/leaderboard.sql) in Supabase SQL Editor.
One table can serve many apps because every row includes `app_id`.

## 2. Add the package

```yaml
dependencies:
  leaderboard_flutter:
    git:
      url: https://github.com/ivyparc/leaderboard.git
      path: flutter
```

## 3. Configure once

```dart
final leaderboard = LeaderboardClient(
  config: LeaderboardConfig(
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    table: 'app_leaderboard_scores',
    namespace: 'my-game',
    countryCodeResolver: () async => 'CA',
  ),
);
```

Use a different `namespace` for every app or game. That keeps rankings separate
even when all apps use the same Supabase project and table.

## 4. Add the screen

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => LeaderboardView(client: leaderboard),
  ),
);
```

## 5. Submit the total score

```dart
await leaderboard.submitScore(totalMissionScore);
```

Call `activateCurrentPeriod()` when the app opens if players should appear in
the current month after opening the app once.

```dart
await leaderboard.activateCurrentPeriod();
```

## Build configuration

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

The anon key is intended for client use. Database permissions must still be
controlled with Supabase RLS policies.

## Important security boundary

This lightweight module trusts scores sent by the client. That is suitable for
small casual games, prototypes, and low-stakes leaderboards. Competitive or
prize-based games should submit scores through a trusted server or Edge
Function that validates gameplay.
