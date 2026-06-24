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
}
