class LeaderboardNamePolicy {
  const LeaderboardNamePolicy({
    this.blockedTerms = defaultBlockedTerms,
    this.maxLength = 32,
  });

  final Set<String> blockedTerms;
  final int maxLength;

  String sanitize(String rawName) {
    final compact = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) {
      throw const FormatException('Name cannot be empty.');
    }
    final name =
        compact.length <= maxLength ? compact : compact.substring(0, maxLength);
    if (isBlocked(name)) {
      throw const FormatException('Please choose another name.');
    }
    return name;
  }

  bool isBlocked(String name) {
    final normalized = name.toLowerCase().replaceAll(
          RegExp(r'[\s_\-.,!@#$%^&*()[\]{}:;`~+=|\\/<>?]+'),
          '',
        );
    final leet = normalized
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('3', 'e')
        .replaceAll('4', 'a')
        .replaceAll('5', 's')
        .replaceAll('7', 't')
        .replaceAll('8', 'b');
    return blockedTerms.any(
      (term) => normalized.contains(term) || leet.contains(term),
    );
  }

  static const Set<String> defaultBlockedTerms = {
    'fuck',
    'fuk',
    'fck',
    'shit',
    'bitch',
    'asshole',
    'bastard',
    'cunt',
    'dick',
    'pussy',
    'slut',
    'whore',
    'nigger',
    'nigga',
    'faggot',
    'retard',
    'porn',
    'sibal',
    'ssibal',
    'jiral',
    'jonna',
    'byungsin',
    'gaesae',
    'saekki',
    '시발',
    '씨발',
    '병신',
    '지랄',
    '염병',
    '개새',
    '새끼',
    '좆',
    '존나',
    '씹',
    '강간',
    'ㅅㅂ',
    'ㅂㅅ',
    'ㅈㄹ',
  };
}
