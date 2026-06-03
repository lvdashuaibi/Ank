import 'dart:math';
import 'dart:io' show File;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'dsl_ast.dart';
import 'dsl_parser.dart';

@visibleForTesting
Random? debugDslChoiceShuffleRandom;

class DslCardView extends StatefulWidget {
  const DslCardView({
    super.key,
    required this.front,
    required this.back,
    required this.revealed,
    this.onReveal,
    this.onCardRefTap,
    this.showBackInline = false,
    this.revealLabel,
  });

  final String front;
  final String back;

  /// Whether the "answer / explanation" section is revealed.
  ///
  /// In review:
  /// - false: user is solving the card (interactive blocks enabled)
  /// - true: show correctness + render back content
  ///
  /// In editor preview:
  /// - keep false
  final bool revealed;

  /// Called when user submits/reveals.
  final VoidCallback? onReveal;

  /// When a @ref[...]{} is tapped, bubble up the referenced DSL id.
  final ValueChanged<String>? onCardRefTap;

  /// Show the back/explanation content inline without requiring reveal.
  ///
  /// Useful for review flows that should keep interactive question blocks
  /// usable while still rendering the answer/explanation area directly below.
  final bool showBackInline;

  /// Optional custom label for the reveal button.
  final String? revealLabel;

  @override
  State<DslCardView> createState() => _DslCardViewState();
}

class _DslCardViewState extends State<DslCardView> {
  bool _submitted = false;
  final Map<int, TextEditingController> _inlineControllers =
      <int, TextEditingController>{};
  int _inlineCounter = 0;

  @override
  void didUpdateWidget(DslCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool contentChanged =
        oldWidget.front != widget.front || oldWidget.back != widget.back;
    final bool revealReset = oldWidget.revealed && !widget.revealed;

    if (contentChanged || revealReset) {
      _submitted = widget.revealed;
      _disposeInlineControllers();
      return;
    }

    if (widget.revealed && !_submitted) {
      _submitted = true;
    }
  }

