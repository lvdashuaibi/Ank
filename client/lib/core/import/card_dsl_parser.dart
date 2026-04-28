class CardDslParseResult {
  const CardDslParseResult({required this.cards, required this.errors});

  final List<CardDslCard> cards;
  final List<String> errors;
}

class CardDslCard {
  const CardDslCard({
    required this.front,
    required this.back,
    required this.tags,
    required this.deckName,
    required this.note,
    required this.type,
    required this.difficulty,
    required this.raw,
  });

  final String front;
  final String back;
  final List<String> tags;
  final String deckName;
  final String note;
  final String type;
  final String difficulty;
  final String raw;
}

class CardDslParser {
  static const String _cardStart = '@card';
  static const String _answerStart = '@answer';
  static const String _cardEnd = '@end';
  static const String _cardSeparator = '===';
  static const String _frontMarker = '---front---';
  static const String _backMarker = '---back---';
  static const String _metaMarker = '---meta---';

  static CardDslParseResult parseDocument(String input) {
    final String text = input.replaceAll('\r\n', '\n');
    final List<String> errors = <String>[];
    final List<String> blocks = _extractBlocks(text, errors);

    final List<CardDslCard> cards = <CardDslCard>[];
    for (int i = 0; i < blocks.length; i++) {
      final CardDslCard? card = _parseBlock(blocks[i], errors, index: i + 1);
      if (card != null) {
        cards.add(card);
      }
    }

    return CardDslParseResult(cards: cards, errors: errors);
  }

  static List<String> _extractBlocks(String input, List<String> errors) {
    final List<String> lines = input.split('\n');
    final bool hasWrappedCards = lines.any(
      (String line) => line.trim() == _cardStart,
    );
    if (hasWrappedCards) {
      return _extractWrappedBlocks(lines, errors);
    }
    return _extractSimplifiedBlocks(lines);
  }

  static List<String> _extractWrappedBlocks(
    List<String> lines,
    List<String> errors,
  ) {
    final List<String> blocks = <String>[];
    final List<String> current = <String>[];
    int ignoredOutsideLines = 0;
    int currentIndex = 0;
    bool insideCard = false;
    bool insideAnswer = false;

    void flushCurrent() {
      final List<String> trimmed = _trimEdgeBlankLines(current);
      if (trimmed.isNotEmpty) {
        blocks.add(trimmed.join('\n'));
      }
      current.clear();
    }

    for (final String rawLine in lines) {
      final String trimmed = rawLine.trim();
      if (!insideCard) {
        if (trimmed == _cardStart) {
          insideCard = true;
          insideAnswer = false;
          currentIndex = blocks.length + 1;
          current
            ..clear()
            ..add(rawLine);
          continue;
        }
        if (trimmed.isEmpty || trimmed == _cardSeparator) {
          continue;
        }
        ignoredOutsideLines++;
        continue;
      }

      if (trimmed == _cardStart && !insideAnswer) {
        errors.add(
          'Card#$currentIndex: missing @end before next @card，已自动结束上一张',
        );
        flushCurrent();
        currentIndex = blocks.length + 1;
        insideAnswer = false;
        current.add(rawLine);
        continue;
      }

      current.add(rawLine);
      if (trimmed == _answerStart) {
        insideAnswer = true;
        continue;
      }
      if (trimmed == _cardEnd) {
        if (insideAnswer) {
          insideAnswer = false;
          continue;
        }
        flushCurrent();
        insideCard = false;
      }
    }

    if (insideCard) {
      errors.add('Card#$currentIndex: missing @end，已在文档结尾自动结束');
      flushCurrent();
    }

    if (ignoredOutsideLines > 0) {
      errors.add('发现 $ignoredOutsideLines 行位于 @card 块之外的内容，已忽略');
    }

    return blocks;
  }

