import 'dart:convert';

import 'package:http/http.dart' as http;

import 'leaderboard_config.dart';
import 'leaderboard_models.dart';
import 'leaderboard_name_policy.dart';
import 'leaderboard_storage.dart';

class LeaderboardClient {
  LeaderboardClient({
    required this.config,
    LeaderboardStorage? storage,
    LeaderboardNamePolicy? namePolicy,
    http.Client? httpClient,
  }) : storage = storage ?? const SharedPreferencesLeaderboardStorage(),
       namePolicy =
           namePolicy ?? LeaderboardNamePolicy(maxLength: config.nameMaxLength),
       _httpClient = httpClient ?? http.Client();

  final LeaderboardConfig config;
  final LeaderboardStorage storage;
  final LeaderboardNamePolicy namePolicy;
  final http.Client _httpClient;

  LeaderboardSnapshot? _cachedSnapshot;
  DateTime? _cachedAt;
  String? _cachedPeriod;

  String get _playerIdKey => '${config.namespace}.leaderboard.playerId.v1';
  String get _playerNameKey => '${config.namespace}.leaderboard.playerName.v1';
  String get currentPeriod => config.periodResolver(DateTime.now());

  Map<String, String> get _headers => {
    'apikey': config.supabaseAnonKey,
    'Authorization': 'Bearer ${config.supabaseAnonKey}',
    'Content-Type': 'application/json',
  };

  Uri _tableUri([Map<String, String>? query]) {
    return Uri.parse(
      '${config.projectUrl}/rest/v1/${config.table}',
    ).replace(queryParameters: query);
  }

  Future<String> getOrCreatePlayerId() async {
    final saved = await storage.read(_playerIdKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final id = createAnonymousPlayerId();
    await storage.write(_playerIdKey, id);
    return id;
  }

  Future<String> getOrCreatePlayerName() async {
    final saved = await storage.read(_playerNameKey);
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    final id = await getOrCreatePlayerId();
    final name =
        'Player-${id.replaceAll('-', '').substring(0, 4).toUpperCase()}';
    await storage.write(_playerNameKey, name);
    return name;
  }

  Future<String?> resolveCountryCode() async {
    return normalizeCountryCode(await config.countryCodeResolver?.call());
  }

  Future<void> activateCurrentPeriod() async {
    final playerId = await getOrCreatePlayerId();
    final rows = await _requestList(
      _tableUri({
        'select': 'player_id',
        'app_id': 'eq.${config.namespace}',
        'player_id': 'eq.$playerId',
        'period': 'eq.$currentPeriod',
        'limit': '1',
      }),
    );
    if (rows.isNotEmpty) return;
    await _upsert(score: 0);
  }

  Future<void> submitScore(int totalScore) async {
    if (totalScore < 0) {
      throw const LeaderboardException('Score cannot be negative.');
    }
    final playerId = await getOrCreatePlayerId();
    final rows = await _requestList(
      _tableUri({
        'select': 'score',
        'app_id': 'eq.${config.namespace}',
        'player_id': 'eq.$playerId',
        'period': 'eq.$currentPeriod',
        'limit': '1',
      }),
    );
    final previous = rows.isEmpty ? null : rows.first['score'] as num?;
    if (previous != null && previous >= totalScore) return;
    await _upsert(score: totalScore);
  }

  Future<String> updatePlayerName(String rawName) async {
    String name;
    try {
      name = namePolicy.sanitize(rawName);
    } on FormatException catch (error) {
      throw LeaderboardNameException(error.message);
    }

    final playerId = await getOrCreatePlayerId();
    final rows = await _requestList(
      _tableUri({
        'select': 'player_id,name',
        'app_id': 'eq.${config.namespace}',
        'period': 'eq.$currentPeriod',
        'name': 'ilike.${_escapeFilter(name)}',
        'limit': '2',
      }),
    );
    final taken = rows.any((row) => row['player_id'] != playerId);
    if (taken) {
      throw const LeaderboardNameException('That name is already taken.');
    }

    await storage.write(_playerNameKey, name);
    await activateCurrentPeriod();
    final response = await _httpClient
        .patch(
          _tableUri({
            'app_id': 'eq.${config.namespace}',
            'player_id': 'eq.$playerId',
            'period': 'eq.$currentPeriod',
          }),
          headers: {..._headers, 'Prefer': 'return=minimal'},
          body: jsonEncode({
            'name': name,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }),
        )
        .timeout(config.requestTimeout);
    _requireSuccess(response);
    invalidateCache();
    return name;
  }

  Future<LeaderboardSnapshot> fetchSnapshot({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedSnapshot != null &&
        _cachedPeriod == currentPeriod &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < config.cacheDuration) {
      return _cachedSnapshot!;
    }

    final rows = await _requestList(
      _tableUri({
        'select': 'player_id,name,score,country_code,updated_at',
        'app_id': 'eq.${config.namespace}',
        'period': 'eq.$currentPeriod',
        'order': 'score.desc,updated_at.desc',
        'limit': '${config.rankScanLimit}',
      }),
    );
    final ranked = [
      for (var index = 0; index < rows.length; index++)
        LeaderboardEntry.fromJson(rows[index], rank: index + 1),
    ];
    final playerId = await getOrCreatePlayerId();
    final current = ranked
        .where((entry) => entry.playerId == playerId)
        .firstOrNull;
    final snapshot = LeaderboardSnapshot(
      entries: ranked.take(config.topLimit).toList(growable: false),
      currentPlayer: current,
    );
    _cachedSnapshot = snapshot;
    _cachedAt = DateTime.now();
    _cachedPeriod = currentPeriod;
    return snapshot;
  }

  void invalidateCache() {
    _cachedSnapshot = null;
    _cachedAt = null;
    _cachedPeriod = null;
  }

  Future<void> _upsert({required int score}) async {
    final response = await _httpClient
        .post(
          _tableUri({'on_conflict': 'app_id,player_id,period'}),
          headers: {
            ..._headers,
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: jsonEncode({
            'app_id': config.namespace,
            'player_id': await getOrCreatePlayerId(),
            'name': await getOrCreatePlayerName(),
            'country_code': await resolveCountryCode(),
            'score': score,
            'period': currentPeriod,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }),
        )
        .timeout(config.requestTimeout);
    _requireSuccess(response);
    invalidateCache();
  }

  Future<List<Map<String, dynamic>>> _requestList(Uri uri) async {
    final response = await _httpClient
        .get(uri, headers: _headers)
        .timeout(config.requestTimeout);
    _requireSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const LeaderboardException('Leaderboard returned invalid data.');
    }
    return decoded.cast<Map<String, dynamic>>();
  }

  void _requireSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LeaderboardException(
        'Leaderboard request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  String _escapeFilter(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