  @override
  void dispose() {
    _disposeInlineControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    _inlineCounter = 0;
    final DslParseResult frontParsed = DslParser.parseBlocks(widget.front);
    final DslParseResult backParsed = DslParser.parseBlocks(widget.back);
    final bool showResults = widget.revealed || _submitted;
    final bool hasBack = widget.back.trim().isNotEmpty;
    final bool showBackSection =
        (showResults || widget.showBackInline) && hasBack;

    final bool hasInteractive = dslBlocksHaveInteractiveContent(
      frontParsed.blocks,
    );
    final bool canReveal =
        !widget.showBackInline &&
        widget.onReveal != null &&
        (hasInteractive || hasBack);
    final String revealLabel =
        widget.revealLabel ??
        (hasInteractive ? '提交答案' : (hasBack ? '查看答案' : '显示解析'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ..._buildBlocks(
          theme: theme,
          blocks: frontParsed.blocks,
          showResults: showResults,
          allowInteraction: !showResults,
        ),
        if (hasBack) ...<Widget>[
          const SizedBox(height: 16),
          _AnswerDivider(revealed: showBackSection),
        ],
        if (showBackSection) ...<Widget>[
          const SizedBox(height: 12),
          _SectionLabel(icon: Icons.fact_check_outlined, label: '答案/解析'),
          const SizedBox(height: 10),
          ..._buildBlocks(
            theme: theme,
            blocks: backParsed.blocks,
            showResults: true,
            allowInteraction: false,
            explainLocked: false,
          ),
        ],
        if (!showResults && canReveal) ...<Widget>[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.center,
            child: FilledButton.tonalIcon(
              onPressed: _submitAndReveal,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(revealLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _submitAndReveal() {
    setState(() => _submitted = true);
    widget.onReveal?.call();
  }

  void _disposeInlineControllers() {
    for (final TextEditingController controller in _inlineControllers.values) {
      controller.dispose();
    }
    _inlineControllers.clear();
  }

  List<Widget> _buildBlocks({
    required ThemeData theme,
    required List<DslBlockNode> blocks,
    required bool showResults,
    required bool allowInteraction,
    bool explainLocked = true,
  }) {
    final List<Widget> out = <Widget>[];
    for (final DslBlockNode block in blocks) {
      out.add(
        _buildBlock(
          theme: theme,
          block: block,
          showResults: showResults,
          allowInteraction: allowInteraction,
          explainLocked: explainLocked,
        ),
      );
      out.add(const SizedBox(height: 12));
    }
    if (out.isNotEmpty) {
      out.removeLast();
    }
    return out;
  }

  Widget _buildBlock({
    required ThemeData theme,
    required DslBlockNode block,
    required bool showResults,
    required bool allowInteraction,
    required bool explainLocked,
  }) {
    if (block is DslParagraphNode) {
      return _DslParagraph(
        lines: block.lines,
        showResults: showResults,
        allowInteraction: allowInteraction,
        inlineControllerFor: _controllerForInline,
        nextInlineKey: _nextInlineKey,
        onCardRefTap: widget.onCardRefTap,
      );
    }

    if (block is DslHeadingNode) {
      final TextStyle base =
          theme.textTheme.titleLarge ?? const TextStyle(fontSize: 20);
      final double scale = switch (block.level) {
        1 => 1.15,
        2 => 1.08,
        3 => 1.02,
        _ => 0.98,
      };
      return _DslInlineRichText(
        nodes: block.content,
        style: base.copyWith(
          fontSize: (base.fontSize ?? 20) * scale,
          fontWeight: FontWeight.w700,
        ),
        showResults: showResults,
        allowInteraction: allowInteraction,
        inlineControllerFor: _controllerForInline,
        nextInlineKey: _nextInlineKey,
        onCardRefTap: widget.onCardRefTap,
      );
    }

    if (block is DslDividerNode) {
      return Divider(color: theme.colorScheme.outlineVariant);
    }

    if (block is DslCodeBlockNode) {
      return Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if ((block.language ?? '').trim().isNotEmpty)
                Text(
                  block.language!.trim(),
                  style: theme.textTheme.labelMedium,
                ),
              if ((block.language ?? '').trim().isNotEmpty)
                const SizedBox(height: 8),
              SelectableText(
                block.code,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (block is DslMathBlockNode) {
      return Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: Math.tex(block.latex, textStyle: theme.textTheme.bodyLarge),
          ),
        ),
      );
    }

    if (block is DslBlockQuoteNode) {
      return Card(
        color: theme.colorScheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildBlocks(
              theme: theme,
              blocks: block.blocks,
              showResults: showResults,
              allowInteraction: allowInteraction,
              explainLocked: explainLocked,
            ),
          ),
        ),
      );
    }

    if (block is DslHintNode) {
      return _DslFoldable(
        icon: Icons.lightbulb_outline,
        title: block.title.isEmpty ? '提示' : block.title,
        children: _buildBlocks(
          theme: theme,
          blocks: block.blocks,
          showResults: showResults,
          allowInteraction: allowInteraction,
          explainLocked: explainLocked,
        ),
      );
    }

    if (block is DslExplainNode) {
      return _DslFoldable(
        icon: Icons.info_outline,
        title: block.title.isEmpty ? '解析' : block.title,
        enabled: !explainLocked || showResults,
        children: _buildBlocks(
          theme: theme,
          blocks: block.blocks,
          showResults: showResults,
          allowInteraction: allowInteraction,
          explainLocked: explainLocked,
        ),
      );
    }

    if (block is DslImageNode) {
      return _DslImage(alt: block.alt, urlOrPath: block.urlOrPath);
    }

    if (block is DslAudioNode) {
      return _DslAudio(alt: block.alt, urlOrPath: block.urlOrPath);
    }

    if (block is DslColumnsNode) {
      final List<List<DslBlockNode>> cols = block.columns;
      if (cols.isEmpty) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool narrow = constraints.maxWidth < 520;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < cols.length; i++) ...<Widget>[
                  ..._buildBlocks(
                    theme: theme,
                    blocks: cols[i],
                    showResults: showResults,
                    allowInteraction: allowInteraction,
                    explainLocked: explainLocked,
                  ),
                  if (i != cols.length - 1) const SizedBox(height: 12),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < cols.length; i++) ...<Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _buildBlocks(
                      theme: theme,
                      blocks: cols[i],
                      showResults: showResults,
                      allowInteraction: allowInteraction,
                      explainLocked: explainLocked,
                    ),
                  ),
                ),
                if (i != cols.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        },
      );
    }

    if (block is DslChoiceGroupNode) {
      return _DslChoiceGroup(
        multiSelect: block.multiSelect,
        options: block.options,
        showResults: showResults,
        allowInteraction: allowInteraction,
      );
    }

    if (block is DslJudgeGroupNode) {
      return _DslJudgeGroup(
        items: block.items,
        showResults: showResults,
        allowInteraction: allowInteraction,
      );
    }

    if (block is DslSortNode) {
      return _DslSortGroup(
        items: block.items,
        showResults: showResults,
        allowInteraction: allowInteraction,
      );
    }

