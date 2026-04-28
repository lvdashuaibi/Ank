import 'dsl_ast.dart';

class DslParseResult {
  const DslParseResult({required this.blocks, required this.errors});

  final List<DslBlockNode> blocks;
  final List<String> errors;
}

/// Parser for the card body fragments (front/back/meta content).
///
/// Note:
/// - This parser is intentionally permissive; it favors "render something" over strict validation.
/// - Validation can be layered above if needed.
class DslParser {
  static DslParseResult parseBlocks(String input) {
    final String normalized = input.replaceAll('\r\n', '\n');
    final List<String> lines = normalized.split('\n');
    final List<String> errors = <String>[];

    final List<DslBlockNode> blocks = <DslBlockNode>[];
    final List<String> paragraphLines = <String>[];

    void flushParagraph() {
      if (paragraphLines.isEmpty) {
        return;
      }
      final List<List<DslInlineNode>> parsedLines = paragraphLines
          .map((String line) => _parseInline(line))
          .toList();
      blocks.add(DslParagraphNode(lines: parsedLines));
      paragraphLines.clear();
    }

    int i = 0;
    while (i < lines.length) {
      final String raw = lines[i];
      final String line = raw.trimRight();

      if (line.trim().isEmpty) {
        flushParagraph();
        i++;
        continue;
      }

      // Code block: ```lang ... ```
      final RegExpMatch? codeStart = RegExp(
        r'^\s*```(\w+)?\s*$',
      ).firstMatch(line.trim());
      if (codeStart != null) {
        flushParagraph();
        final String? lang = codeStart.group(1);
        final StringBuffer buf = StringBuffer();
        i++;
        while (i < lines.length) {
          final String current = lines[i].trimRight();
          if (current.trim() == '```') {
            i++;
            break;
          }
          buf.writeln(current);
          i++;
        }
        blocks.add(
          DslCodeBlockNode(language: lang, code: buf.toString().trimRight()),
        );
        continue;
      }

      // Block math: $$ ... $$ (single-line or fenced)
      if (line.trim() == r'$$') {
        flushParagraph();
        final StringBuffer buf = StringBuffer();
        i++;
        while (i < lines.length) {
          final String current = lines[i].trimRight();
          if (current.trim() == r'$$') {
            i++;
            break;
          }
          buf.writeln(current);
          i++;
        }
        blocks.add(DslMathBlockNode(latex: buf.toString().trim()));
        continue;
      }
      final RegExpMatch? mathSingle = RegExp(
        r'^\s*\$\$(.*)\$\$\s*$',
      ).firstMatch(line);
      if (mathSingle != null) {
        flushParagraph();
        blocks.add(DslMathBlockNode(latex: mathSingle.group(1)!.trim()));
        i++;
        continue;
      }

      // Foldable blocks.
      final _TitledBlock? hint = _consumeTitledBlock(
        lines,
        startIndex: i,
        startPrefix: '{hint:',
        endToken: '{/hint}',
      );
      if (hint != null) {
        flushParagraph();
        blocks.add(
          DslHintNode(title: hint.title, blocks: parseBlocks(hint.body).blocks),
        );
        i = hint.nextIndex;
        continue;
      }
      final _TitledBlock? explain = _consumeTitledBlock(
        lines,
        startIndex: i,
        startPrefix: '{explain:',
        endToken: '{/explain}',
      );
      if (explain != null) {
        flushParagraph();
        blocks.add(
          DslExplainNode(
            title: explain.title,
            blocks: parseBlocks(explain.body).blocks,
          ),
        );
        i = explain.nextIndex;
        continue;
      }

      // Sort block.
      if (line.trim() == '{sort}') {
        flushParagraph();
        final StringBuffer buf = StringBuffer();
        i++;
        while (i < lines.length) {
          final String current = lines[i].trimRight();
          if (current.trim() == '{/sort}') {
            i++;
            break;
          }
          buf.writeln(current);
          i++;
        }
        final List<DslSortItem> items = <DslSortItem>[];
        for (final String itemLine in buf.toString().split('\n')) {
          final RegExpMatch? m = RegExp(
            r'^\s*-\s*\[(\d+)\]\s+(.*)$',
          ).firstMatch(itemLine.trimRight());
          if (m == null) {
            if (itemLine.trim().isNotEmpty) {
              errors.add('sort item invalid: $itemLine');
            }
            continue;
          }
          items.add(
            DslSortItem(
              correctOrder: int.tryParse(m.group(1)!) ?? 0,
              content: _parseInline(m.group(2)!.trim()),
            ),
          );
        }
        blocks.add(DslSortNode(items: items));
        continue;
      }

      // Match block.
      if (line.trim() == '{match}') {
        flushParagraph();
        final StringBuffer buf = StringBuffer();
        i++;
        while (i < lines.length) {
          final String current = lines[i].trimRight();
          if (current.trim() == '{/match}') {
            i++;
            break;
          }
          buf.writeln(current);
          i++;
        }
        final List<DslMatchPair> pairs = <DslMatchPair>[];
        for (final String itemLine in buf.toString().split('\n')) {
          final String trimmed = itemLine.trim();
          if (trimmed.isEmpty) continue;
          final int sep = trimmed.indexOf('<->');
          if (sep < 0) {
            errors.add('match pair invalid: $trimmed');
            continue;
          }
          final String left = trimmed.substring(0, sep).trim();
          final String right = trimmed.substring(sep + 3).trim();
          pairs.add(
            DslMatchPair(left: _parseInline(left), right: _parseInline(right)),
          );
        }
        blocks.add(DslMatchNode(pairs: pairs));
        continue;
      }

      // Columns block.
      final RegExpMatch? columnsStart = RegExp(
        r'^\s*\{columns:(\d+)\}\s*$',
      ).firstMatch(line.trim());
      if (columnsStart != null) {
        flushParagraph();
        final int count = int.tryParse(columnsStart.group(1)!) ?? 2;
        final List<String> parts = <String>[];
        final StringBuffer buf = StringBuffer();
        i++;
        while (i < lines.length) {
          final String current = lines[i].trimRight();
          if (current.trim() == '{/columns}') {
            i++;
            break;
          }
          if (current.trim() == '|||') {
            parts.add(buf.toString().trim());
            buf.clear();
            i++;
            continue;
          }
          buf.writeln(current);
          i++;
        }
        parts.add(buf.toString().trim());
        final List<String> nonEmpty = parts
            .where((String p) => p.isNotEmpty)
            .toList();
        final List<List<DslBlockNode>> cols = nonEmpty
            .map((String p) => parseBlocks(p).blocks)
            .toList();
        blocks.add(DslColumnsNode(count: count, columns: cols));
        continue;
      }

      // Divider.
      if (line.trim() == '---') {
        flushParagraph();
        blocks.add(const DslDividerNode());
        i++;
        continue;
      }

      // Heading.
      final RegExpMatch? heading = RegExp(
        r'^(#{1,6})\s+(.*)$',
      ).firstMatch(line.trim());
      if (heading != null) {
        flushParagraph();
        blocks.add(
          DslHeadingNode(
            level: heading.group(1)!.length.clamp(1, 6),
            content: _parseInline(heading.group(2)!.trim()),
          ),
        );
        i++;
        continue;
      }

      // Blockquote: consecutive lines starting with ">".
      if (line.trimLeft().startsWith('>')) {
        flushParagraph();
        final StringBuffer buf = StringBuffer();
        while (i < lines.length) {
          final String current = lines[i].trimRight();
          if (!current.trimLeft().startsWith('>')) {
            break;
          }
          buf.writeln(current.trimLeft().replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        blocks.add(
          DslBlockQuoteNode(blocks: parseBlocks(buf.toString().trim()).blocks),
        );
        continue;
      }

      // Media.
      final RegExpMatch? img = RegExp(
        r'^\s*!img\[(.*)\]\((.*)\)\s*$',
      ).firstMatch(line.trim());
      if (img != null) {
        flushParagraph();
        blocks.add(
          DslImageNode(
            alt: img.group(1)!.trim(),
            urlOrPath: img.group(2)!.trim(),
          ),
        );
        i++;
        continue;
      }
      final RegExpMatch? audio = RegExp(
        r'^\s*!audio\[(.*)\]\((.*)\)\s*$',
      ).firstMatch(line.trim());
      if (audio != null) {
        flushParagraph();
        blocks.add(
          DslAudioNode(
            alt: audio.group(1)!.trim(),
            urlOrPath: audio.group(2)!.trim(),
          ),
        );
        i++;
        continue;
      }

      // Custom single-choice / multi-choice blocks used by the inline editor.
      final _BlockGroupWithIndex? singleChoice = _consumeCustomChoiceBlock(
        lines,
        startIndex: i,
        startMarker: '{single-choice}',
        endMarker: '{/single-choice}',
        multiSelect: false,
      );
      if (singleChoice != null) {
        flushParagraph();
        blocks.addAll(singleChoice.blocks);
        i = singleChoice.nextIndex;
        continue;
      }
      final _BlockGroupWithIndex? multiChoice = _consumeCustomChoiceBlock(
        lines,
        startIndex: i,
        startMarker: '{multi-choice}',
        endMarker: '{/multi-choice}',
        multiSelect: true,
      );
      if (multiChoice != null) {
        flushParagraph();
        blocks.addAll(multiChoice.blocks);
        i = multiChoice.nextIndex;
        continue;
      }

      // Choice group.
      final _ChoiceBlock? choice = _consumeChoice(lines, startIndex: i);
      if (choice != null) {
        flushParagraph();
        blocks.add(choice.node);
        i = choice.nextIndex;
        continue;
      }

      // Judge group.
      final _JudgeBlock? judge = _consumeJudge(lines, startIndex: i);
      if (judge != null) {
        flushParagraph();
        blocks.add(judge.node);
        i = judge.nextIndex;
        continue;
      }

      // Default: accumulate as paragraph.
      paragraphLines.add(line);
      i++;
    }

    flushParagraph();
    return DslParseResult(blocks: blocks, errors: errors);
  }

  static _TitledBlock? _consumeTitledBlock(
    List<String> lines, {
    required int startIndex,
    required String startPrefix,
    required String endToken,
  }) {
    final String head = lines[startIndex].trimRight().trim();
    if (!head.startsWith(startPrefix)) {
      return null;
    }
    final int endBrace = head.indexOf('}');
    if (endBrace < 0) {
      return null;
    }
    final String title = head.substring(startPrefix.length, endBrace).trim();
    final StringBuffer body = StringBuffer();
    int i = startIndex + 1;
    while (i < lines.length) {
      final String current = lines[i].trimRight();
      if (current.trim() == endToken) {
        i++;
        break;
      }
      body.writeln(current);
      i++;
    }
    return _TitledBlock(
      title: title,
      body: body.toString().trim(),
      nextIndex: i,
    );
  }
}

class _TitledBlock {
  const _TitledBlock({
    required this.title,
    required this.body,
    required this.nextIndex,
  });

  final String title;
  final String body;
  final int nextIndex;
}

class _ChoiceBlock {
  const _ChoiceBlock({required this.node, required this.nextIndex});

  final DslChoiceGroupNode node;
  final int nextIndex;
}

class _BlockGroupWithIndex {
  const _BlockGroupWithIndex({required this.blocks, required this.nextIndex});

  final List<DslBlockNode> blocks;
  final int nextIndex;
}

class _JudgeBlock {
  const _JudgeBlock({required this.node, required this.nextIndex});

  final DslJudgeGroupNode node;
  final int nextIndex;
}

_ChoiceBlock? _consumeChoice(List<String> lines, {required int startIndex}) {
  final String first = lines[startIndex].trimRight();
  final bool isChoice = RegExp(r'^\s*\([x ]\)\s+').hasMatch(first);
  final bool isMulti = RegExp(r'^\s*\[[x ]\]\s+').hasMatch(first);
  if (!isChoice && !isMulti) {
    return null;
  }

  final List<DslChoiceOption> options = <DslChoiceOption>[];
  int i = startIndex;
  while (i < lines.length) {
    final String line = lines[i].trimRight();
    if (line.trim().isEmpty) break;
    final RegExpMatch? m =
        (isMulti
                ? RegExp(r'^\s*\[([x ])\]\s+(.*)$')
                : RegExp(r'^\s*\(([x ])\)\s+(.*)$'))
            .firstMatch(line);
    if (m == null) break;
    options.add(
      DslChoiceOption(
        isCorrect: m.group(1) == 'x',
        content: _parseInline(m.group(2)!.trim()),
      ),
    );
    i++;
  }

  return _ChoiceBlock(
    node: DslChoiceGroupNode(multiSelect: isMulti, options: options),
    nextIndex: i,
  );
}

_BlockGroupWithIndex? _consumeCustomChoiceBlock(
  List<String> lines, {
  required int startIndex,
  required String startMarker,
  required String endMarker,
  required bool multiSelect,
}) {
  if (lines[startIndex].trim() != startMarker) {
    return null;
  }

  final List<String> questionLines = <String>[];
  final List<DslChoiceOption> options = <DslChoiceOption>[];
  bool sawCorrect = false;
  bool sawOption = false;
  int i = startIndex + 1;

  while (i < lines.length) {
    final String raw = lines[i].trimRight();
    final String line = raw.trim();
    if (line == endMarker) {
      if (options.isEmpty) {
        return null;
      }
      final List<DslChoiceOption> normalizedOptions = sawCorrect
          ? options
          : <DslChoiceOption>[
              DslChoiceOption(isCorrect: true, content: options.first.content),
              ...options.skip(1),
            ];

      final List<DslBlockNode> blocks = <DslBlockNode>[];
      if (questionLines.any((String item) => item.trim().isNotEmpty)) {
        blocks.add(
          DslParagraphNode(
            lines: questionLines
                .where((String item) => item.trim().isNotEmpty)
                .map((String item) => _parseInline(item.trim()))
                .toList(),
          ),
        );
      }
      blocks.add(
        DslChoiceGroupNode(
          multiSelect: multiSelect,
          options: normalizedOptions,
        ),
      );
      return _BlockGroupWithIndex(blocks: blocks, nextIndex: i + 1);
    }

    if (line.isEmpty) {
      i++;
      continue;
    }

    if (line.startsWith('Q:') || line.startsWith('Q：')) {
      questionLines.add(line.substring(2).trim());
      i++;
      continue;
    }

    if (line.startsWith('*')) {
      sawCorrect = true;
      sawOption = true;
      options.add(
        DslChoiceOption(
          isCorrect: true,
          content: _parseInline(line.substring(1).trim()),
        ),
      );
      i++;
      continue;
    }

    if (line.startsWith('-')) {
      sawOption = true;
      options.add(
        DslChoiceOption(
          isCorrect: false,
          content: _parseInline(line.substring(1).trim()),
        ),
      );
      i++;
      continue;
    }

    if (!sawOption) {
      questionLines.add(line);
      i++;
      continue;
    }

    return null;
  }

  return null;
}

_JudgeBlock? _consumeJudge(List<String> lines, {required int startIndex}) {
  final String first = lines[startIndex].trimRight();
  if (!RegExp(r'^\s*\{[TF]\}\s+').hasMatch(first)) {
    return null;
  }
  final List<DslJudgeItem> items = <DslJudgeItem>[];
  int i = startIndex;
  while (i < lines.length) {
    final String line = lines[i].trimRight();
    if (line.trim().isEmpty) break;
    final RegExpMatch? m = RegExp(r'^\s*\{([TF])\}\s+(.*)$').firstMatch(line);
    if (m == null) break;
    items.add(
      DslJudgeItem(
        isTrue: m.group(1) == 'T',
        content: _parseInline(m.group(2)!.trim()),
      ),
    );
    i++;
  }
  return _JudgeBlock(
    node: DslJudgeGroupNode(items: items),
    nextIndex: i,
  );
}

List<DslInlineNode> _parseInline(String input) {
  final String s = input;
  final List<DslInlineNode> out = <DslInlineNode>[];
  int i = 0;

  void emitText(String text) {
    if (text.isEmpty) return;
    if (out.isNotEmpty && out.last is DslTextNode) {
      final DslTextNode prev = out.removeLast() as DslTextNode;
      out.add(DslTextNode(prev.text + text));
      return;
    }
    out.add(DslTextNode(text));
  }

  while (i < s.length) {
    // Cloze: {{...}}
    if (s.startsWith('{{', i)) {
      final int end = s.indexOf('}}', i + 2);
      if (end > i) {
        final String inner = s.substring(i + 2, end).trim();
        out.add(_parseCloze(inner));
        i = end + 2;
        continue;
      }
    }

    // Ref: @ref[id]{label}
    if (s.startsWith('@ref[', i)) {
      final int closeBracket = s.indexOf(']', i + 5);
      if (closeBracket > i) {
        final int openBrace = s.indexOf('{', closeBracket + 1);
        if (openBrace > closeBracket) {
          final int endBrace = _findMatchingBrace(s, openBrace);
          if (endBrace > openBrace) {
            final String id = s.substring(i + 5, closeBracket).trim();
            final String label = s.substring(openBrace + 1, endBrace).trim();
            out.add(DslRefNode(id: id, label: label));
            i = endBrace + 1;
            continue;
          }
        }
      }
    }

    // Answer blank: ___(expected)___ or ______
    if (s.startsWith('___', i)) {
      final RegExpMatch? m = RegExp(
        r'^___\(([^)]*)\)___',
      ).firstMatch(s.substring(i));
      if (m != null) {
        out.add(DslAnswerBlankNode(expected: m.group(1)!.trim()));
        i += m.group(0)!.length;
        continue;
      }
      final RegExpMatch? m2 = RegExp(r'^_{3,}').firstMatch(s.substring(i));
      if (m2 != null) {
        out.add(const DslAnswerBlankNode());
        i += m2.group(0)!.length;
        continue;
      }
    }

    // Inline math: $...$ (avoid $$...$$ handled at block level)
    if (s[i] == r'$') {
      if (i + 1 < s.length && s[i + 1] == r'$') {
        // Let block parser handle $$.
      } else {
        final int end = s.indexOf(r'$', i + 1);
        if (end > i + 1) {
          final String latex = s.substring(i + 1, end).trim();
          out.add(DslMathInlineNode(latex: latex));
          i = end + 1;
          continue;
        }
      }
    }

    // Inline code: `...`
    if (s[i] == '`') {
      final int end = s.indexOf('`', i + 1);
      if (end > i + 1) {
        out.add(DslInlineCodeNode(s.substring(i + 1, end)));
        i = end + 1;
        continue;
      }
    }

    // Bold: **...**
    if (s.startsWith('**', i)) {
      final int end = s.indexOf('**', i + 2);
      if (end > i + 2) {
        final String inner = s.substring(i + 2, end);
        out.add(DslBoldNode(_parseInline(inner)));
        i = end + 2;
        continue;
      }
    }

    // Strike: ~~...~~
    if (s.startsWith('~~', i)) {
      final int end = s.indexOf('~~', i + 2);
      if (end > i + 2) {
        final String inner = s.substring(i + 2, end);
        out.add(DslStrikeNode(_parseInline(inner)));
        i = end + 2;
        continue;
      }
    }

    // Highlight: ==...==
    if (s.startsWith('==', i)) {
      final int end = s.indexOf('==', i + 2);
      if (end > i + 2) {
        final String inner = s.substring(i + 2, end);
        out.add(DslHighlightNode(_parseInline(inner)));
        i = end + 2;
        continue;
      }
    }

    // Italic: *...* (avoid **)
    if (s[i] == '*' && !(i + 1 < s.length && s[i + 1] == '*')) {
      final int end = s.indexOf('*', i + 1);
      if (end > i + 1) {
        final String inner = s.substring(i + 1, end);
        out.add(DslItalicNode(_parseInline(inner)));
        i = end + 1;
        continue;
      }
    }

    // Extension styles: {...}
    if (s[i] == '{') {
      final int endBrace = _findMatchingBrace(s, i);
      if (endBrace > i) {
        final String inner = s.substring(i + 1, endBrace);
        final DslInlineNode? styled = _parseStyle(inner);
        if (styled != null) {
          out.add(styled);
          i = endBrace + 1;
          continue;
        }
      }
    }

    // Fallback: emit one char.
    emitText(s[i]);
    i++;
  }

  return out;
}

DslInlineNode _parseCloze(String inner) {
  // Forms:
  // - answer
  // - answer|提示:xxx
  // - c1:answer
  // - answerA|answerB|regex:...
  // - c2:answer|提示:xxx|regex:...
  int? id;
  String body = inner;
  final RegExpMatch? numbered = RegExp(r'^c(\d+):(.*)$').firstMatch(inner);
  if (numbered != null) {
    id = int.tryParse(numbered.group(1)!);
    body = numbered.group(2)!.trim();
  }

  final List<String> parts = body
      .split('|')
      .map((String s) => s.trim())
      .toList();
  final List<String> answers = <String>[];
  String? hint;
  String? regex;

  for (final String p in parts) {
    if (p.startsWith('提示:')) {
      hint = p.substring('提示:'.length).trim();
      continue;
    }
    if (p.startsWith('regex:')) {
      regex = p.substring('regex:'.length).trim();
      continue;
    }
    if (p.isNotEmpty) {
      answers.add(p);
    }
  }

  if (answers.isEmpty) {
    answers.add(body);
  }

  return DslClozeNode(id: id, answers: answers, hint: hint, regex: regex);
}

DslInlineNode? _parseStyle(String inner) {
  // Examples:
  // {red:文字}
  // {bg:yellow:文字}
  // {size:lg:文字}
  // {u:文字} {sup:文字} {sub:文字} {kbd:文字}
  final List<String> parts = inner.split(':');
  if (parts.isEmpty) return null;

  final String key = parts.first.trim();
  if (key.isEmpty) return null;

  if (key == 'bg' && parts.length >= 3) {
    final String color = parts[1].trim();
    final String content = inner.substring(
      inner.indexOf(':', inner.indexOf(':') + 1) + 1,
    );
    return DslBgColorNode(color: color, children: _parseInline(content));
  }

  if (key == 'size' && parts.length >= 3) {
    final String size = parts[1].trim();
    final String content = inner.substring(
      inner.indexOf(':', inner.indexOf(':') + 1) + 1,
    );
    return DslSizeNode(size: size, children: _parseInline(content));
  }

  if (key == 'u' && parts.length >= 2) {
    final String content = inner.substring(inner.indexOf(':') + 1);
    return DslUnderlineNode(_parseInline(content));
  }
  if (key == 'sup' && parts.length >= 2) {
    final String content = inner.substring(inner.indexOf(':') + 1);
    return DslSupNode(_parseInline(content));
  }
  if (key == 'sub' && parts.length >= 2) {
    final String content = inner.substring(inner.indexOf(':') + 1);
    return DslSubNode(_parseInline(content));
  }
  if (key == 'kbd' && parts.length >= 2) {
    final String content = inner.substring(inner.indexOf(':') + 1).trim();
    return DslKbdNode(content);
  }

  // Named colors.
  const Set<String> colors = <String>{
    'red',
    'blue',
    'green',
    'orange',
    'purple',
    'gray',
  };
  if (colors.contains(key) && parts.length >= 2) {
    final String content = inner.substring(inner.indexOf(':') + 1);
    return DslColorNode(color: key, children: _parseInline(content));
  }

  return null;
}

int _findMatchingBrace(String s, int openIndex) {
  if (openIndex < 0 || openIndex >= s.length || s[openIndex] != '{') {
    return -1;
  }
  int depth = 0;
  for (int i = openIndex; i < s.length; i++) {
    final String ch = s[i];
    if (ch == '{') depth++;
    if (ch == '}') depth--;
    if (depth == 0) return i;
  }
  return -1;
}
