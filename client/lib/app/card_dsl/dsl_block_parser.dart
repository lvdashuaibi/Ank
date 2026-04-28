import 'dsl_types.dart';

class DslBlockParser {
  static List<DslBlock> parse(String input) {
    final List<String> lines = input.replaceAll('\r\n', '\n').split('\n');
    final List<DslBlock> blocks = <DslBlock>[];

    int i = 0;
    while (i < lines.length) {
      final String raw = lines[i];
      final String line = raw.trimRight();

      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      final _BlockWithIndex? hint = _consumeTitledBlock(
        lines,
        i,
        startPrefix: '{hint:',
        endToken: '{/hint}',
        type: DslBlockType.hint,
      );
      if (hint != null) {
        blocks.add(hint.block);
        i = hint.nextIndex;
        continue;
      }

      final _BlockWithIndex? explain = _consumeTitledBlock(
        lines,
        i,
        startPrefix: '{explain:',
        endToken: '{/explain}',
        type: DslBlockType.explain,
      );
      if (explain != null) {
        blocks.add(explain.block);
        i = explain.nextIndex;
        continue;
      }

      final _BlockWithIndex? choice = _consumeChoice(lines, i);
      if (choice != null) {
        blocks.add(choice.block);
        i = choice.nextIndex;
        continue;
      }

      final _BlockWithIndex? tf = _consumeTrueFalse(lines, i);
      if (tf != null) {
        blocks.add(tf.block);
        i = tf.nextIndex;
        continue;
      }

      final _BlockWithIndex? answerLines = _consumeAnswerLines(lines, i);
      if (answerLines != null) {
        blocks.add(answerLines.block);
        i = answerLines.nextIndex;
        continue;
      }

      // Paragraph: consume until blank line or special starter.
      final StringBuffer buffer = StringBuffer();
      while (i < lines.length) {
        final String current = lines[i].trimRight();
        if (current.trim().isEmpty) {
          break;
        }
        if (current.trimLeft().startsWith('{hint:') ||
            current.trimLeft().startsWith('{explain:') ||
            _looksLikeChoice(current) ||
            _looksLikeTrueFalse(current) ||
            _looksLikeAnswerLine(current)) {
          break;
        }
        buffer.writeln(current);
        i++;
      }
      blocks.add(DslBlock(type: DslBlockType.paragraph, text: buffer.toString().trim()));
    }

    return blocks;
  }

  static bool _looksLikeChoice(String line) {
    return RegExp(r'^\s*\([x ]\)\s+').hasMatch(line) || RegExp(r'^\s*\[[x ]\]\s+').hasMatch(line);
  }

  static bool _looksLikeTrueFalse(String line) {
    return RegExp(r'^\s*\{[TF]\}\s+').hasMatch(line);
  }

  static bool _looksLikeAnswerLine(String line) {
    return RegExp(r'_{3,}').hasMatch(line) || RegExp(r'___\([^)]*\)___').hasMatch(line);
  }

  static _BlockWithIndex? _consumeChoice(List<String> lines, int start) {
    final String first = lines[start].trimRight();
    if (!_looksLikeChoice(first)) {
      return null;
    }

    final bool isMulti = RegExp(r'^\s*\[[x ]\]').hasMatch(first);
    final List<DslItem> items = <DslItem>[];
    int i = start;
    while (i < lines.length) {
      final String line = lines[i].trimRight();
      if (line.trim().isEmpty) {
        break;
      }
      final RegExpMatch? match = (isMulti
              ? RegExp(r'^\s*\[([x ])\]\s+(.*)$')
              : RegExp(r'^\s*\(([x ])\)\s+(.*)$'))
          .firstMatch(line);
      if (match == null) {
        break;
      }
      items.add(DslItem(text: match.group(2)!.trim(), correct: match.group(1) == 'x'));
      i++;
    }

    return _BlockWithIndex(
      block: DslBlock(
        type: isMulti ? DslBlockType.multiChoice : DslBlockType.singleChoice,
        text: '',
        items: items,
      ),
      nextIndex: i,
    );
  }

  static _BlockWithIndex? _consumeTrueFalse(List<String> lines, int start) {
    final String first = lines[start].trimRight();
    if (!_looksLikeTrueFalse(first)) {
      return null;
    }

    final List<DslItem> items = <DslItem>[];
    int i = start;
    while (i < lines.length) {
      final String line = lines[i].trimRight();
      if (line.trim().isEmpty) {
        break;
      }
      final RegExpMatch? match = RegExp(r'^\s*\{([TF])\}\s+(.*)$').firstMatch(line);
      if (match == null) {
        break;
      }
      items.add(DslItem(text: match.group(2)!.trim(), correct: match.group(1) == 'T'));
      i++;
    }

    return _BlockWithIndex(
      block: DslBlock(type: DslBlockType.trueFalse, text: '', items: items),
      nextIndex: i,
    );
  }

  static _BlockWithIndex? _consumeAnswerLines(List<String> lines, int start) {
    final String first = lines[start].trimRight();
    if (!_looksLikeAnswerLine(first)) {
      return null;
    }

    final List<String> expected = <String>[];
    final List<String> rawLines = <String>[];

    int i = start;
    while (i < lines.length) {
      final String line = lines[i].trimRight();
      if (line.trim().isEmpty) {
        break;
      }
      if (!_looksLikeAnswerLine(line)) {
        break;
      }
      rawLines.add(line);
      final RegExpMatch? match = RegExp(r'___\(([^)]*)\)___').firstMatch(line);
      if (match != null) {
        expected.add(match.group(1)!.trim());
      } else {
        expected.add('');
      }
      i++;
    }

    return _BlockWithIndex(
      block: DslBlock(
        type: DslBlockType.answerLines,
        text: rawLines.join('\n'),
        expected: expected,
      ),
      nextIndex: i,
    );
  }

  static _BlockWithIndex? _consumeTitledBlock(
    List<String> lines,
    int start, {
    required String startPrefix,
    required String endToken,
    required DslBlockType type,
  }) {
    final String line = lines[start].trim();
    if (!line.startsWith(startPrefix)) {
      return null;
    }
    final int endBrace = line.indexOf('}');
    if (endBrace < 0) {
      return null;
    }
    final String title = line.substring(startPrefix.length, endBrace);

    final StringBuffer buffer = StringBuffer();
    int i = start + 1;
    while (i < lines.length) {
      final String current = lines[i].trimRight();
      if (current.trim() == endToken) {
        i++;
        break;
      }
      buffer.writeln(current);
      i++;
    }

    return _BlockWithIndex(
      block: DslBlock(
        type: type,
        title: title.trim(),
        text: buffer.toString().trim(),
      ),
      nextIndex: i,
    );
  }
}

class _BlockWithIndex {
  const _BlockWithIndex({
    required this.block,
    required this.nextIndex,
  });

  final DslBlock block;
  final int nextIndex;
}