    if (block is DslMatchNode) {
      return _DslMatchGroup(
        pairs: block.pairs,
        showResults: showResults,
        allowInteraction: allowInteraction,
      );
    }

    if (block is DslUnknownBlockNode) {
      return Text(block.raw);
    }

    return const SizedBox.shrink();
  }

  TextEditingController _controllerForInline(int key) {
    return _inlineControllers.putIfAbsent(key, () => TextEditingController());
  }

  int _nextInlineKey() {
    _inlineCounter += 1;
    return _inlineCounter;
  }
}

bool dslHasInteractiveContent(String input) {
  return dslBlocksHaveInteractiveContent(DslParser.parseBlocks(input).blocks);
}

bool dslBlocksHaveInteractiveContent(List<DslBlockNode> blocks) {
  bool inlineHasInteractive(List<DslInlineNode> nodes) {
    for (final DslInlineNode node in nodes) {
      if (node is DslClozeNode || node is DslAnswerBlankNode) {
        return true;
      }
      if (node is DslBoldNode && inlineHasInteractive(node.children)) {
        return true;
      }
      if (node is DslItalicNode && inlineHasInteractive(node.children)) {
        return true;
      }
      if (node is DslStrikeNode && inlineHasInteractive(node.children)) {
        return true;
      }
      if (node is DslHighlightNode && inlineHasInteractive(node.children)) {
        return true;
      }
      if (node is DslUnderlineNode && inlineHasInteractive(node.children)) {
        return true;
      }
      if (node is DslColorNode && inlineHasInteractive(node.children)) {
        return true;
      }
      if (node is DslBgColorNode && inlineHasInteractive(node.children)) {
        return true;
      }
      if (node is DslSizeNode && inlineHasInteractive(node.children)) {
        return true;
      }
      if (node is DslSupNode && inlineHasInteractive(node.children)) {
        return true;
      }
      if (node is DslSubNode && inlineHasInteractive(node.children)) {
        return true;
      }
    }
    return false;
  }

  for (final DslBlockNode block in blocks) {
    if (block is DslChoiceGroupNode ||
        block is DslJudgeGroupNode ||
        block is DslSortNode ||
        block is DslMatchNode) {
      return true;
    }
    if (block is DslParagraphNode) {
      for (final List<DslInlineNode> line in block.lines) {
        if (inlineHasInteractive(line)) {
          return true;
        }
      }
    }
    if (block is DslHintNode && dslBlocksHaveInteractiveContent(block.blocks)) {
      return true;
    }
    if (block is DslExplainNode &&
        dslBlocksHaveInteractiveContent(block.blocks)) {
      return true;
    }
    if (block is DslBlockQuoteNode &&
        dslBlocksHaveInteractiveContent(block.blocks)) {
      return true;
    }
    if (block is DslColumnsNode) {
      for (final List<DslBlockNode> column in block.columns) {
        if (dslBlocksHaveInteractiveContent(column)) {
          return true;
        }
      }
    }
  }
  return false;
}

class _AnswerDivider extends StatelessWidget {
  const _AnswerDivider({required this.revealed});

  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color color = revealed ? scheme.primary : scheme.outline;
    final Color background = revealed
        ? scheme.primaryContainer.withValues(alpha: 0.72)
        : scheme.surfaceContainerHighest;