  static List<String> _extractSimplifiedBlocks(List<String> lines) {
    final List<String> blocks = <String>[];
    final List<String> current = <String>[];
    bool insideAnswer = false;

    void flushCurrent() {
      final List<String> trimmed = _trimEdgeBlankLines(current);
      if (trimmed.isEmpty) {
        current.clear();
        return;
      }
      blocks.add(trimmed.join('\n'));
      current.clear();
    }

    for (final String line in lines) {
      final String trimmed = line.trim();
      if (trimmed == _answerStart) {
        insideAnswer = true;
        current.add(line);
        continue;
      }
      if (trimmed == _cardEnd && insideAnswer) {
        insideAnswer = false;
        current.add(line);
        continue;
      }
      if (trimmed == _cardSeparator && !insideAnswer) {
        flushCurrent();
        continue;
      }
      current.add(line);
    }
    flushCurrent();

    return blocks;
  }

  static CardDslCard? _parseBlock(
    String raw,
    List<String> errors, {
    required int index,
  }) {
    List<String> lines = raw.replaceAll('\r\n', '\n').split('\n');
    lines = _trimEdgeBlankLines(lines);

    if (lines.isNotEmpty && lines.first.trim() == _cardStart) {
      lines = lines.sublist(1);
    }
    final bool hasAnswerSection = lines.any(
      (String line) => line.trim() == _answerStart,
    );
    final int endCount = lines
        .where((String line) => line.trim() == _cardEnd)
        .length;
    final bool shouldStripTrailingCardEnd =
        lines.isNotEmpty &&
        lines.last.trim() == _cardEnd &&
        (!hasAnswerSection || endCount >= 2);
    if (shouldStripTrailingCardEnd) {
      lines = lines.sublist(0, lines.length - 1);
    }
    lines = _trimEdgeBlankLines(lines);

    String deckName = '';
    String type = '';
    String difficulty = '';
    final List<String> tags = <String>[];

    int cursor = 0;
    while (cursor < lines.length) {
      final String trimmed = lines[cursor].trim();
      if (trimmed.isEmpty) {
        cursor++;
        continue;
      }
      if (_isSectionMarker(trimmed)) {
        break;
      }
      final _HeaderLine? header = _tryParseHeader(lines[cursor]);
      if (header == null) {
        break;
      }
      switch (header.key) {
        case 'deck':
          deckName = header.value;
          break;
        case 'type':
          type = header.value;
          break;
        case 'difficulty':
          difficulty = header.value;
          break;
        case 'tags':
          tags.addAll(_splitTags(header.value));
          break;
      }
      cursor++;
    }

    final List<String> bodyLines = lines.sublist(cursor);
    final _ParsedSections sections = _parseSections(
      bodyLines,
      errors: errors,
      index: index,
    );

    final String front = sections.front.trim();
    final String back = sections.back.trim();
    final String meta = sections.meta.trim();

    if (front.isEmpty && back.isEmpty) {
      errors.add('Card#$index: empty card block');
      return null;
    }

    final List<String> normalizedTags = <String>{
      ...tags,
      if (type.isNotEmpty) type,
      'dsl',
    }.toList();

    return CardDslCard(
      front: front,
      back: back,
      tags: normalizedTags,
      deckName: deckName,
      note: meta,
      type: type,
      difficulty: difficulty,
      raw: raw.trim(),
    );
  }

  static _ParsedSections _parseSections(
    List<String> lines, {
    required List<String> errors,
    required int index,
  }) {
    if (lines.isEmpty) {
      return const _ParsedSections(front: '', back: '', meta: '');
    }

    final _ParsedSections? answerSections = _parseAnswerSections(
      lines,
      errors: errors,
      index: index,
    );
    if (answerSections != null) {
      return answerSections;
    }

    return _parseLegacySections(lines);
  }

