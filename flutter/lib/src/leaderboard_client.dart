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
  })  : storage = storage ?? const SharedPreferencesLeaderboardStorage(),
        namePolicy = namePolicy ??
            LeaderboardNamePolicy(maxLength: config.nameMaxLength),
        _httpClient = httpClient ?? http.Client();

  final LeaderboardConfig config;
  final LeaderboardStorage storage;
  final LeaderboardNamePolicy namePolicy;
  final http.Client _httpClient;

  LeaderboardSnapshot? _cachedSnapshot;
  DateTime? _cachedAt;
  String? _cachedPeriod;

  String get _playerIdKey =>
      '${config.namespace}.${config.scope}.leaderboard.playerId.v1';
  String get _playerNameKey =>
      '${config.namespace}.${config.scope}.leaderboard.playerName.v1';
  String get _legacyPlayerIdKey =>
      '${config.namespace}.leaderboard.playerId.v1';
  Future<String> get currentPeriod => _rpc('leaderboard_period', {});

  Future<String> _rpc(String action, Map<String, dynamic> params) async {
    if (config.usesEndpoint) {
      final payload = await _requestEndpointJson(method: 'POST', body: {
        'action': action, 'namespace': config.namespace, 'scope': config.scope, ...params,
      });
      final value = payload?[action == 'leaderboard_name' ? 'playerName' : 'period'];
      if (value is! String || value.isEmpty) {
        throw const LeaderboardException('Endpoint must implement name reservation and ranking periods.');
      }
      return value;
    }
    final response = await _httpClient.post(
      Uri.parse('${config.projectUrl}/rest/v1/rpc/$action'), headers: _headers,
      body: jsonEncode({'p_app_id': config.namespace, 'p_scope': config.scope, ...params}),
    ).timeout(config.requestTimeout);
    _requireSuccess(response);
    return jsonDecode(response.body) as String;
  }

  Map<String, String> get _headers => {
        'apikey': config.requiredAnonKey,
        'Authorization': 'Bearer ${config.requiredAnonKey}',
        'Content-Type': 'application/json',
      };

  Map<String, String> get _endpointHeaders => {
        'Content-Type': 'application/json',
      };

  Uri _tableUri([Map<String, String>? query]) {
    return Uri.parse(
      '${config.projectUrl}/rest/v1/${config.table}',
    ).replace(queryParameters: query);
  }

  Uri _endpointUri([Map<String, String>? query]) {
    if (config.endpoint == null || config.endpoint!.trim().isEmpty) {
      throw const LeaderboardConfigException('endpoint is not configured.');
    }
    return Uri.parse(config.endpoint!).replace(queryParameters: query);
  }

  Future<String> getOrCreatePlayerId() async {
    final saved = await storage.read(_playerIdKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final legacy = config.scope == 'default'
        ? await storage.read(_legacyPlayerIdKey)
        : null;
    if (legacy != null && legacy.isNotEmpty) {
      await storage.write(_playerIdKey, legacy);
      return legacy;
    }
    final id = createAnonymousPlayerId();
    await storage.write(_playerIdKey, id);
    return id;
  }

  Future<String> getOrCreatePlayerName() async {
    final name = await _rpc('leaderboard_name', {
      (config.usesEndpoint ? 'playerId' : 'p_player_id'): await getOrCreatePlayerId(),
    });
    await storage.write(_playerNameKey, name);
    return name;
  }

  Future<String?> resolveCountryCode() async {
    return normalizeCountryCode(await config.countryCodeResolver?.call());
  }

  // Compatibility method: visiting a board must never submit an activation score.
  Future<void> activateCurrentPeriod() async { await currentPeriod; }

  Future<void> submitScore(int totalScore, {DateTime? completedAt}) async {
    final playedMonth = (completedAt ?? DateTime.now()).toUtc().toIso8601String().substring(0, 7);
    final period = await currentPeriod;
    if (playedMonth != period) throw const LeaderboardException('Gameplay belongs to an expired ranking period.');
    if (totalScore < 0) {
      throw const LeaderboardException('Score cannot be negative.');
    }
    if (config.usesEndpoint) {
      await _upsert(score: totalScore, period: period);
      await _rememberScore(period, totalScore);
      return;
    }

    final playerId = await getOrCreatePlayerId();
    final rows = await _requestList(
      _tableUri({
        'select': 'score',
        'app_id': 'eq.${config.namespace}',
        'scope': 'eq.${config.scope}',
        'player_id': 'eq.$playerId',
        'period': 'eq.$period',
        'limit': '1',
      }),
    );
    final previous = rows.isEmpty ? null : rows.first['score'] as num?;
    if (!config.isBetterScore(totalScore, previous)) return;
    await _upsert(score: totalScore, period: period);
    await _rememberScore(period, totalScore);
  }

  Future<String> updatePlayerName(String rawName) async {
    String name;
    try {
      name = namePolicy.sanitize(rawName);
    } on FormatException catch (error) {
      throw LeaderboardNameException(error.message);
    }

    final playerId = await getOrCreatePlayerId();

    if (config.usesEndpoint) {
      final payload = await _requestEndpointJson(
        method: 'PATCH',
        body: {
          'namespace': config.namespace,
          'playerId': playerId,
          'playerName': name,
          'scope': config.scope,
        },
      );
      final savedName = payload?['playerName'] as String? ?? name;
      await storage.write(_playerNameKey, savedName);
      invalidateCache();
      return savedName;
    }

    await _rpc('leaderboard_rename', {'p_player_id': playerId, 'p_name': name});
    await storage.write(_playerNameKey, name);
    invalidateCache();
    return name;
  }

  Future<LeaderboardSnapshot> fetchSnapshot({bool forceRefresh = false}) async {
    if (config.usesEndpoint) {
      return _fetchEndpointSnapshot(forceRefresh: forceRefresh);
    }

    final period = await currentPeriod;
    if (!forceRefresh &&
        _cachedSnapshot != null &&
        _cachedPeriod == period &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < config.cacheDuration) {
      return _cachedSnapshot!;
    }

    final rows = await _requestList(
      _tableUri({
        'select': 'player_id,name,score,country_code,updated_at',
        'app_id': 'eq.${config.namespace}',
        'scope': 'eq.${config.scope}',
        'period': 'eq.$period',
        'order':
            'score.${config.scoreOrder == LeaderboardScoreOrder.lower ? 'asc' : 'desc'},updated_at.desc',
        'limit': '${config.rankScanLimit}',
      }),
    );
    final ranked = [
      for (var index = 0; index < rows.length; index++)
        LeaderboardEntry.fromJson(rows[index], rank: index + 1),
    ];
    final playerId = await getOrCreatePlayerId();
    final current =
        ranked.where((entry) => entry.playerId == playerId).firstOrNull;
    final personal = await _personalRecord(period);
    final snapshot = LeaderboardSnapshot(
      entries: ranked.take(config.topLimit).toList(growable: false),
      currentPlayer: current,
      previousScore: personal['previous'] as int?,
      showPrevious: current != null && personal['previous'] != null && config.isBetterScore(personal['previous'] as int, current.score),
    );
    if (snapshot.currentPlayer != null) await _rememberScore(period, snapshot.currentPlayer!.score);
    _cachedSnapshot = snapshot;
    _cachedAt = DateTime.now();
    _cachedPeriod = period;
    return snapshot;
  }

  Future<Map<String, dynamic>> _personalRecord(String period) async {
    final key = '${config.namespace}.${config.scope}.${await getOrCreatePlayerId()}.personal.v1';
    final raw = await storage.read(key);
    final state = raw == null ? <String, dynamic>{'period': period, 'current': null, 'previous': null} : jsonDecode(raw) as Map<String, dynamic>;
    if (state['period'] != period) {
      if (state['current'] != null && config.isBetterScore(state['current'] as int, state['previous'] as num?)) state['previous'] = state['current'];
      state['current'] = null;
      state['period'] = period;
    }
    state['key'] = key;
    await storage.write(key, jsonEncode(state));
    return state;
  }

  Future<void> _rememberScore(String period, int score) async {
    final state = await _personalRecord(period);
    if (config.isBetterScore(score, state['current'] as num?)) state['current'] = score;
    await storage.write(state['key'] as String, jsonEncode(state));
  }

  void invalidateCache() {
    _cachedSnapshot = null;
    _cachedAt = null;
    _cachedPeriod = null;
  }

  Future<void> _upsert({required int score, required String period}) async {
    if (config.usesEndpoint) {
      await _requestEndpointJson(
        method: 'POST',
        body: {
          'countryCode': await resolveCountryCode(),
          'namespace': config.namespace,
          'playerId': await getOrCreatePlayerId(),
          'playerName': await getOrCreatePlayerName(),
          'period': period,
          'score': score,
          'scope': config.scope,
        },
      );
      invalidateCache();
      return;
    }

    final response = await _httpClient
        .post(
          _tableUri({'on_conflict': 'app_id,scope,player_id,period'}),
          headers: {
            ..._headers,
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: jsonEncode({
            'app_id': config.namespace,
            'scope': config.scope,
            'player_id': await getOrCreatePlayerId(),
            'name': await getOrCreatePlayerName(),
            'country_code': await resolveCountryCode(),
            'score': score,
            'period': period,
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

  Future<Map<String, dynamic>?> _requestEndpointJson({
    required String method,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = _endpointUri(query);
    final encodedBody = body == null ? null : jsonEncode(body);
    final response = switch (method) {
      'GET' => await _httpClient
          .get(uri, headers: _endpointHeaders)
          .timeout(config.requestTimeout),
      'PATCH' => await _httpClient
          .patch(uri, headers: _endpointHeaders, body: encodedBody)
          .timeout(config.requestTimeout),
      'POST' => await _httpClient
          .post(uri, headers: _endpointHeaders, body: encodedBody)
          .timeout(config.requestTimeout),
      _ => throw LeaderboardException('Unsupported endpoint method: $method.'),
    };
    _requireSuccess(response);
    if (response.body.trim().isEmpty) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const LeaderboardException('Leaderboard returned invalid data.');
    }
    return decoded;
  }

  Future<LeaderboardSnapshot> _fetchEndpointSnapshot({
    bool forceRefresh = false,
  }) async {
    final period = await currentPeriod;
    if (!forceRefresh &&
        _cachedSnapshot != null &&
        _cachedPeriod == period &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < config.cacheDuration) {
      return _cachedSnapshot!;
    }

    final payload = await _requestEndpointJson(
      method: 'GET',
      query: {
        'limit': '${config.topLimit}',
        'namespace': config.namespace,
        'playerId': await getOrCreatePlayerId(),
        'scope': config.scope,
      },
    );
    final entriesJson = payload?['entries'];
    if (entriesJson is! List) {
      throw const LeaderboardException('Leaderboard returned invalid data.');
    }
    final entries = [
      for (final entry in entriesJson)
        if (entry is Map<String, dynamic>)
          LeaderboardEntry.fromEndpointJson(entry),
    ];
    final currentJson = payload?['currentPlayer'] ?? payload?['playerEntry'];
    final currentPlayer = currentJson is Map<String, dynamic>
        ? LeaderboardEntry.fromEndpointJson(currentJson)
        : null;
    final personal = await _personalRecord(period);
    final snapshot = LeaderboardSnapshot(
      entries: entries,
      currentPlayer: currentPlayer,
      previousScore: personal['previous'] as int?,
      showPrevious: currentPlayer != null && personal['previous'] != null && config.isBetterScore(personal['previous'] as int, currentPlayer.score),
    );
    if (snapshot.currentPlayer != null) await _rememberScore(period, snapshot.currentPlayer!.score);
    _cachedSnapshot = snapshot;
    _cachedAt = DateTime.now();
    _cachedPeriod = period;
    return snapshot;
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