    return Row(
      children: <Widget>[
        Expanded(child: Divider(color: color.withValues(alpha: 0.7))),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Text(
            revealed ? '答案已展开' : '答案线',
            style: theme.textTheme.labelMedium?.copyWith(
              color: revealed
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: color.withValues(alpha: 0.7))),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _DslParagraph extends StatelessWidget {
  const _DslParagraph({
    required this.lines,
    required this.showResults,
    required this.allowInteraction,
    required this.inlineControllerFor,
    required this.nextInlineKey,
    required this.onCardRefTap,
  });

  final List<List<DslInlineNode>> lines;
  final bool showResults;
  final bool allowInteraction;
  final TextEditingController Function(int key) inlineControllerFor;
  final int Function() nextInlineKey;
  final ValueChanged<String>? onCardRefTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < lines.length; i++) ...<Widget>[
          _DslInlineRichText(
            nodes: lines[i],
            style: theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16),
            showResults: showResults,
            allowInteraction: allowInteraction,
            inlineControllerFor: inlineControllerFor,
            nextInlineKey: nextInlineKey,
            onCardRefTap: onCardRefTap,
          ),
          if (i != lines.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _DslInlineRichText extends StatelessWidget {
  const _DslInlineRichText({
    required this.nodes,
    required this.style,
    required this.showResults,
    required this.allowInteraction,
    required this.inlineControllerFor,
    required this.nextInlineKey,
    required this.onCardRefTap,
  });

  final List<DslInlineNode> nodes;
  final TextStyle style;
  final bool showResults;
  final bool allowInteraction;
  final TextEditingController Function(int key) inlineControllerFor;
  final int Function() nextInlineKey;
  final ValueChanged<String>? onCardRefTap;

  @override
  Widget build(BuildContext context) {
    final List<InlineSpan> spans = _buildSpans(
      context: context,
      nodes: nodes,
      style: style,
      showResults: showResults,
      allowInteraction: allowInteraction,
      inlineControllerFor: inlineControllerFor,
      nextInlineKey: nextInlineKey,
      onCardRefTap: onCardRefTap,
    );
    return RichText(
      text: TextSpan(style: style, children: spans),
    );
  }
}

List<InlineSpan> _buildSpans({
  required BuildContext context,
  required List<DslInlineNode> nodes,
  required TextStyle style,
  required bool showResults,
  required bool allowInteraction,
  required TextEditingController Function(int key) inlineControllerFor,
  required int Function() nextInlineKey,
  required ValueChanged<String>? onCardRefTap,
}) {
  final ThemeData theme = Theme.of(context);
  final List<InlineSpan> out = <InlineSpan>[];

  TextStyle withColor(String color) {
    final Color mapped = switch (color) {
      'red' => Colors.red,
      'blue' => Colors.blue,
      'green' => Colors.green,
      'orange' => Colors.orange,
      'purple' => Colors.purple,
      'gray' => Colors.grey,
      _ => theme.colorScheme.primary,
    };
    return style.copyWith(color: mapped);
  }

  TextStyle withBg(String color) {
    final Color mapped = switch (color) {
      'yellow' => Colors.yellow,
      'orange' => Colors.orange,
      'red' => Colors.red,
      'green' => Colors.green,
      'blue' => Colors.blue,
      _ => Colors.yellow,
    };
    return style.copyWith(backgroundColor: mapped.withValues(alpha: 0.25));
  }

  double withSize(String size) {
    final double base = style.fontSize ?? 16;
    return switch (size) {
      'sm' => base * 0.92,
      'md' => base,
      'lg' => base * 1.08,
      'xl' => base * 1.18,
      _ => base,
    };
  }

  List<InlineSpan> rec(List<DslInlineNode> inner, TextStyle st) {
    return _buildSpans(
      context: context,
      nodes: inner,
      style: st,
      showResults: showResults,
      allowInteraction: allowInteraction,
      inlineControllerFor: inlineControllerFor,
      nextInlineKey: nextInlineKey,
      onCardRefTap: onCardRefTap,
    );
  }

  for (final DslInlineNode node in nodes) {
    if (node is DslTextNode) {
      out.add(TextSpan(text: node.text));
      continue;
    }
    if (node is DslBoldNode) {
      out.add(
        TextSpan(
          children: rec(
            node.children,
            style.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );
      continue;
    }
    if (node is DslItalicNode) {
      out.add(
        TextSpan(
          children: rec(
            node.children,
            style.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      );
      continue;
    }
    if (node is DslInlineCodeNode) {
      out.add(
        TextSpan(
          text: node.code,
          style: style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      );
      continue;
    }
    if (node is DslStrikeNode) {
      out.add(
        TextSpan(
          children: rec(
            node.children,
            style.copyWith(decoration: TextDecoration.lineThrough),
          ),
        ),
      );
      continue;
    }
    if (node is DslHighlightNode) {
      out.add(
        TextSpan(
          children: rec(
            node.children,
            style.copyWith(
              backgroundColor: theme.colorScheme.tertiaryContainer,
            ),
          ),
        ),
      );
      continue;
    }
    if (node is DslUnderlineNode) {
      out.add(
        TextSpan(
          children: rec(
            node.children,
            style.copyWith(decoration: TextDecoration.underline),
          ),
        ),
      );
      continue;
    }
    if (node is DslColorNode) {
      out.add(TextSpan(children: rec(node.children, withColor(node.color))));
      continue;
    }
    if (node is DslBgColorNode) {
      out.add(TextSpan(children: rec(node.children, withBg(node.color))));
      continue;
    }
    if (node is DslSizeNode) {
      out.add(
        TextSpan(
          children: rec(
            node.children,
            style.copyWith(fontSize: withSize(node.size)),
          ),
        ),
      );
      continue;
    }
    if (node is DslSupNode) {
      out.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: Transform.translate(
            offset: const Offset(0, -4),
            child: Text.rich(
              TextSpan(
                style: style.copyWith(fontSize: (style.fontSize ?? 16) * 0.8),
                children: rec(
                  node.children,
                  style.copyWith(fontSize: (style.fontSize ?? 16) * 0.8),
                ),
              ),
            ),
          ),
        ),
      );
      continue;
    }
    if (node is DslSubNode) {
      out.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: Transform.translate(
            offset: const Offset(0, 2),
            child: Text.rich(
              TextSpan(
                style: style.copyWith(fontSize: (style.fontSize ?? 16) * 0.8),
                children: rec(
                  node.children,
                  style.copyWith(fontSize: (style.fontSize ?? 16) * 0.8),
                ),
              ),
            ),
          ),
        ),
      );
      continue;
    }
    if (node is DslKbdNode) {
      out.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              node.text,
              style: style.copyWith(
                fontFamily: 'monospace',
                fontSize: (style.fontSize ?? 16) * 0.9,
              ),
            ),
          ),
        ),
      );
      continue;
    }
    if (node is DslMathInlineNode) {
      out.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Math.tex(node.latex, textStyle: style),
        ),
      );
      continue;
    }
    if (node is DslRefNode) {
      out.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: TextButton(
            onPressed: () => onCardRefTap?.call(node.id),
            child: Text(node.label.isEmpty ? node.id : node.label),
          ),
        ),
      );
      continue;
    }
    if (node is DslClozeNode) {
      final int key = nextInlineKey();
      out.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _DslClozeField(
            node: node,
            controller: inlineControllerFor(key),
            showResults: showResults,
            enabled: allowInteraction,
          ),
        ),
      );
      continue;
    }
    if (node is DslAnswerBlankNode) {
      final int key = nextInlineKey();
      out.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _DslAnswerBlankField(
            expected: node.expected,
            controller: inlineControllerFor(key),
            showResults: showResults,
            enabled: allowInteraction,
          ),
        ),
      );
      continue;
    }
  }

  return out;
}

