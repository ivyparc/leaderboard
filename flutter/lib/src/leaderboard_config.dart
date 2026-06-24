typedef CountryCodeResolver = Future<String?> Function();
typedef PeriodResolver = String Function(DateTime now);

class LeaderboardConfig {
  const LeaderboardConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.table,
    required this.namespace,
    this.topLimit = 100,
    this.rankScanLimit = 500,
    this.nameMaxLength = 16,
    this.cacheDuration = const Duration(seconds: 45),
    this.requestTimeout = const Duration(seconds: 8),
    this.refreshCooldown = const Duration(minutes: 1),
    this.countryCodeResolver,
    this.periodResolver = monthlyPeriod,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String table;
  final String namespace;
  final int topLimit;
  final int rankScanLimit;
  final int nameMaxLength;
  final Duration cacheDuration;
  final Duration requestTimeout;
  final Duration refreshCooldown;
  final CountryCodeResolver? countryCodeResolver;
  final PeriodResolver periodResolver;

  String get projectUrl {
    var value = supabaseUrl.trim();
    value = value.replaceFirst(RegExp(r'/rest/v1/?$'), '');
    return value.replaceFirst(RegExp(r'/$'), '');
  }

  static String monthlyPeriod(DateTime now) {
    final utc = now.toUtc();
    return '${utc.year}-${utc.month.toString().padLeft(2, '0')}';
  }
}

String monthlyPeriod(DateTime now) => LeaderboardConfig.monthlyPeriod(now);
