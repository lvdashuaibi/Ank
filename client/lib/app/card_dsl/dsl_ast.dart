// Card DSL AST used by the renderer and editor preview.
//
// Design goals:
// - Keep the model small and UI-friendly (WidgetSpan rendering).
// - Be permissive: unknown / malformed syntax should degrade to plain text nodes.
// - Support "full spec" constructs from `卡片格式.md`.

sealed class DslBlockNode {
  const DslBlockNode();
}

final class DslParagraphNode extends DslBlockNode {
  const DslParagraphNode({required this.lines});
  final List<List<DslInlineNode>> lines;
}

final class DslHeadingNode extends DslBlockNode {
  const DslHeadingNode({required this.level, required this.content});
  final int level;
  final List<DslInlineNode> content;
}

final class DslBlockQuoteNode extends DslBlockNode {
  const DslBlockQuoteNode({required this.blocks});
  final List<DslBlockNode> blocks;
}

final class DslCodeBlockNode extends DslBlockNode {
  const DslCodeBlockNode({required this.language, required this.code});
  final String? language;
  final String code;
}

final class DslDividerNode extends DslBlockNode {
  const DslDividerNode();
}

final class DslImageNode extends DslBlockNode {
  const DslImageNode({required this.alt, required this.urlOrPath});
  final String alt;
  final String urlOrPath;
}

final class DslAudioNode extends DslBlockNode {
  const DslAudioNode({required this.alt, required this.urlOrPath});
  final String alt;
  final String urlOrPath;
}

final class DslMathBlockNode extends DslBlockNode {
  const DslMathBlockNode({required this.latex});
  final String latex;
}

final class DslColumnsNode extends DslBlockNode {
  const DslColumnsNode({required this.count, required this.columns});
  final int count;
  final List<List<DslBlockNode>> columns;
}

final class DslHintNode extends DslBlockNode {
  const DslHintNode({required this.title, required this.blocks});
  final String title;
  final List<DslBlockNode> blocks;
}

final class DslExplainNode extends DslBlockNode {
  const DslExplainNode({required this.title, required this.blocks});
  final String title;
  final List<DslBlockNode> blocks;
}

final class DslChoiceGroupNode extends DslBlockNode {
  const DslChoiceGroupNode({required this.multiSelect, required this.options});
  final bool multiSelect;
  final List<DslChoiceOption> options;
}

final class DslJudgeGroupNode extends DslBlockNode {
  const DslJudgeGroupNode({required this.items});
  final List<DslJudgeItem> items;
}

final class DslSortNode extends DslBlockNode {
  const DslSortNode({required this.items});
  final List<DslSortItem> items;
}

final class DslMatchNode extends DslBlockNode {
  const DslMatchNode({required this.pairs});
  final List<DslMatchPair> pairs;
}

final class DslUnknownBlockNode extends DslBlockNode {
  const DslUnknownBlockNode({required this.raw});
  final String raw;
}

final class DslChoiceOption {
  const DslChoiceOption({required this.isCorrect, required this.content});
  final bool isCorrect;
  final List<DslInlineNode> content;
}

final class DslJudgeItem {
  const DslJudgeItem({required this.isTrue, required this.content});
  final bool isTrue;
  final List<DslInlineNode> content;
}

final class DslSortItem {
  const DslSortItem({required this.correctOrder, required this.content});
  final int correctOrder;
  final List<DslInlineNode> content;
}

final class DslMatchPair {
  const DslMatchPair({required this.left, required this.right});
  final List<DslInlineNode> left;
  final List<DslInlineNode> right;
}

sealed class DslInlineNode {
  const DslInlineNode();
}

final class DslTextNode extends DslInlineNode {
  const DslTextNode(this.text);
  final String text;
}

final class DslBoldNode extends DslInlineNode {
  const DslBoldNode(this.children);
  final List<DslInlineNode> children;
}

final class DslItalicNode extends DslInlineNode {
  const DslItalicNode(this.children);
  final List<DslInlineNode> children;
}

final class DslInlineCodeNode extends DslInlineNode {
  const DslInlineCodeNode(this.code);
  final String code;
}

final class DslStrikeNode extends DslInlineNode {
  const DslStrikeNode(this.children);
  final List<DslInlineNode> children;
}

final class DslHighlightNode extends DslInlineNode {
  const DslHighlightNode(this.children);
  final List<DslInlineNode> children;
}

final class DslUnderlineNode extends DslInlineNode {
  const DslUnderlineNode(this.children);
  final List<DslInlineNode> children;
}

final class DslColorNode extends DslInlineNode {
  const DslColorNode({required this.color, required this.children});
  final String color;
  final List<DslInlineNode> children;
}

final class DslBgColorNode extends DslInlineNode {
  const DslBgColorNode({required this.color, required this.children});
  final String color;
  final List<DslInlineNode> children;
}

final class DslSizeNode extends DslInlineNode {
  const DslSizeNode({required this.size, required this.children});
  final String size;
  final List<DslInlineNode> children;
}

final class DslSupNode extends DslInlineNode {
  const DslSupNode(this.children);
  final List<DslInlineNode> children;
}

final class DslSubNode extends DslInlineNode {
  const DslSubNode(this.children);
  final List<DslInlineNode> children;
}

final class DslKbdNode extends DslInlineNode {
  const DslKbdNode(this.text);
  final String text;
}

final class DslClozeNode extends DslInlineNode {
  const DslClozeNode({
    required this.id,
    required this.answers,
    required this.hint,
    required this.regex,
  });

  // Null means an unnumbered cloze (single-card fill).
  final int? id;

  // Accepted answers (case-insensitive, trimmed).
  final List<String> answers;
  final String? hint;
  final String? regex;
}

final class DslAnswerBlankNode extends DslInlineNode {
  const DslAnswerBlankNode({this.expected});
  final String? expected;
}

final class DslRefNode extends DslInlineNode {
  const DslRefNode({required this.id, required this.label});
  final String id;
  final String label;
}

final class DslMathInlineNode extends DslInlineNode {
  const DslMathInlineNode({required this.latex});
  final String latex;
}

