import 'package:uuid/uuid.dart';

import '../card_dsl/dsl_ast.dart';
import '../card_dsl/dsl_parser.dart';
import '../../core/import/card_dsl_parser.dart';
import 'models.dart';
import 'rich_text_controller.dart';

/// Converts between persisted Card DSL strings and the in-memory editor document.
///
/// Design choice:
/// - We do NOT attempt to preserve every unsupported syntax node perfectly in edit mode.
/// - For constructs the visual editor understands, we round-trip structurally.
/// - For unsupported/unknown fragments, we degrade to plain paragraph/code content instead of failing.
class EditorDocumentCodec {
  EditorDocumentCodec._();

  static const Uuid _uuid = Uuid();

  static EditorDocument fromCard({
    required String front,
    required String back,
    required List<String> tags,
    required String note,
  }) {
    final String primary = front.trim().isNotEmpty ? front : back;
    return EditorDocument(
      frontBlocks: _mapBlocks(DslParser.parseBlocks(primary).blocks),
      backBlocks: const <EditorBlock>[],
      tags: tags
          .where((tag) => tag.trim().isNotEmpty && tag.trim() != 'dsl')
          .toList(),
      note: note,
    );
  }

  static EditorDocument empty() {
    return EditorDocument(
      frontBlocks: <EditorBlock>[_newParagraphBlock()],
      backBlocks: const <EditorBlock>[],
      tags: const <String>[],
      note: '',
    );
  }

