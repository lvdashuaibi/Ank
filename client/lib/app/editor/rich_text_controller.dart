import 'package:flutter/material.dart';

import 'models.dart';

/// A TextEditingController that renders rich text based on `EditorRichText.spans`.
///
/// This is the key to "single-mode editing":
/// - The user always types in the same widget (EditableText/TextField).
/// - We transform markdown markers into spans and remove markers from stored text.
/// - The text displayed while editing is already styled (WYSIWYG-like).
///
/// Constraints (intentional for maintainability):
/// - Only supports non-overlapping spans produced by our transformer.
/// - Does not try to keep nested styling. If nested markers appear, it degrades gracefully.
class EditorRichTextController extends TextEditingController {
  EditorRichTextController({required EditorRichText initial})
    : _spans = initial.spans,
      super(text: initial.text);

  List<InlineStyleSpan> _spans;
  TextEditingValue? _lastValue;

  EditorRichText get model => EditorRichText(text: text, spans: _spans);

  @override
  set value(TextEditingValue newValue) {
    final TextEditingValue oldValue = _lastValue ?? super.value;
    if (oldValue.text != newValue.text) {
      _spans = shiftInlineStyleSpansForTextEdit(
        spans: _spans,
        oldText: oldValue.text,
        newText: newValue.text,
      );
    }
    super.value = newValue;
    _lastValue = newValue;
  }

  void updateModel(EditorRichText next, {bool notify = false}) {
    _spans = next.spans;
    value = value.copyWith(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.text.length),
      composing: TextRange.empty,
    );
    if (notify) {
      notifyListeners();
    }
  }

  void setSpans(List<InlineStyleSpan> spans, {bool notify = false}) {
    _spans = spans;
    if (notify) {
      notifyListeners();
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final TextStyle base = style ?? DefaultTextStyle.of(context).style;
    final String s = text;
    if (_spans.isEmpty || s.isEmpty) {
      return TextSpan(text: s, style: base);
    }

    final List<InlineStyleSegment> spans = normalizeInlineStyleSegments(
      text: s,
      spans: _spans,
    );

    final List<InlineSpan> children = <InlineSpan>[];
    int cursor = 0;
    for (final InlineStyleSegment span in spans) {
      final int start = span.start.clamp(0, s.length);
      final int end = span.end.clamp(0, s.length);
      if (end <= start) continue;
      if (start > cursor) {
        children.add(TextSpan(text: s.substring(cursor, start)));
      }
      children.add(
        TextSpan(
          text: s.substring(start, end),
          style: _applyInlineStyles(base, span.styles, Theme.of(context)),
        ),
      );
      cursor = end;
    }
    if (cursor < s.length) {
      children.add(TextSpan(text: s.substring(cursor)));
    }

    return TextSpan(style: base, children: children);
  }
}

List<InlineStyleSpan> applyInlineStyleToRange({
  required List<InlineStyleSpan> spans,
  required int start,
  required int end,
  required InlineStyle style,
}) {
  final int selectionStart = start < end ? start : end;
  final int selectionEnd = start < end ? end : start;
  if (selectionStart >= selectionEnd) {
    return List<InlineStyleSpan>.from(spans);
  }

  final Set<InlineStyle> conflictingStyles = _conflictingInlineStyles(style);
  final bool shouldToggleOff = _rangeFullyCoveredByStyle(
    spans: spans,
    start: selectionStart,
    end: selectionEnd,
    style: style,
  );

  final List<InlineStyleSpan> next = <InlineStyleSpan>[];
  for (final InlineStyleSpan span in spans) {
    final bool overlaps =
        selectionStart < span.end && selectionEnd > span.start;
    final bool hasStyleConflict = conflictingStyles.contains(span.style);
    if (!overlaps || !hasStyleConflict) {
      next.add(span);
      continue;
    }

    if (span.start < selectionStart) {
      next.add(
        InlineStyleSpan(
          start: span.start,
          end: selectionStart,
          style: span.style,
        ),
      );
    }
    if (span.end > selectionEnd) {
      next.add(
        InlineStyleSpan(start: selectionEnd, end: span.end, style: span.style),
      );
    }
  }

  if (!shouldToggleOff) {
    next.add(
      InlineStyleSpan(start: selectionStart, end: selectionEnd, style: style),
    );
  }
  return next;
}

