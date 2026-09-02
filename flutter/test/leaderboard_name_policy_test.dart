import 'package:flutter_test/flutter_test.dart';
import 'package:leaderboard_flutter/leaderboard_flutter.dart';

void main() {
  test('sanitizes whitespace', () {
    const policy = LeaderboardNamePolicy();
    expect(policy.sanitize('  Ivy   Park  '), 'Ivy Park');
  });

  test('blocks normalized profanity', () {
    const policy = LeaderboardNamePolicy();
    expect(() => policy.sanitize('f.u.c.k'), throwsFormatException);
  });

  test('formats monthly period', () {
    expect(monthlyPeriod(DateTime.utc(2026, 6, 23)), '2026-06');
  });

  test('compares higher and lower scores', () {
    const higher = LeaderboardConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabaseAnonKey: 'anon',
      table: 'scores',
      namespace: 'game',
    );
    const lower = LeaderboardConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabaseAnonKey: 'anon',
      table: 'scores',
      namespace: 'game',
      scoreOrder: LeaderboardScoreOrder.lower,
    );

    expect(higher.isBetterScore(12, 10), isTrue);
    expect(higher.isBetterScore(8, 10), isFalse);
    expect(lower.isBetterScore(8, 10), isTrue);
    expect(lower.isBetterScore(12, 10), isFalse);
  });

  test('formats duration scores as mm:ss', () {
    expect(formatDurationScore(0), '00:00');
    expect(formatDurationScore(231), '03:51');
    expect(formatDurationScore(623), '10:23');
  });
}
