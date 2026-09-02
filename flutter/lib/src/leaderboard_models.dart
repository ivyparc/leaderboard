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

  factory LeaderboardEntry.fromEndpointJson(Map<String, dynamic> json) {
    final rawName = json['name'] ?? json['playerName'] ?? json['player_name'];
    final rawPlayerId = json['playerId'] ?? json['player_id'];
    final rawScore = json['score'] ?? json['elapsedSeconds'];
    final rawCountryCode = json['countryCode'] ?? json['country_code'];
    final rawUpdatedAt =
        json['updatedAt'] ?? json['updated_at'] ?? json['submittedAt'];

    return LeaderboardEntry(
      rank: (json['rank'] as num?)?.round() ?? 0,
      playerId: rawPlayerId as String? ?? '',
      name: rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : 'Player',
      score: (rawScore as num?)?.round() ?? 0,
      updatedAt: DateTime.tryParse(rawUpdatedAt as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      countryCode: normalizeCountryCode(rawCountryCode as String?),
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