class InlineStyleSegment {
  const InlineStyleSegment({
    required this.start,
    required this.end,
    required this.styles,
  });

  final int start;
  final int end;
  final Set<InlineStyle> styles;
}

List<InlineStyleSegment> normalizeInlineStyleSegments({
  required String text,
  required List<InlineStyleSpan> spans,
}) {
  if (text.isEmpty || spans.isEmpty) {
    return const <InlineStyleSegment>[];
  }

  final Set<int> boundaries = <int>{0, text.length};
  for (final InlineStyleSpan span in spans) {
    boundaries.add(span.start.clamp(0, text.length));
    boundaries.add(span.end.clamp(0, text.length));
  }

  final List<int> sorted = boundaries.toList()..sort();
  final List<InlineStyleSegment> segments = <InlineStyleSegment>[];
  for (int index = 0; index < sorted.length - 1; index++) {
    final int start = sorted[index];
    final int end = sorted[index + 1];
    if (end <= start) continue;
    final Set<InlineStyle> styles = <InlineStyle>{};
    for (final InlineStyleSpan span in spans) {
      if (span.start <= start && span.end >= end) {
        styles.add(span.style);
      }
    }
    if (styles.isEmpty) continue;
    segments.add(InlineStyleSegment(start: start, end: end, styles: styles));
  }
  return segments;
}

TextStyle _applyInlineStyles(
  TextStyle base,
  Set<InlineStyle> styles,
  ThemeData theme,
) {
  TextStyle current = base;
  for (final InlineStyle style in styles) {
    switch (style) {
      case InlineStyle.bold:
        current = current.copyWith(fontWeight: FontWeight.w700);
      case InlineStyle.italic:
        current = current.copyWith(fontStyle: FontStyle.italic);
      case InlineStyle.code:
        current = current.copyWith(
          fontFamily: 'monospace',
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        );
      case InlineStyle.strike:
        current = current.copyWith(
          decoration: _mergeDecoration(
            current.decoration,
            TextDecoration.lineThrough,
          ),
        );
      case InlineStyle.highlight:
        current = current.copyWith(
          backgroundColor: theme.colorScheme.tertiaryContainer,
        );
      case InlineStyle.underline:
        current = current.copyWith(
          decoration: _mergeDecoration(
            current.decoration,
            TextDecoration.underline,
          ),
        );
      case InlineStyle.cloze:
        current = current.copyWith(
          decoration: _mergeDecoration(
            current.decoration,
            TextDecoration.underline,
          ),
        );
      case InlineStyle.fontSmall:
        current = current.copyWith(fontSize: (base.fontSize ?? 16) - 2);
      case InlineStyle.fontLarge:
        current = current.copyWith(fontSize: (base.fontSize ?? 16) + 4);
    }
  }
  return current;
}

TextDecoration _mergeDecoration(TextDecoration? current, TextDecoration next) {
  if (current == null || current == TextDecoration.none) {
    return next;
  }
  return TextDecoration.combine(<TextDecoration>[current, next]);
}

Set<InlineStyle> _conflictingInlineStyles(InlineStyle style) {
  switch (style) {
    case InlineStyle.fontSmall:
    case InlineStyle.fontLarge:
      return const <InlineStyle>{InlineStyle.fontSmall, InlineStyle.fontLarge};
    case InlineStyle.bold:
    case InlineStyle.italic:
    case InlineStyle.code:
    case InlineStyle.strike:
    case InlineStyle.highlight:
    case InlineStyle.underline:
    case InlineStyle.cloze:
      return <InlineStyle>{style};
  }
}

