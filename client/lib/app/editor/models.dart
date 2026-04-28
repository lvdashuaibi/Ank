import 'package:flutter/foundation.dart';

/// Card editor document model.
///
/// Why this exists:
/// - The backend currently persists `front`/`back` as Card DSL strings.
/// - The editor UX we want is Notion-like: block-based, inline WYSIWYG, and edit-mode only.
/// - Therefore we need an in-memory block document model, and a bridge to/from DSL.
@immutable
class EditorDocument {
  const EditorDocument({
    required this.frontBlocks,
    required this.backBlocks,
    required this.tags,
    required this.note,
  });

  final List<EditorBlock> frontBlocks;
  final List<EditorBlock> backBlocks;
  final List<String> tags;
  final String note;

  EditorDocument copyWith({
    List<EditorBlock>? frontBlocks,
    List<EditorBlock>? backBlocks,
    List<String>? tags,
    String? note,
  }) {
    return EditorDocument(
      frontBlocks: frontBlocks ?? this.frontBlocks,
      backBlocks: backBlocks ?? this.backBlocks,
      tags: tags ?? this.tags,
      note: note ?? this.note,
    );
  }
}

/// Block kinds supported by the editor.
///
/// NOTE: This is intentionally aligned with the existing DSL renderer capabilities:
/// `DslParser.parseBlocks()` already supports heading/divider/quote/code/math/hint/explain/media,
/// and interactive blocks like choice/judge/sort/match.
enum EditorBlockType {
  paragraph,
  heading1,
  heading2,
  heading3,
  fill,
  quote,
  code,
  divider,
  image,
  audio,
  math,
  hint,
  explain,
  singleChoice,
  multipleChoice,
  trueFalse,
  sorting,
  matching,
}

@immutable
class EditorBlock {
  const EditorBlock({required this.id, required this.type, required this.data});

  final String id;
  final EditorBlockType type;
  final EditorBlockData data;

  EditorBlock copyWith({
    String? id,
    EditorBlockType? type,
    EditorBlockData? data,
  }) {
    return EditorBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      data: data ?? this.data,
    );
  }
}

sealed class EditorBlockData {
  const EditorBlockData();
}

/// Inline styles supported by the WYSIWYG text blocks.
enum InlineStyle {
  bold,
  italic,
  code,
  strike,
  highlight,
  underline,
  cloze,
  fontSmall,
  fontLarge,
}

@immutable
class InlineStyleSpan {
  const InlineStyleSpan({
    required this.start,
    required this.end,
    required this.style,
  });

  /// Start index in plain text (inclusive).
  final int start;

  /// End index in plain text (exclusive).
  final int end;

  final InlineStyle style;
}

/// Rich text stored as plain text + spans.
///
/// The plain text must NOT contain markdown markers like `**` or `` ` ``.
@immutable
class EditorRichText {
  const EditorRichText({required this.text, required this.spans});

  final String text;
  final List<InlineStyleSpan> spans;

  EditorRichText copyWith({String? text, List<InlineStyleSpan>? spans}) {
    return EditorRichText(text: text ?? this.text, spans: spans ?? this.spans);
  }

  static const EditorRichText empty = EditorRichText(
    text: '',
    spans: <InlineStyleSpan>[],
  );
}

@immutable
class ParagraphBlockData extends EditorBlockData {
  const ParagraphBlockData({required this.richText});
  final EditorRichText richText;

  ParagraphBlockData copyWith({EditorRichText? richText}) {
    return ParagraphBlockData(richText: richText ?? this.richText);
  }
}

@immutable
class HeadingBlockData extends EditorBlockData {
  const HeadingBlockData({required this.richText});
  final EditorRichText richText;

  HeadingBlockData copyWith({EditorRichText? richText}) {
    return HeadingBlockData(richText: richText ?? this.richText);
  }
}

@immutable
class FillBlankData {
  const FillBlankData({
    required this.id,
    required this.start,
    required this.end,
    required this.answer,
  });

  final String id;
  final int start;
  final int end;
  final String answer;

  FillBlankData copyWith({String? id, int? start, int? end, String? answer}) {
    return FillBlankData(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      answer: answer ?? this.answer,
    );
  }
}

@immutable
class FillBlockData extends EditorBlockData {
  const FillBlockData({required this.text, required this.blanks});

  final String text;
  final List<FillBlankData> blanks;

  FillBlockData copyWith({String? text, List<FillBlankData>? blanks}) {
    return FillBlockData(
      text: text ?? this.text,
      blanks: blanks ?? this.blanks,
    );
  }
}