  static CardDslCard toCard({required EditorDocument document}) {
    final String front = _encodeBlocks(document.frontBlocks);
    final String back = _encodeBlocks(document.backBlocks);
    final List<String> tags = <String>{
      ...document.tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty),
      'dsl',
    }.toList();
    return CardDslCard(
      front: front.trim(),
      back: back.trim(),
      tags: tags,
      deckName: '',
      note: document.note.trim(),
      type: '',
      difficulty: '',
      raw: '',
    );
  }

  /// Encode a single rich text surface into Card DSL.
  ///
  /// This is used by the simplified editor that only exposes one writing area,
  /// but still needs to persist WYSIWYG styling into the backend DSL format.
  static String encodeSingleRichText(EditorRichText richText) {
    return _encodeRichText(richText).trim();
  }

  static List<EditorBlock> _mapBlocks(List<DslBlockNode> input) {
    if (input.isEmpty) {
      return <EditorBlock>[_newParagraphBlock()];
    }
    return input.map(_mapBlock).toList();
  }

  static EditorBlock _mapBlock(DslBlockNode block) {
    if (block is DslParagraphNode) {
      if (_paragraphContainsFill(block.lines)) {
        return EditorBlock(
          id: _uuid.v4(),
          type: EditorBlockType.fill,
          data: _fillBlockDataFromLines(block.lines),
        );
      }
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.paragraph,
        data: ParagraphBlockData(richText: _richTextFromLines(block.lines)),
      );
    }
    if (block is DslHeadingNode) {
      final EditorBlockType type = switch (block.level) {
        1 => EditorBlockType.heading1,
        2 => EditorBlockType.heading2,
        _ => EditorBlockType.heading3,
      };
      return EditorBlock(
        id: _uuid.v4(),
        type: type,
        data: HeadingBlockData(richText: _richTextFromNodes(block.content)),
      );
    }
    if (block is DslDividerNode) {
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.divider,
        data: const ParagraphBlockData(richText: EditorRichText.empty),
      );
    }
    if (block is DslCodeBlockNode) {
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.code,
        data: CodeBlockData(language: block.language ?? '', code: block.code),
      );
    }
    if (block is DslMathBlockNode) {
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.math,
        data: MathBlockData(latex: block.latex),
      );
    }
    if (block is DslImageNode) {
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.image,
        data: MediaBlockData(alt: block.alt, src: block.urlOrPath),
      );
    }
    if (block is DslAudioNode) {
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.audio,
        data: MediaBlockData(alt: block.alt, src: block.urlOrPath),
      );
    }
    if (block is DslHintNode) {
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.hint,
        data: FoldableBlockData(
          title: block.title,
          blocks: _mapBlocks(block.blocks),
        ),
      );
    }
    if (block is DslExplainNode) {
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.explain,
        data: FoldableBlockData(
          title: block.title,
          blocks: _mapBlocks(block.blocks),
        ),
      );
    }
    if (block is DslBlockQuoteNode) {
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.quote,
        data: QuoteBlockData(blocks: _mapBlocks(block.blocks)),
      );
    }
    if (block is DslChoiceGroupNode) {
      return EditorBlock(
        id: _uuid.v4(),
        type: block.multiSelect
            ? EditorBlockType.multipleChoice
            : EditorBlockType.singleChoice,
        data: ChoiceBlockData(
          question: EditorRichText.empty,
          multiSelect: block.multiSelect,
          options: block.options
              .map(
                (option) => ChoiceOptionData(
                  id: _uuid.v4(),
                  richText: _richTextFromNodes(option.content),
                  isCorrect: option.isCorrect,
                ),
              )
              .toList(),
        ),
      );
    }
    if (block is DslJudgeGroupNode) {
      final DslJudgeItem first = block.items.isNotEmpty
          ? block.items.first
          : const DslJudgeItem(isTrue: true, content: <DslInlineNode>[]);
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.trueFalse,
        data: TrueFalseBlockData(
          statement: _richTextFromNodes(first.content),
          isTrue: first.isTrue,
        ),
      );
    }
    if (block is DslSortNode) {
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.sorting,
        data: SortingBlockData(
          items: block.items
              .map(
                (item) => SortItemData(
                  id: _uuid.v4(),
                  richText: _richTextFromNodes(item.content),
                  correctOrder: item.correctOrder,
                ),
              )
              .toList(),
        ),
      );
    }
    if (block is DslMatchNode) {
      return EditorBlock(
        id: _uuid.v4(),
        type: EditorBlockType.matching,
        data: MatchingBlockData(
          pairs: block.pairs
              .map(
                (pair) => MatchPairData(
                  id: _uuid.v4(),
                  left: _richTextFromNodes(pair.left),
                  right: _richTextFromNodes(pair.right),
                ),
              )
              .toList(),
        ),
      );
    }
    return EditorBlock(
      id: _uuid.v4(),
      type: EditorBlockType.paragraph,
      data: ParagraphBlockData(
        richText: EditorRichText(
          text: _rawBlockText(block),
          spans: const <InlineStyleSpan>[],
        ),
      ),
    );
  }

  static String _encodeBlocks(List<EditorBlock> blocks) {
    final Iterable<String> chunks = blocks
        .map(_encodeBlock)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
    return chunks.join('\n\n');
  }

  static String _encodeBlock(EditorBlock block) {
    switch (block.type) {
      case EditorBlockType.paragraph:
        return _encodeRichText((block.data as ParagraphBlockData).richText);
      case EditorBlockType.heading1:
        return '# ${_encodeRichText((block.data as HeadingBlockData).richText).trim()}'
            .trim();
      case EditorBlockType.heading2:
        return '## ${_encodeRichText((block.data as HeadingBlockData).richText).trim()}'
            .trim();
      case EditorBlockType.heading3:
        return '### ${_encodeRichText((block.data as HeadingBlockData).richText).trim()}'
            .trim();
      case EditorBlockType.fill:
        return _encodeFillBlock(block.data as FillBlockData);
      case EditorBlockType.quote:
        final QuoteBlockData data = block.data as QuoteBlockData;
        final List<String> lines = _encodeBlocks(data.blocks).split('\n');
        return lines
            .map((line) => line.trim().isEmpty ? '>' : '> $line')
            .join('\n');
      case EditorBlockType.code:
        final CodeBlockData data = block.data as CodeBlockData;
        final String lang = data.language.trim();
        return '```$lang\n${data.code.trimRight()}\n```';
      case EditorBlockType.divider:
        return '---';
      case EditorBlockType.image:
        final MediaBlockData data = block.data as MediaBlockData;
        return '!img[${data.alt.trim()}](${data.src.trim()})';
      case EditorBlockType.audio:
        final MediaBlockData data = block.data as MediaBlockData;
        return '!audio[${data.alt.trim()}](${data.src.trim()})';
      case EditorBlockType.math:
        final MathBlockData data = block.data as MathBlockData;
        return '\$\$${data.latex.trim()}\$\$';
      case EditorBlockType.hint:
        final FoldableBlockData data = block.data as FoldableBlockData;
        return '{hint:${data.title.trim()}}\n${_encodeBlocks(data.blocks)}\n{/hint}';
      case EditorBlockType.explain:
        final FoldableBlockData data = block.data as FoldableBlockData;
        return '{explain:${data.title.trim()}}\n${_encodeBlocks(data.blocks)}\n{/explain}';
      case EditorBlockType.singleChoice:
      case EditorBlockType.multipleChoice:
        final ChoiceBlockData data = block.data as ChoiceBlockData;
        final String question = _encodeRichText(data.question).trim();
        final String markerOff = data.multiSelect ? '[ ]' : '( )';
        final String Function(bool ok) markerOn = data.multiSelect
            ? (ok) => ok ? '[x]' : markerOff
            : (ok) => ok ? '(x)' : markerOff;
        final List<String> lines = <String>[
          if (question.isNotEmpty) question,
          ...data.options.map(
            (option) =>
                '${markerOn(option.isCorrect)} ${_encodeRichText(option.richText).trim()}',
          ),
        ];
        return lines.join('\n').trim();
      case EditorBlockType.trueFalse:
        final TrueFalseBlockData data = block.data as TrueFalseBlockData;
        return '${data.isTrue ? '{T}' : '{F}'} ${_encodeRichText(data.statement).trim()}'
            .trim();
      case EditorBlockType.sorting:
        final SortingBlockData data = block.data as SortingBlockData;
        return '{sort}\n${data.items.map((item) => '- [${item.correctOrder}] ${_encodeRichText(item.richText).trim()}').join('\n')}\n{/sort}';
      case EditorBlockType.matching:
        final MatchingBlockData data = block.data as MatchingBlockData;
        return '{match}\n${data.pairs.map((pair) => '${_encodeRichText(pair.left).trim()} <-> ${_encodeRichText(pair.right).trim()}').join('\n')}\n{/match}';
    }
  }

  static EditorRichText _richTextFromLines(List<List<DslInlineNode>> lines) {
    final String joined = lines.map(_rawInlineTextFromNodes).join('\n');
    return EditorRichText(text: joined, spans: const <InlineStyleSpan>[]);
  }

  static EditorRichText _richTextFromNodes(List<DslInlineNode> nodes) {
    return EditorRichText(
      text: _rawInlineTextFromNodes(nodes),
      spans: _spansFromNodes(nodes),
    );
  }

  static String _rawInlineTextFromNodes(List<DslInlineNode> nodes) {
    final StringBuffer buffer = StringBuffer();
    for (final DslInlineNode node in nodes) {
      if (node is DslTextNode) {
        buffer.write(node.text);
      } else if (node is DslInlineCodeNode) {
        buffer.write(node.code);
      } else if (node is DslBoldNode) {
        buffer.write(_rawInlineTextFromNodes(node.children));
      } else if (node is DslItalicNode) {
        buffer.write(_rawInlineTextFromNodes(node.children));
      } else if (node is DslStrikeNode) {
        buffer.write(_rawInlineTextFromNodes(node.children));
      } else if (node is DslHighlightNode) {
        buffer.write(_rawInlineTextFromNodes(node.children));
      } else if (node is DslUnderlineNode) {
        buffer.write(_rawInlineTextFromNodes(node.children));
      } else if (node is DslColorNode) {
        buffer.write(_rawInlineTextFromNodes(node.children));
      } else if (node is DslBgColorNode) {
        buffer.write(_rawInlineTextFromNodes(node.children));
      } else if (node is DslSizeNode) {
        buffer.write(_rawInlineTextFromNodes(node.children));
      } else if (node is DslSupNode) {
        buffer.write(_rawInlineTextFromNodes(node.children));
      } else if (node is DslSubNode) {
        buffer.write(_rawInlineTextFromNodes(node.children));
      } else if (node is DslKbdNode) {
        buffer.write(node.text);
      } else if (node is DslMathInlineNode) {
        buffer.write(node.latex);
      } else if (node is DslRefNode) {
        buffer.write(node.label.isEmpty ? node.id : node.label);
      } else if (node is DslClozeNode || node is DslAnswerBlankNode) {
        buffer.write('____');
      }
    }
    return buffer.toString();
  }

  static List<InlineStyleSpan> _spansFromNodes(List<DslInlineNode> nodes) {
    final List<InlineStyleSpan> spans = <InlineStyleSpan>[];
    int offset = 0;

    int walk(List<DslInlineNode> items) {
      int local = 0;
      for (final DslInlineNode node in items) {
        if (node is DslTextNode) {
          local += node.text.length;
          continue;
        }
        if (node is DslInlineCodeNode) {
          final int start = offset + local;
          final int end = start + node.code.length;
          spans.add(
            InlineStyleSpan(start: start, end: end, style: InlineStyle.code),
          );
          local += node.code.length;
          continue;
        }
        if (node is DslBoldNode) {
          final int start = offset + local;
          final int childLen = _plainLength(node.children);
          spans.add(
            InlineStyleSpan(
              start: start,
              end: start + childLen,
              style: InlineStyle.bold,
            ),
          );
          final int nestedOffset = offset;
          offset = start;
          walk(node.children);
          offset = nestedOffset;
          local += childLen;
          continue;
        }
        if (node is DslItalicNode) {
          final int start = offset + local;
          final int childLen = _plainLength(node.children);
          spans.add(
            InlineStyleSpan(
              start: start,
              end: start + childLen,
              style: InlineStyle.italic,
            ),
          );
          final int nestedOffset = offset;
          offset = start;
          walk(node.children);
          offset = nestedOffset;
          local += childLen;
          continue;
        }
        if (node is DslStrikeNode) {
          final int start = offset + local;
          final int childLen = _plainLength(node.children);
          spans.add(
            InlineStyleSpan(
              start: start,
              end: start + childLen,
              style: InlineStyle.strike,
            ),
          );
          final int nestedOffset = offset;
          offset = start;
          walk(node.children);
          offset = nestedOffset;
          local += childLen;
          continue;
        }
        if (node is DslHighlightNode) {
          final int start = offset + local;
          final int childLen = _plainLength(node.children);
          spans.add(
            InlineStyleSpan(
              start: start,
              end: start + childLen,
              style: InlineStyle.highlight,
            ),
          );
          final int nestedOffset = offset;
          offset = start;
          walk(node.children);
          offset = nestedOffset;
          local += childLen;
          continue;
        }
        if (node is DslUnderlineNode) {
          final int start = offset + local;
          final int childLen = _plainLength(node.children);
          spans.add(
            InlineStyleSpan(
              start: start,
              end: start + childLen,
              style: InlineStyle.underline,
            ),
          );
          final int nestedOffset = offset;
          offset = start;
          walk(node.children);
          offset = nestedOffset;
          local += childLen;
          continue;
        }
        if (node is DslSizeNode) {
          final int start = offset + local;
          final int childLen = _plainLength(node.children);
          final InlineStyle? style = switch (node.size.trim()) {
            'sm' => InlineStyle.fontSmall,
            'lg' => InlineStyle.fontLarge,
            _ => null,
          };
          if (style != null) {
            spans.add(
              InlineStyleSpan(
                start: start,
                end: start + childLen,
                style: style,
              ),
            );
          }
          final int nestedOffset = offset;
          offset = start;
          walk(node.children);
          offset = nestedOffset;
          local += childLen;
          continue;
        }
        final int len = switch (node) {
          DslColorNode(:final children) => _plainLength(children),
          DslBgColorNode(:final children) => _plainLength(children),
          DslSupNode(:final children) => _plainLength(children),
          DslSubNode(:final children) => _plainLength(children),
          DslKbdNode(:final text) => text.length,
          DslMathInlineNode(:final latex) => latex.length,
          DslRefNode(:final id, :final label) =>
            (label.isEmpty ? id : label).length,
          DslClozeNode() => 4,
          DslAnswerBlankNode() => 4,
          _ => 0,
        };
        local += len;
      }
      return local;
    }

    walk(nodes);
    return spans;
  }

  static int _plainLength(List<DslInlineNode> nodes) {
    return _rawInlineTextFromNodes(nodes).length;
  }

  static String _rawBlockText(DslBlockNode block) {
    return switch (block) {
      DslUnknownBlockNode(:final raw) => raw,
      _ => '',
    };
  }

  static String _encodeRichText(EditorRichText richText) {
    if (richText.text.trim().isEmpty) {
      return '';
    }
    final String text = richText.text;
    final List<InlineStyleSegment> spans = normalizeInlineStyleSegments(
      text: text,
      spans: richText.spans,
    );
    if (spans.isEmpty) {
      return text;
    }

    final StringBuffer out = StringBuffer();
    int cursor = 0;
    for (final InlineStyleSegment span in spans) {
      final int start = span.start.clamp(0, text.length);
      final int end = span.end.clamp(0, text.length);
      if (end <= start) continue;
      if (start > cursor) {
        out.write(text.substring(cursor, start));
      }
      final String content = text.substring(start, end);
      out.write(_wrapInlineStyles(content, span.styles));
      cursor = end;
    }
    if (cursor < text.length) {
      out.write(text.substring(cursor));
    }
    return out.toString();
  }

  static String _wrapInlineStyles(String content, Set<InlineStyle> styles) {
    final List<InlineStyle> ordered = styles.toList()
      ..sort(
        (InlineStyle a, InlineStyle b) =>
            _inlineStylePriority(a).compareTo(_inlineStylePriority(b)),
      );
    String output = content;
    for (final InlineStyle style in ordered) {
      output = switch (style) {
        InlineStyle.bold => '**$output**',
        InlineStyle.italic => '*$output*',
        InlineStyle.code => '`$output`',
        InlineStyle.strike => '~~$output~~',
        InlineStyle.highlight => '==$output==',
        InlineStyle.underline => '{u:$output}',
        InlineStyle.cloze => '{{$output}}',
        InlineStyle.fontSmall => '{size:sm:$output}',
        InlineStyle.fontLarge => '{size:lg:$output}',
      };
    }
    return output;
  }

  static int _inlineStylePriority(InlineStyle style) {
    return switch (style) {
      InlineStyle.fontSmall => 1,
      InlineStyle.fontLarge => 1,
      InlineStyle.bold => 2,
      InlineStyle.italic => 3,
      InlineStyle.underline => 4,
      InlineStyle.cloze => 5,
      InlineStyle.strike => 6,
      InlineStyle.highlight => 7,
      InlineStyle.code => 8,
    };
  }

  static EditorBlock createDefaultBlock(EditorBlockType type) {
    switch (type) {
      case EditorBlockType.paragraph:
        return _newParagraphBlock();
      case EditorBlockType.heading1:
      case EditorBlockType.heading2:
      case EditorBlockType.heading3:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: const HeadingBlockData(richText: EditorRichText.empty),
        );
      case EditorBlockType.fill:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: const FillBlockData(
            text: '在这里输入原文，然后选中需要挖空的内容',
            blanks: <FillBlankData>[],
          ),
        );
      case EditorBlockType.quote:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: QuoteBlockData(blocks: <EditorBlock>[_newParagraphBlock()]),
        );
      case EditorBlockType.code:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: const CodeBlockData(language: '', code: ''),
        );
      case EditorBlockType.divider:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: const ParagraphBlockData(richText: EditorRichText.empty),
        );
      case EditorBlockType.image:
      case EditorBlockType.audio:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: const MediaBlockData(alt: '', src: ''),
        );
      case EditorBlockType.math:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: const MathBlockData(latex: ''),
        );
      case EditorBlockType.hint:
      case EditorBlockType.explain:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: FoldableBlockData(
            title: '',
            blocks: <EditorBlock>[_newParagraphBlock()],
          ),
        );
      case EditorBlockType.singleChoice:
      case EditorBlockType.multipleChoice:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: ChoiceBlockData(
            question: EditorRichText.empty,
            multiSelect: type == EditorBlockType.multipleChoice,
            options: <ChoiceOptionData>[
              ChoiceOptionData(
                id: _uuid.v4(),
                richText: const EditorRichText(
                  text: '选项 A',
                  spans: <InlineStyleSpan>[],
                ),
                isCorrect: false,
              ),
              ChoiceOptionData(
                id: _uuid.v4(),
                richText: const EditorRichText(
                  text: '选项 B',
                  spans: <InlineStyleSpan>[],
                ),
                isCorrect: true,
              ),
            ],
          ),
        );
      case EditorBlockType.trueFalse:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: const TrueFalseBlockData(
            statement: EditorRichText(text: '判断陈述', spans: <InlineStyleSpan>[]),
            isTrue: true,
          ),
        );
      case EditorBlockType.sorting:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: SortingBlockData(
            items: <SortItemData>[
              SortItemData(
                id: _uuid.v4(),
                richText: const EditorRichText(
                  text: '步骤 1',
                  spans: <InlineStyleSpan>[],
                ),
                correctOrder: 1,
              ),
              SortItemData(
                id: _uuid.v4(),
                richText: const EditorRichText(
                  text: '步骤 2',
                  spans: <InlineStyleSpan>[],
                ),
                correctOrder: 2,
              ),
            ],
          ),
        );
      case EditorBlockType.matching:
        return EditorBlock(
          id: _uuid.v4(),
          type: type,
          data: MatchingBlockData(
            pairs: <MatchPairData>[
              MatchPairData(
                id: _uuid.v4(),
                left: const EditorRichText(
                  text: '左侧 A',
                  spans: <InlineStyleSpan>[],
                ),
                right: const EditorRichText(
                  text: '右侧 A',
                  spans: <InlineStyleSpan>[],
                ),
              ),
            ],
          ),
        );
    }
  }

  static EditorBlock _newParagraphBlock() {
    return EditorBlock(
      id: _uuid.v4(),
      type: EditorBlockType.paragraph,
      data: const ParagraphBlockData(richText: EditorRichText.empty),
    );
  }

  static bool _paragraphContainsFill(List<List<DslInlineNode>> lines) {
    for (final List<DslInlineNode> line in lines) {
      for (final DslInlineNode node in line) {
        if (node is DslClozeNode || node is DslAnswerBlankNode) {
          return true;
        }
      }
    }
    return false;
  }

  static FillBlockData _fillBlockDataFromLines(
    List<List<DslInlineNode>> lines,
  ) {
    final StringBuffer text = StringBuffer();
    final List<FillBlankData> blanks = <FillBlankData>[];

    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      if (lineIndex > 0) {
        text.write('\n');
      }
      for (final DslInlineNode node in lines[lineIndex]) {
        if (node is DslTextNode) {
          text.write(node.text);
          continue;
        }
        if (node is DslClozeNode) {
          final String answer = node.answers.isNotEmpty
              ? node.answers.first
              : '';
          final int start = text.length;
          text.write(answer);
          blanks.add(
            FillBlankData(
              id: _uuid.v4(),
              start: start,
              end: text.length,
              answer: answer,
            ),
          );
          continue;
        }
        if (node is DslAnswerBlankNode) {
          final String answer = (node.expected ?? '').trim();
          final int start = text.length;
          text.write(answer);
          blanks.add(
            FillBlankData(
              id: _uuid.v4(),
              start: start,
              end: text.length,
              answer: answer,
            ),
          );
          continue;
        }
        text.write(_rawInlineTextFromNodes(<DslInlineNode>[node]));
      }
    }

    return FillBlockData(text: text.toString(), blanks: blanks);
  }

  static String _encodeFillBlock(FillBlockData data) {
    if (data.text.trim().isEmpty) {
      return '';
    }
    final List<FillBlankData> blanks = List<FillBlankData>.from(data.blanks)
      ..sort((a, b) => b.start.compareTo(a.start));
    String output = data.text;
    for (final FillBlankData blank in blanks) {
      final int start = blank.start.clamp(0, output.length);
      final int end = blank.end.clamp(start, output.length);
      output =
          '${output.substring(0, start)}{{${blank.answer}}}${output.substring(end)}';
    }
    return output;
  }
}
