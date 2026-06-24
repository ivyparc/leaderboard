import 'package:flutter/material.dart';
import 'package:leaderboard_flutter/leaderboard_flutter.dart';

void main() {
  final client = LeaderboardClient(
    config: LeaderboardConfig(
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      table: 'app_leaderboard_scores',
      namespace: 'example-game',
      countryCodeResolver: () async => 'CA',
    ),
  );
  runApp(MaterialApp(home: LeaderboardView(client: client)));
}