class _DslClozeField extends StatefulWidget {
  const _DslClozeField({
    required this.node,
    required this.controller,
    required this.showResults,
    required this.enabled,
  });

  final DslClozeNode node;
  final TextEditingController controller;
  final bool showResults;
  final bool enabled;

  @override
  State<_DslClozeField> createState() => _DslClozeFieldState();
}

class _DslClozeFieldState extends State<_DslClozeField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String answer = widget.node.answers.isNotEmpty
        ? widget.node.answers.first
        : '';
    final TextStyle textStyle =
        theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final double measuredWidth = _measureInlineTextWidth(
      answer.isEmpty ? '  ' : answer,
      textStyle,
      Directionality.of(context),
    );
    final double blankWidth = (measuredWidth + 4).clamp(16, 220);

    Widget buildUnderlineBox({required Widget child, required bool revealed}) {
      return Container(
        key: revealed ? null : const ValueKey<String>('dsl_cloze_blank'),
        width: blankWidth,
        constraints: const BoxConstraints(minHeight: 28),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: revealed
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
              width: 1.6,
            ),
          ),
        ),
        child: child,
      );
    }

    if (widget.showResults || _revealed) {
      return buildUnderlineBox(
        revealed: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            answer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: widget.enabled ? () => setState(() => _revealed = true) : null,
      borderRadius: BorderRadius.circular(2),
      child: buildUnderlineBox(
        revealed: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            widget.node.hint?.isNotEmpty == true ? widget.node.hint! : ' ',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: widget.node.hint?.isNotEmpty == true
                  ? theme.colorScheme.onSurfaceVariant
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

double _measureInlineTextWidth(
  String text,
  TextStyle style,
  TextDirection textDirection,
) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    maxLines: 1,
  )..layout();
  return painter.width;
}

class _DslAnswerBlankField extends StatefulWidget {
  const _DslAnswerBlankField({
    required this.expected,
    required this.controller,
    required this.showResults,
    required this.enabled,
  });

  final String? expected;
  final TextEditingController controller;
  final bool showResults;
  final bool enabled;

  @override
  State<_DslAnswerBlankField> createState() => _DslAnswerBlankFieldState();
}

class _DslAnswerBlankFieldState extends State<_DslAnswerBlankField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String expected = (widget.expected ?? '').trim();
    if (widget.showResults || _revealed) {
      return Container(
        constraints: const BoxConstraints(minWidth: 64),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colorScheme.primary),
          color: theme.colorScheme.primaryContainer,
        ),
        child: Text(expected.isEmpty ? '____' : expected),
      );
    }

    return InkWell(
      onTap: widget.enabled ? () => setState(() => _revealed = true) : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(minWidth: 64),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colorScheme.outline),
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        child: const Text('____'),
      ),
    );
  }
}