@immutable
class QuoteBlockData extends EditorBlockData {
  const QuoteBlockData({required this.blocks});
  final List<EditorBlock> blocks;

  QuoteBlockData copyWith({List<EditorBlock>? blocks}) {
    return QuoteBlockData(blocks: blocks ?? this.blocks);
  }
}

@immutable
class CodeBlockData extends EditorBlockData {
  const CodeBlockData({required this.language, required this.code});
  final String language;
  final String code;

  CodeBlockData copyWith({String? language, String? code}) {
    return CodeBlockData(
      language: language ?? this.language,
      code: code ?? this.code,
    );
  }
}

@immutable
class MathBlockData extends EditorBlockData {
  const MathBlockData({required this.latex});
  final String latex;

  MathBlockData copyWith({String? latex}) {
    return MathBlockData(latex: latex ?? this.latex);
  }
}

@immutable
class MediaBlockData extends EditorBlockData {
  const MediaBlockData({required this.alt, required this.src});
  final String alt;
  final String src;

  MediaBlockData copyWith({String? alt, String? src}) {
    return MediaBlockData(alt: alt ?? this.alt, src: src ?? this.src);
  }
}

@immutable
class FoldableBlockData extends EditorBlockData {
  const FoldableBlockData({required this.title, required this.blocks});
  final String title;
  final List<EditorBlock> blocks;

  FoldableBlockData copyWith({String? title, List<EditorBlock>? blocks}) {
    return FoldableBlockData(
      title: title ?? this.title,
      blocks: blocks ?? this.blocks,
    );
  }
}

@immutable
class ChoiceOptionData {
  const ChoiceOptionData({
    required this.id,
    required this.richText,
    required this.isCorrect,
  });

  final String id;
  final EditorRichText richText;
  final bool isCorrect;

  ChoiceOptionData copyWith({
    String? id,
    EditorRichText? richText,
    bool? isCorrect,
  }) {
    return ChoiceOptionData(
      id: id ?? this.id,
      richText: richText ?? this.richText,
      isCorrect: isCorrect ?? this.isCorrect,
    );
  }
}

@immutable
class ChoiceBlockData extends EditorBlockData {
  const ChoiceBlockData({
    required this.question,
    required this.options,
    required this.multiSelect,
  });

  final EditorRichText question;
  final List<ChoiceOptionData> options;
  final bool multiSelect;

  ChoiceBlockData copyWith({
    EditorRichText? question,
    List<ChoiceOptionData>? options,
    bool? multiSelect,
  }) {
    return ChoiceBlockData(
      question: question ?? this.question,
      options: options ?? this.options,
      multiSelect: multiSelect ?? this.multiSelect,
    );
  }
}

@immutable
class TrueFalseBlockData extends EditorBlockData {
  const TrueFalseBlockData({required this.statement, required this.isTrue});

  final EditorRichText statement;
  final bool isTrue;

  TrueFalseBlockData copyWith({EditorRichText? statement, bool? isTrue}) {
    return TrueFalseBlockData(
      statement: statement ?? this.statement,
      isTrue: isTrue ?? this.isTrue,
    );
  }
}

@immutable
class SortItemData {
  const SortItemData({
    required this.id,
    required this.richText,
    required this.correctOrder,
  });

  final String id;
  final EditorRichText richText;
  final int correctOrder;

  SortItemData copyWith({
    String? id,
    EditorRichText? richText,
    int? correctOrder,
  }) {
    return SortItemData(
      id: id ?? this.id,
      richText: richText ?? this.richText,
      correctOrder: correctOrder ?? this.correctOrder,
    );
  }
}

@immutable
class SortingBlockData extends EditorBlockData {
  const SortingBlockData({required this.items});
  final List<SortItemData> items;

  SortingBlockData copyWith({List<SortItemData>? items}) {
    return SortingBlockData(items: items ?? this.items);
  }
}

@immutable
class MatchPairData {
  const MatchPairData({
    required this.id,
    required this.left,
    required this.right,
  });

  final String id;
  final EditorRichText left;
  final EditorRichText right;

  MatchPairData copyWith({
    String? id,
    EditorRichText? left,
    EditorRichText? right,
  }) {
    return MatchPairData(
      id: id ?? this.id,
      left: left ?? this.left,
      right: right ?? this.right,
    );
  }
}

@immutable
class MatchingBlockData extends EditorBlockData {
  const MatchingBlockData({required this.pairs});
  final List<MatchPairData> pairs;

  MatchingBlockData copyWith({List<MatchPairData>? pairs}) {
    return MatchingBlockData(pairs: pairs ?? this.pairs);
  }
}
