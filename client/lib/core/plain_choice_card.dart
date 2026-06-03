class PlainChoiceOption {
  const PlainChoiceOption({required this.id, required this.text});

  final String id;
  final String text;

  String get label => '$id. $text';
}

class PlainChoiceQuestion {
  const PlainChoiceQuestion({
    required this.stem,
    required this.options,
    required this.correctIds,
    required this.isMultiSelect,
  });

  final String stem;
  final List<PlainChoiceOption> options;
  final Set<String> correctIds;
  final bool isMultiSelect;

  static final RegExp _optionPattern = RegExp(
    r'^\s*([A-Ha-h])[\.\)、)]\s*(.+?)\s*$',
  );

  static PlainChoiceQuestion? tryParse({
    required String prompt,
    required String answer,
    String cardType = '',
  }) {
    final List<String> lines = prompt.replaceAll('\r\n', '\n').split('\n');
    final List<String> stemLines = <String>[];
    final List<PlainChoiceOption> options = <PlainChoiceOption>[];

    for (final String line in lines) {
      final RegExpMatch? match = _optionPattern.firstMatch(line);
      if (match == null) {
        final String cleaned = _stripInlineAnswer(line).trim();
        if (cleaned.isNotEmpty) {
          stemLines.add(cleaned);
        }
        continue;
      }
      options.add(
        PlainChoiceOption(
          id: match.group(1)!.toUpperCase(),
          text: match.group(2)!.trim(),
        ),
      );
    }

    if (options.length < 2) {
      return null;
    }
    final Set<String> correctIds = _parseCorrectIds(answer, options);
    if (correctIds.isEmpty) {
      return null;
    }
    final String normalizedType = cardType.trim().toLowerCase();
    final bool isMulti =
        normalizedType == 'multi_choice' ||
        correctIds.length > 1 ||
        stemLines.any((String line) => line.contains('多选'));

    return PlainChoiceQuestion(
      stem: stemLines.join('\n').trim(),
      options: options,
      correctIds: correctIds,
      isMultiSelect: isMulti,
    );
  }

  bool isCorrect(Set<String> selectedIds) {
    return selectedIds.length == correctIds.length &&
        selectedIds.containsAll(correctIds);
  }

  String toDsl() {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln(isMultiSelect ? '{multi-choice}' : '{single-choice}');
    if (stem.isNotEmpty) {
      buffer.writeln('Q: $stem');
    }
    for (final PlainChoiceOption option in options) {
      final String marker = correctIds.contains(option.id) ? '*' : '-';
      buffer.writeln('$marker ${option.label}');
    }
    buffer.write(isMultiSelect ? '{/multi-choice}' : '{/single-choice}');
    return buffer.toString();
  }

  static Set<String> _parseCorrectIds(
    String answer,
    List<PlainChoiceOption> options,
  ) {
    String normalized = answer.replaceAll('\r\n', '\n');
    normalized = normalized.replaceAll(
      RegExp(r'正确答案\s*[:：]\s*', caseSensitive: false),
      '',
    );
    final Set<String> ids = <String>{};
    for (final RegExpMatch match in RegExp(
      r'(?:^|[^A-Za-z])([A-Ha-h])(?:\s*[\.\)、)]|[^A-Za-z]|$)',
    ).allMatches(normalized)) {
      ids.add(match.group(1)!.toUpperCase());
    }
    for (final PlainChoiceOption option in options) {
      if (normalized.contains(option.text) ||
          normalized.contains(option.label)) {
        ids.add(option.id);
      }
    }
    return ids
        .where(
          (String id) =>
              options.any((PlainChoiceOption option) => option.id == id),
        )
        .toSet();
  }

  static String _stripInlineAnswer(String line) {
    return line.replaceAll(RegExp(r'^\s*正确答案\s*[:：].*$'), '');
  }
}