bool _rangeFullyCoveredByStyle({
  required List<InlineStyleSpan> spans,
  required int start,
  required int end,
  required InlineStyle style,
}) {
  final List<InlineStyleSpan> matches =
      spans
          .where(
            (InlineStyleSpan span) =>
                span.style == style && start < span.end && end > span.start,
          )
          .map(
            (InlineStyleSpan span) => InlineStyleSpan(
              start: span.start < start ? start : span.start,
              end: span.end > end ? end : span.end,
              style: span.style,
            ),
          )
          .toList()
        ..sort((InlineStyleSpan left, InlineStyleSpan right) {
          final int startCompare = left.start.compareTo(right.start);
          if (startCompare != 0) {
            return startCompare;
          }
          return left.end.compareTo(right.end);
        });

  if (matches.isEmpty) {
    return false;
  }

  int coveredUntil = start;
  for (final InlineStyleSpan span in matches) {
    if (span.start > coveredUntil) {
      return false;
    }
    if (span.end > coveredUntil) {
      coveredUntil = span.end;
    }
    if (coveredUntil >= end) {
      return true;
    }
  }
  return coveredUntil >= end;
}

List<InlineStyleSpan> shiftInlineStyleSpansForTextEdit({
  required List<InlineStyleSpan> spans,
  required String oldText,
  required String newText,
}) {
  if (spans.isEmpty || oldText == newText) {
    return spans;
  }

  int prefix = 0;
  while (prefix < oldText.length &&
      prefix < newText.length &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }

  int oldSuffix = oldText.length;
  int newSuffix = newText.length;
  while (oldSuffix > prefix &&
      newSuffix > prefix &&
      oldText.codeUnitAt(oldSuffix - 1) == newText.codeUnitAt(newSuffix - 1)) {
    oldSuffix--;
    newSuffix--;
  }

  final int oldEditEnd = oldSuffix;
  final int newEditEnd = newSuffix;
  final int replacedOldCount = oldEditEnd - prefix;
  final int replacedNewCount = newEditEnd - prefix;
  final int delta = replacedNewCount - replacedOldCount;

  final List<InlineStyleSpan> shifted = <InlineStyleSpan>[];
  for (final InlineStyleSpan span in spans) {
    int start = span.start;
    int end = span.end;

    if (end <= prefix) {
      shifted.add(span);
      continue;
    }

    if (replacedOldCount == 0) {
      if (start >= prefix) {
        start += delta;
        end += delta;
      } else if (end > prefix) {
        end += delta;
      }
      if (end > start) {
        shifted.add(InlineStyleSpan(start: start, end: end, style: span.style));
      }
      continue;
    }

    if (start >= oldEditEnd) {
      start += delta;
      end += delta;
      if (end > start) {
        shifted.add(InlineStyleSpan(start: start, end: end, style: span.style));
      }
      continue;
    }

    if (end <= prefix) {
      shifted.add(span);
      continue;
    }

    if (start < prefix) {
      final int removedInside = (end < oldEditEnd ? end : oldEditEnd) - prefix;
      int newEnd =
          end - (removedInside < 0 ? 0 : removedInside) + replacedNewCount;
      if (newEnd > start) {
        shifted.add(
          InlineStyleSpan(start: start, end: newEnd, style: span.style),
        );
      }
      continue;
    }

    if (end <= oldEditEnd) {
      if (replacedNewCount > 0) {
        shifted.add(
          InlineStyleSpan(
            start: prefix,
            end: prefix + replacedNewCount,
            style: span.style,
          ),
        );
      }
      continue;
    }

    final int newStart = prefix + replacedNewCount;
    final int newEnd = end + delta;
    if (newEnd > newStart) {
      shifted.add(
        InlineStyleSpan(start: newStart, end: newEnd, style: span.style),
      );
    }
  }

  return shifted;
}

/// Transform markdown-like markers in a plain string into:
/// - plain text without markers
/// - inline style spans in the plain text coordinate space
///
/// Supported patterns (non-nested):
/// - `**bold**`
/// - `` `code` ``
/// - `==highlight==`
/// - `~~strike~~`
/// - `*italic*` (best-effort; avoids `**`)
EditorRichText transformInlineMarkdown({
  required String raw,
  required int caretOffset,
}) {
  final InlineMarkdownTransformResult result = transformInlineMarkdownWithCaret(
    raw: raw,
    caretOffset: caretOffset,
  );
  return EditorRichText(text: result.text, spans: result.spans);
}

