class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.playerId,
    required this.name,
    required this.score,
    required this.updatedAt,
    this.countryCode,
  });

  final int rank;
  final String playerId;
  final String name;
  final int score;
  final DateTime updatedAt;
  final String? countryCode;

  factory LeaderboardEntry.fromJson(
    Map<String, dynamic> json, {
    required int rank,
  }) {
    return LeaderboardEntry(
      rank: rank,
      playerId: json['player_id'] as String? ?? '',
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Player',
      score: (json['score'] as num?)?.round() ?? 0,
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      countryCode: normalizeCountryCode(json['country_code'] as String?),
    );
  }
}

class LeaderboardSnapshot {
  const LeaderboardSnapshot({this.entries = const [], this.currentPlayer});

  final List<LeaderboardEntry> entries;
  final LeaderboardEntry? currentPlayer;
}

class LeaderboardException implements Exception {
  const LeaderboardException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class LeaderboardNameException extends LeaderboardException {
  const LeaderboardNameException(super.message);
}

String? normalizeCountryCode(String? code) {
  if (code == null) return null;
  final normalized = code.trim().toUpperCase();
  return RegExp(r'^[A-Z]{2}$').hasMatch(normalized) ? normalized : null;
}