class _DslChoiceGroup extends StatelessWidget {
  const _DslChoiceGroup({
    required this.multiSelect,
    required this.options,
    required this.showResults,
    required this.allowInteraction,
  });

  final bool multiSelect;
  final List<DslChoiceOption> options;
  final bool showResults;
  final bool allowInteraction;

  @override
  Widget build(BuildContext context) {
    return _DslChoiceGroupStateful(
      multiSelect: multiSelect,
      options: options,
      showResults: showResults,
      allowInteraction: allowInteraction,
    );
  }
}

class _DslChoiceGroupStateful extends StatefulWidget {
  const _DslChoiceGroupStateful({
    required this.multiSelect,
    required this.options,
    required this.showResults,
    required this.allowInteraction,
  });

  final bool multiSelect;
  final List<DslChoiceOption> options;
  final bool showResults;
  final bool allowInteraction;

  @override
  State<_DslChoiceGroupStateful> createState() =>
      _DslChoiceGroupStatefulState();
}

class _DslChoiceGroupStatefulState extends State<_DslChoiceGroupStateful> {
  int? _singleSelected;
  final Set<int> _multiSelected = <int>{};
  late List<int> _optionOrder;
  late String _optionFingerprint;

  @override
  void initState() {
    super.initState();
    _reshuffleOptions();
  }

  @override
  void didUpdateWidget(_DslChoiceGroupStateful oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String nextFingerprint = _fingerprintOptions(widget.options);
    if (nextFingerprint != _optionFingerprint ||
        oldWidget.multiSelect != widget.multiSelect) {
      _singleSelected = null;
      _multiSelected.clear();
      _reshuffleOptions();
    }
  }

  void _reshuffleOptions() {
    _optionFingerprint = _fingerprintOptions(widget.options);
    _optionOrder = List<int>.generate(widget.options.length, (int i) => i);
    if (_optionOrder.length > 1) {
      _optionOrder.shuffle(debugDslChoiceShuffleRandom ?? Random());
    }
  }

  String _fingerprintOptions(List<DslChoiceOption> options) => options
      .map((DslChoiceOption option) => '${option.isCorrect}:${option.content}')
      .join('\u001f');

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (!widget.multiSelect) {
      return RadioGroup<int>(
        groupValue: _singleSelected,
        onChanged: widget.allowInteraction
            ? (int? value) => setState(() => _singleSelected = value)
            : (_) {},
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('单选题', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final int optionIndex in _optionOrder)
              RadioListTile<int>(
                value: optionIndex,
                enabled: widget.allowInteraction,
                title: Text(_plainInline(widget.options[optionIndex].content)),
                secondary: widget.showResults
                    ? Icon(
                        widget.options[optionIndex].isCorrect
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                        color: widget.options[optionIndex].isCorrect
                            ? Colors.green
                            : Colors.red,
                      )
                    : null,
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('多选题', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final int optionIndex in _optionOrder)
          CheckboxListTile(
            value: _multiSelected.contains(optionIndex),
            onChanged: widget.allowInteraction
                ? (_) => setState(() {
                    if (_multiSelected.contains(optionIndex)) {
                      _multiSelected.remove(optionIndex);
                    } else {
                      _multiSelected.add(optionIndex);
                    }
                  })
                : null,
            title: Text(_plainInline(widget.options[optionIndex].content)),
            secondary: widget.showResults
                ? Icon(
                    widget.options[optionIndex].isCorrect
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    color: widget.options[optionIndex].isCorrect
                        ? Colors.green
                        : Colors.red,
                  )
                : null,
          ),
      ],
    );
  }
}

class _DslJudgeGroup extends StatelessWidget {
  const _DslJudgeGroup({
    required this.items,
    required this.showResults,
    required this.allowInteraction,
  });

  final List<DslJudgeItem> items;
  final bool showResults;
  final bool allowInteraction;

  @override
  Widget build(BuildContext context) {
    return _DslJudgeGroupStateful(
      items: items,
      showResults: showResults,
      allowInteraction: allowInteraction,
    );
  }
}

class _DslJudgeGroupStateful extends StatefulWidget {
  const _DslJudgeGroupStateful({
    required this.items,
    required this.showResults,
    required this.allowInteraction,
  });

  final List<DslJudgeItem> items;
  final bool showResults;
  final bool allowInteraction;

  @override
  State<_DslJudgeGroupStateful> createState() => _DslJudgeGroupStatefulState();
}

