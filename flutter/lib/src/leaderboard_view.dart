import 'dart:async';

import 'package:flutter/material.dart';

import 'leaderboard_client.dart';
import 'leaderboard_config.dart';
import 'leaderboard_models.dart';

class LeaderboardView extends StatefulWidget {
  const LeaderboardView({
    super.key,
    required this.client,
    this.title = 'Leaderboard',
    this.onBack,
    this.scoreLabel = 'Score',
    this.scoreFormatter = formatLeaderboardScore,
    this.backgroundColor = const Color(0xFF505050),
    this.accentColor = const Color(0xFFFFC400),
  });

  final LeaderboardClient client;
  final String title;
  final VoidCallback? onBack;
  final String scoreLabel;
  final LeaderboardScoreFormatter scoreFormatter;
  final Color backgroundColor;
  final Color accentColor;

  @override
  State<LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<LeaderboardView> {
  late Future<LeaderboardSnapshot> _snapshot;
  String? _name;
  DateTime? _refreshLockedUntil;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _snapshot = _activateAndFetch();
    widget.client.getOrCreatePlayerName().then((value) {
      if (mounted) setState(() => _name = value);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<LeaderboardSnapshot> _activateAndFetch({
    bool forceRefresh = false,
  }) async {
    await widget.client.activateCurrentPeriod();
    return widget.client.fetchSnapshot(forceRefresh: forceRefresh);
  }

  void _refresh() {
    if (_refreshLockedUntil != null) return;
    setState(() {
      _refreshLockedUntil = DateTime.now().add(
        widget.client.config.refreshCooldown,
      );
      _snapshot = _activateAndFetch(forceRefresh: true);
    });
    _refreshTimer = Timer(widget.client.config.refreshCooldown, () {
      if (mounted) setState(() => _refreshLockedUntil = null);
    });
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _name);
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: widget.client.config.nameMaxLength,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (selected == null) return;
    try {
      final saved = await widget.client.updatePlayerName(selected);
      if (!mounted) return;
      setState(() {
        _name = saved;
        _snapshot = widget.client.fetchSnapshot(forceRefresh: true);
      });
    } on LeaderboardException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed:
                        widget.onBack ?? () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _refreshLockedUntil == null ? _refresh : null,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _editName,
                  icon: const Icon(Icons.edit),
                  label: Text(_name ?? 'Name'),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<LeaderboardSnapshot>(
                  future: _snapshot,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _Message(
                        title: 'Leaderboard unavailable',
                        body: '${snapshot.error}',
                      );
                    }
                    final data = snapshot.data ?? const LeaderboardSnapshot();
                    if (data.entries.isEmpty && data.currentPlayer == null) {
                      return const _Message(
                        title: 'No scores yet',
                        body: 'Play once to enter this period ranking.',
                      );
                    }
                    return Column(
                      children: [
                        if (data.currentPlayer case final current?) ...[
                          _EntryRow(
                            entry: current,
                            label: 'My Rank',
                            accentColor: widget.accentColor,
                            scoreFormatter: widget.scoreFormatter,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _Header(scoreLabel: widget.scoreLabel),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView.separated(
                            itemCount: data.entries.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, index) => _EntryRow(
                              entry: data.entries[index],
                              accentColor: widget.accentColor,
                              scoreFormatter: widget.scoreFormatter,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.scoreLabel});

  final String scoreLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 58, child: Text('Rank', style: _headerStyle)),
        const SizedBox(width: 36),
        const Expanded(child: Text('Name', style: _headerStyle)),
        SizedBox(
          width: 92,
          child: Text(
            scoreLabel,
            textAlign: TextAlign.right,
            style: _headerStyle,
          ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.accentColor,
    required this.scoreFormatter,
    this.label,
  });

  final LeaderboardEntry entry;
  final Color accentColor;
  final LeaderboardScoreFormatter scoreFormatter;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: entry.rank <= 3 ? accentColor : Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(label!, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              SizedBox(
                width: 58,
                child: Text('#${entry.rank}', style: _entryStyle),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  flagEmoji(entry.countryCode),
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _entryStyle,
                ),
              ),
              SizedBox(
                width: 92,
                child: Text(
                  scoreFormatter(entry.score),
                  textAlign: TextAlign.right,
                  style: _entryStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBE8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String flagEmoji(String? countryCode) {
  if (countryCode == null || countryCode.length != 2) return '--';
  return String.fromCharCodes(
    countryCode.codeUnits.map((code) => code - 0x41 + 0x1F1E6),
  );
}

const _headerStyle = TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.w800,
);
const _entryStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
