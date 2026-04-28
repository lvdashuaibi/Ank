class CardDocumentParts {
  const CardDocumentParts({
    required this.prompt,
    required this.answer,
    required this.hasAnswerLine,
  });

  final String prompt;
  final String answer;
  final bool hasAnswerLine;
}

class CardDocumentCodec {
  CardDocumentCodec._();

  static const String answerStart = '@answer';
  static const String answerEnd = '@end';

  static CardDocumentParts parse(String content) {
    final List<String> lines = content.replaceAll('\r\n', '\n').split('\n');
    final List<String> promptLines = <String>[];
    final List<String> answerLines = <String>[];
    bool inAnswer = false;
    bool hasAnswerLine = false;

    for (final String rawLine in lines) {
      final String trimmed = rawLine.trim();
      if (!inAnswer && trimmed == answerStart) {
        hasAnswerLine = true;
        inAnswer = true;
        continue;
      }
      if (inAnswer && trimmed == answerEnd) {
        inAnswer = false;
        continue;
      }
      if (inAnswer) {
        answerLines.add(rawLine);
      } else {
        promptLines.add(rawLine);
      }
    }

    return CardDocumentParts(
      prompt: _normalize(promptLines.join('\n')),
      answer: _normalize(answerLines.join('\n')),
      hasAnswerLine: hasAnswerLine,
    );
  }

  static String compose({
    required String prompt,
    required String answer,
    bool includeAnswerLine = false,
  }) {
    final String normalizedPrompt = _normalize(prompt);
    final String normalizedAnswer = _normalize(answer);
    if (normalizedAnswer.isEmpty) {
      if (includeAnswerLine) {
        if (normalizedPrompt.isEmpty) {
          return '$answerStart\n$answerEnd';
        }
        return '$normalizedPrompt\n\n$answerStart\n$answerEnd';
      }
      return normalizedPrompt;
    }
    if (normalizedPrompt.isEmpty) {
      return '$answerStart\n$normalizedAnswer\n$answerEnd';
    }
    return '$normalizedPrompt\n\n$answerStart\n$normalizedAnswer\n$answerEnd';
  }

  static String promptPreview(String content) {
    return parse(content).prompt;
  }

  static String _normalize(String value) {
    return value.trim();
  }
}