class _DslJudgeGroupStatefulState extends State<_DslJudgeGroupStateful> {
  final Map<int, bool> _answers = <int, bool>{};

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('判断题', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (int i = 0; i < widget.items.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(_plainInline(widget.items[i].content))),
                  const SizedBox(width: 10),
                  SegmentedButton<bool>(
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(value: true, label: Text('T')),
                      ButtonSegment<bool>(value: false, label: Text('F')),
                    ],
                    selected: _answers.containsKey(i)
                        ? <bool>{_answers[i]!}
                        : <bool>{},
                    onSelectionChanged: widget.allowInteraction
                        ? (Set<bool> value) =>
                              setState(() => _answers[i] = value.first)
                        : null,
                  ),
                  if (widget.showResults) ...<Widget>[
                    const SizedBox(width: 8),
                    Icon(
                      widget.items[i].isTrue
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      color: widget.items[i].isTrue ? Colors.green : Colors.red,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DslSortGroup extends StatefulWidget {
  const _DslSortGroup({
    required this.items,
    required this.showResults,
    required this.allowInteraction,
  });

  final List<DslSortItem> items;
  final bool showResults;
  final bool allowInteraction;

  @override
  State<_DslSortGroup> createState() => _DslSortGroupState();
}

class _DslSortGroupState extends State<_DslSortGroup> {
  late List<int> _order;

  @override
  void initState() {
    super.initState();
    _order = List<int>.generate(widget.items.length, (int i) => i);
    _order.shuffle();
  }

  List<int> _correctOrder() {
    final List<int> idx = List<int>.generate(widget.items.length, (int i) => i);
    idx.sort(
      (int a, int b) =>
          widget.items[a].correctOrder.compareTo(widget.items[b].correctOrder),
    );
    return idx;
  }

  bool _isCorrect() {
    final List<int> correct = _correctOrder();
    if (correct.length != _order.length) return false;
    for (int i = 0; i < correct.length; i++) {
      if (correct[i] != _order[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool ok = _isCorrect();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('排序题', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            if (widget.showResults)
              Icon(
                ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                color: ok ? Colors.green : Colors.red,
              ),
          ],
        ),
        const SizedBox(height: 8),
        ReorderableListView(
          buildDefaultDragHandles: false,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: widget.allowInteraction
              ? (int oldIndex, int newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final int item = _order.removeAt(oldIndex);
                    _order.insert(newIndex, item);
                  });
                }
              : (_, _) {},
          children: <Widget>[
            for (int i = 0; i < _order.length; i++)
              ListTile(
                key: ValueKey<int>(_order[i]),
                leading: widget.allowInteraction
                    ? ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle),
                      )
                    : const Icon(Icons.drag_handle),
                title: Text(_plainInline(widget.items[_order[i]].content)),
                trailing: widget.showResults
                    ? Text(
                        '#${widget.items[_order[i]].correctOrder}',
                        style: theme.textTheme.labelMedium,
                      )
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _DslMatchGroup extends StatefulWidget {
  const _DslMatchGroup({
    required this.pairs,
    required this.showResults,
    required this.allowInteraction,
  });

  final List<DslMatchPair> pairs;
  final bool showResults;
  final bool allowInteraction;

  @override
  State<_DslMatchGroup> createState() => _DslMatchGroupState();
}

class _DslMatchGroupState extends State<_DslMatchGroup> {
  late List<int> _rightOrder;
  final Map<int, int> _links = <int, int>{}; // leftIndex -> rightIndex
  int? _selectedLeft;

  @override
  void initState() {
    super.initState();
    _rightOrder = List<int>.generate(widget.pairs.length, (int i) => i);
    _rightOrder.shuffle();
  }

  bool _isPairCorrect(int leftIndex) {
    final int? right = _links[leftIndex];
    return right != null && right == leftIndex;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('匹配题', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < widget.pairs.length; i++)
                    ListTile(
                      dense: true,
                      title: Text(_plainInline(widget.pairs[i].left)),
                      selected: _selectedLeft == i,
                      leading: CircleAvatar(
                        radius: 12,
                        child: Text(
                          '${i + 1}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      trailing: widget.showResults
                          ? Icon(
                              _isPairCorrect(i)
                                  ? Icons.check_circle_outline
                                  : Icons.cancel_outlined,
                              color: _isPairCorrect(i)
                                  ? Colors.green
                                  : Colors.red,
                            )
                          : null,
                      onTap: widget.allowInteraction
                          ? () => setState(() => _selectedLeft = i)
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int j = 0; j < _rightOrder.length; j++)
                    ListTile(
                      dense: true,
                      title: Text(
                        _plainInline(widget.pairs[_rightOrder[j]].right),
                      ),
                      leading: const Icon(Icons.arrow_left),
                      onTap: widget.allowInteraction
                          ? () {
                              final int? left = _selectedLeft;
                              if (left == null) return;
                              setState(() {
                                _links[left] = _rightOrder[j];
                                _selectedLeft = null;
                              });
                            }
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
        if (widget.allowInteraction && _links.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '已连接：${_links.length}/${widget.pairs.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _DslFoldable extends StatelessWidget {
  const _DslFoldable({
    required this.icon,
    required this.title,
    required this.children,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: IgnorePointer(
        ignoring: !enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: ExpansionTile(
            leading: Icon(icon),
            title: Text(title),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: children.isEmpty ? <Widget>[const Text('（空）')] : children,
          ),
        ),
      ),
    );
  }
}

class _DslImage extends StatelessWidget {
  const _DslImage({required this.alt, required this.urlOrPath});

  final String alt;
  final String urlOrPath;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String src = urlOrPath.trim();
    final bool isHttp = src.startsWith('http://') || src.startsWith('https://');
    final bool isAsset = src.startsWith('assets/');
    final bool isFile = src.startsWith('/') || src.startsWith('file://');

    Widget image;
    if (isHttp) {
      image = Image.network(src, fit: BoxFit.contain);
    } else if (isAsset) {
      image = Image.asset(src, fit: BoxFit.contain);
    } else if (isFile && !kIsWeb) {
      final String path = src.startsWith('file://')
          ? src.substring('file://'.length)
          : src;
      image = Image.file(File(path), fit: BoxFit.contain);
    } else {
      image = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('图片路径不可用：$src'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(borderRadius: BorderRadius.circular(12), child: image),
        if (alt.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            alt,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _DslAudio extends StatefulWidget {
  const _DslAudio({required this.alt, required this.urlOrPath});
  final String alt;
  final String urlOrPath;

  @override
  State<_DslAudio> createState() => _DslAudioState();
}

class _DslAudioState extends State<_DslAudio> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((PlayerState s) {
      if (!mounted) return;
      setState(() => _state = s);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final String src = widget.urlOrPath.trim();
    if (_state == PlayerState.playing) {
      await _player.pause();
      return;
    }
    if (src.startsWith('http://') || src.startsWith('https://')) {
      await _player.play(UrlSource(src));
      return;
    }
    if (src.startsWith('assets/')) {
      await _player.play(AssetSource(src));
      return;
    }
    if (!kIsWeb && (src.startsWith('/') || src.startsWith('file://'))) {
      final String path = src.startsWith('file://')
          ? src.substring('file://'.length)
          : src;
      await _player.play(DeviceFileSource(path));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('音频路径不可用：$src')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool playing = _state == PlayerState.playing;

    return Card(
      color: theme.colorScheme.surfaceContainerLowest,
      child: ListTile(
        leading: Icon(
          playing ? Icons.pause_circle_outline : Icons.play_circle_outline,
        ),
        title: Text(widget.alt.isEmpty ? '音频' : widget.alt),
        subtitle: Text(
          widget.urlOrPath,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: _toggle,
      ),
    );
  }
}

String _plainInline(List<DslInlineNode> nodes) {
  final StringBuffer buf = StringBuffer();
  void rec(List<DslInlineNode> inner) {
    for (final DslInlineNode n in inner) {
      if (n is DslTextNode) {
        buf.write(n.text);
      } else if (n is DslBoldNode) {
        rec(n.children);
      } else if (n is DslItalicNode) {
        rec(n.children);
      } else if (n is DslStrikeNode) {
        rec(n.children);
      } else if (n is DslHighlightNode) {
        rec(n.children);
      } else if (n is DslUnderlineNode) {
        rec(n.children);
      } else if (n is DslColorNode) {
        rec(n.children);
      } else if (n is DslBgColorNode) {
        rec(n.children);
      } else if (n is DslSizeNode) {
        rec(n.children);
      } else if (n is DslSupNode) {
        rec(n.children);
      } else if (n is DslSubNode) {
        rec(n.children);
      } else if (n is DslInlineCodeNode) {
        buf.write(n.code);
      } else if (n is DslKbdNode) {
        buf.write(n.text);
      } else if (n is DslClozeNode || n is DslAnswerBlankNode) {
        buf.write('____');
      } else if (n is DslRefNode) {
        buf.write(n.label.isEmpty ? n.id : n.label);
      } else if (n is DslMathInlineNode) {
        buf.write(r'[$]');
      }
    }
  }

  rec(nodes);
  return buf.toString().trim();
}
