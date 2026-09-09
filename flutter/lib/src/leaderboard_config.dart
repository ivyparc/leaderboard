typedef CountryCodeResolver = Future<String?> Function();
typedef PeriodResolver = String Function(DateTime now);
typedef LeaderboardScoreFormatter = String Function(int score);

enum LeaderboardScoreOrder { higher, lower }

class LeaderboardConfig {
  const LeaderboardConfig({
    this.endpoint,
    this.supabaseUrl,
    this.supabaseAnonKey,
    required this.table,
    required this.namespace,
    this.scope = 'default',
    this.scoreOrder = LeaderboardScoreOrder.higher,
    this.activationScore = 0,
    this.topLimit = 100,
    this.rankScanLimit = 500,
    this.nameMaxLength = 32,
    this.cacheDuration = const Duration(seconds: 45),
    this.requestTimeout = const Duration(seconds: 8),
    this.refreshCooldown = const Duration(minutes: 1),
    this.countryCodeResolver,
    this.periodResolver = monthlyPeriod,
  });

  final String? endpoint;
  final String? supabaseUrl;
  final String? supabaseAnonKey;
  final String table;
  final String namespace;
  final String scope;
  final LeaderboardScoreOrder scoreOrder;
  final int? activationScore;
  final int topLimit;
  final int rankScanLimit;
  final int nameMaxLength;
  final Duration cacheDuration;
  final Duration requestTimeout;
  final Duration refreshCooldown;
  final CountryCodeResolver? countryCodeResolver;
  final PeriodResolver periodResolver;

  String get projectUrl {
    if (supabaseUrl == null || supabaseUrl!.trim().isEmpty) {
      throw const LeaderboardConfigException(
        'supabaseUrl is required when endpoint is not configured.',
      );
    }
    var value = supabaseUrl!.trim();
    value = value.replaceFirst(RegExp(r'/rest/v1/?$'), '');
    return value.replaceFirst(RegExp(r'/$'), '');
  }

  String get requiredAnonKey {
    if (supabaseAnonKey == null || supabaseAnonKey!.trim().isEmpty) {
      throw const LeaderboardConfigException(
        'supabaseAnonKey is required when endpoint is not configured.',
      );
    }
    return supabaseAnonKey!;
  }

  bool get usesEndpoint => endpoint != null && endpoint!.trim().isNotEmpty;

  bool isBetterScore(int nextScore, num? previousScore) {
    if (previousScore == null) return true;
    return scoreOrder == LeaderboardScoreOrder.lower
        ? nextScore < previousScore
        : nextScore > previousScore;
  }

  static String monthlyPeriod(DateTime now) {
    final utc = now.toUtc();
    return '${utc.year}-${utc.month.toString().padLeft(2, '0')}';
  }
}

String monthlyPeriod(DateTime now) => LeaderboardConfig.monthlyPeriod(now);

class LeaderboardConfigException implements Exception {
  const LeaderboardConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

String formatLeaderboardScore(int score) => score.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );

String formatDurationScore(int totalSeconds) {
  final seconds = totalSeconds < 0 ? 0 : totalSeconds;
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}