/// Result of inline markdown transformation, including caret mapping.
@immutable
class InlineMarkdownTransformResult {
  const InlineMarkdownTransformResult({
    required this.text,
    required this.spans,
    required this.caretOffset,
  });

  final String text;
  final List<InlineStyleSpan> spans;
  final int caretOffset;
}

InlineMarkdownTransformResult transformInlineMarkdownWithCaret({
  required String raw,
  required int caretOffset,
}) {
  final String s = raw;
  final int caret = caretOffset.clamp(0, s.length);

  // We do a single left-to-right scan with a small state machine per marker.
  // The output text omits markers; we also compute how the caret maps.
  final StringBuffer out = StringBuffer();
  final List<InlineStyleSpan> spans = <InlineStyleSpan>[];

  int i = 0;
  int outCaret = caret;

  // Helper: when we skip `n` chars from input before caret, caret shifts left by `n`.
  void shiftCaretLeftIfBeforeOrAt(int inputIndex, int removedCount) {
    if (caret > inputIndex) {
      outCaret -= removedCount;
    }
  }

  bool tryConsumeDelimited({
    required String open,
    required String close,
    required InlineStyle style,
  }) {
    if (!s.startsWith(open, i)) return false;
    final int contentStart = i + open.length;
    final int closeAt = s.indexOf(close, contentStart);
    if (closeAt < 0) return false;
    if (closeAt == contentStart) return false;

    // Emit content only.
    final int outStart = out.length;
    out.write(s.substring(contentStart, closeAt));
    final int outEnd = out.length;
    spans.add(InlineStyleSpan(start: outStart, end: outEnd, style: style));

    // Caret mapping: remove open + close markers from the stream.
    // If caret was after openStart, shift by open.length.
    shiftCaretLeftIfBeforeOrAt(contentStart, open.length);
    // If caret was after closeAt, shift by close.length.
    shiftCaretLeftIfBeforeOrAt(closeAt + close.length, close.length);

    i = closeAt + close.length;
    return true;
  }

  while (i < s.length) {
    if (tryConsumeDelimited(
      open: '{{',
      close: '}}',
      style: InlineStyle.cloze,
    )) {
      continue;
    }
    // Bold must be checked before italic.
    if (tryConsumeDelimited(open: '**', close: '**', style: InlineStyle.bold)) {
      continue;
    }
    if (tryConsumeDelimited(open: '`', close: '`', style: InlineStyle.code)) {
      continue;
    }
    if (tryConsumeDelimited(
      open: '==',
      close: '==',
      style: InlineStyle.highlight,
    )) {
      continue;
    }
    if (tryConsumeDelimited(
      open: '~~',
      close: '~~',
      style: InlineStyle.strike,
    )) {
      continue;
    }

    // Italic: *...* but not **...**
    if (s[i] == '*' && !(i + 1 < s.length && s[i + 1] == '*')) {
      final int contentStart = i + 1;
      final int closeAt = s.indexOf('*', contentStart);
      if (closeAt > contentStart) {
        final int outStart = out.length;
        out.write(s.substring(contentStart, closeAt));
        final int outEnd = out.length;
        spans.add(
          InlineStyleSpan(
            start: outStart,
            end: outEnd,
            style: InlineStyle.italic,
          ),
        );

        shiftCaretLeftIfBeforeOrAt(contentStart, 1);
        shiftCaretLeftIfBeforeOrAt(closeAt + 1, 1);

        i = closeAt + 1;
        continue;
      } else {
        // Not a valid italic pattern, fall through and emit '*'.
        // No-op.
      }
    }

    out.write(s[i]);
    i++;
  }

  outCaret = outCaret.clamp(0, out.length);
  return InlineMarkdownTransformResult(
    text: out.toString(),
    spans: spans,
    caretOffset: outCaret,
  );
}