  static _ParsedSections? _parseAnswerSections(
    List<String> lines, {
    required List<String> errors,
    required int index,
  }) {
    if (!lines.any((String line) => line.trim() == _answerStart)) {
      return null;
    }

    final List<String> promptLines = <String>[];
    final List<String> answerLines = <String>[];
    final List<String> metaLines = <String>[];
    bool inAnswer = false;
    bool answerClosed = false;
    bool inMeta = false;

    for (final String rawLine in lines) {
      final String trimmed = rawLine.trim();
      if (!inAnswer && !inMeta && trimmed == _answerStart) {
        inAnswer = true;
        answerClosed = false;
        continue;
      }
      if (inAnswer && trimmed == _cardEnd) {
        inAnswer = false;
        answerClosed = true;
        continue;
      }
      if (!inAnswer && trimmed == _metaMarker) {
        inMeta = true;
        continue;
      }

      if (inMeta) {
        metaLines.add(rawLine);
      } else if (inAnswer) {
        answerLines.add(rawLine);
      } else {
        promptLines.add(rawLine);
      }
    }

    if (!answerClosed) {
      errors.add('Card#$index: missing @end for @answer，已在文档结尾自动结束');
    }

    return _ParsedSections(
      front: _joinContent(promptLines),
      back: _joinContent(answerLines),
      meta: _joinContent(metaLines),
    );
  }

  static _ParsedSections _parseLegacySections(List<String> lines) {
    if (lines.isEmpty) {
      return const _ParsedSections(front: '', back: '', meta: '');
    }

    final List<String> prefaceLines = <String>[];
    final List<String> frontLines = <String>[];
    final List<String> backLines = <String>[];
    final List<String> metaLines = <String>[];
    _CardSection section = _CardSection.preface;
    bool sawMarker = false;
    bool sawFront = false;

    for (final String rawLine in lines) {
      final String trimmed = rawLine.trim();
      if (trimmed == _frontMarker) {
        sawMarker = true;
        sawFront = true;
        section = _CardSection.front;
        continue;
      }
      if (trimmed == _backMarker) {
        sawMarker = true;
        section = _CardSection.back;
        continue;
      }
      if (trimmed == _metaMarker) {
        sawMarker = true;
        section = _CardSection.meta;
        continue;
      }

      switch (section) {
        case _CardSection.preface:
          prefaceLines.add(rawLine);
          break;
        case _CardSection.front:
          frontLines.add(rawLine);
          break;
        case _CardSection.back:
          backLines.add(rawLine);
          break;
        case _CardSection.meta:
          metaLines.add(rawLine);
          break;
      }
    }

    if (!sawMarker) {
      return _ParsedSections(front: _joinContent(lines), back: '', meta: '');
    }

    return _ParsedSections(
      front: sawFront ? _joinContent(frontLines) : _joinContent(prefaceLines),
      back: _joinContent(backLines),
      meta: _joinContent(metaLines),
    );
  }

  static _HeaderLine? _tryParseHeader(String line) {
    final String trimmed = line.trim();
    if (!trimmed.startsWith('#')) {
      return null;
    }

    final int sep = trimmed.indexOf(':');
    if (sep <= 1) {
      return null;
    }

    final String key = trimmed.substring(1, sep).trim().toLowerCase();
    if (key != 'deck' &&
        key != 'tags' &&
        key != 'type' &&
        key != 'difficulty') {
      return null;
    }

    final String value = trimmed.substring(sep + 1).trim();
    return _HeaderLine(key: key, value: value);
  }

  static List<String> _splitTags(String raw) {
    return raw
        .split(RegExp(r'[,，、;；]'))
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }

  static bool _isSectionMarker(String value) {
    return value == _frontMarker ||
        value == _backMarker ||
        value == _metaMarker;
  }

  static String _joinContent(List<String> lines) {
    return _trimEdgeBlankLines(lines).join('\n').trim();
  }

  static List<String> _trimEdgeBlankLines(List<String> lines) {
    int start = 0;
    int end = lines.length;

    while (start < end && lines[start].trim().isEmpty) {
      start++;
    }
    while (end > start && lines[end - 1].trim().isEmpty) {
      end--;
    }

    return lines.sublist(start, end);
  }
}

enum _CardSection { preface, front, back, meta }

class _ParsedSections {
  const _ParsedSections({
    required this.front,
    required this.back,
    required this.meta,
  });

  final String front;
  final String back;
  final String meta;
}

class _HeaderLine {
  const _HeaderLine({required this.key, required this.value});

  final String key;
  final String value;
}
