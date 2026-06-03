import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../card_dsl/dsl_view.dart';
import '../layout/responsive_layout.dart';
import '../theme/app_design.dart';
import '../../core/app_store.dart';
import '../../core/card_document.dart';
import 'document_codec.dart';
import 'models.dart';
import 'rich_text_controller.dart';
import 'single_choice_block.dart';

/// A simplified card editor focused on a single writing surface.
///
/// Why this rewrite exists:
/// - The previous block-based editor introduced too much structural overhead.
/// - The current product goal is to let users "write a card first" with minimal UI.
/// - Therefore this screen intentionally reduces the editing model to:
///   1) one blank card,
///   2) one multiline text input,
///   3) four inline formatting actions.
class BlockCardEditorScreen extends ConsumerStatefulWidget {
  const BlockCardEditorScreen({super.key, required this.deckId, this.cardId});

  final String deckId;
  final String? cardId;

  @override
  ConsumerState<BlockCardEditorScreen> createState() =>
      _BlockCardEditorScreenState();
}

class _BlockCardEditorScreenState extends ConsumerState<BlockCardEditorScreen> {
  static const Uuid _uuid = Uuid();
  static const String _singleChoiceStartMarker = '{single-choice}';
  static const String _singleChoiceEndMarker = '{/single-choice}';
  static const String _multiChoiceStartMarker = '{multi-choice}';
  static const String _multiChoiceEndMarker = '{/multi-choice}';
  bool _initialized = false;
  bool _studyEnabled = true;
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;
  final List<_BodyFlowNode> _bodyNodes = <_BodyFlowNode>[];
  String? _activeTextNodeId;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _titleFocusNode = FocusNode();
    _titleController.addListener(_handleEditorChanged);
    // Start with a single blank paragraph.
    _resetBodyNodes(<_BodyFlowNode>[_createTextNode(EditorRichText.empty)]);
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleEditorChanged);
    _titleController.dispose();
    _titleFocusNode.dispose();
    _disposeBodyNodes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    _ensureInitialized(state);
    final DeckModel? deck = _resolveDeck(state);
    final bool hasContent = _hasMeaningfulContent;
    final bool canSave = !state.syncInProgress && hasContent;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(widget.cardId == null ? '创建卡片' : '编辑卡片'),
        actions: <Widget>[
          IconButton(
            onPressed: state.syncInProgress || !hasContent
                ? null
                : _openAIRewriteSheet,
            icon: const Icon(Icons.auto_fix_high_outlined),
            tooltip: widget.cardId == null ? 'AI 优化当前草稿' : 'AI 优化卡片',
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double horizontalPadding = AppResponsive.horizontalPadding(
              constraints.maxWidth,
            );
            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                0,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: SizedBox.expand(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (deck != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              deck.name,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _StudyToggleCard(
                            value: _studyEnabled,
                            reviewOrder:
                                deck?.reviewOrder ?? DeckReviewOrder.sequential,
                            onChanged: (bool value) {
                              setState(() {
                                _studyEnabled = value;
                              });
                            },
                          ),
                        ),
                        Expanded(child: _buildEditorSurface(theme)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double horizontalPadding = AppResponsive.horizontalPadding(
              constraints.maxWidth,
            );

            return DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  10,
                  horizontalPadding,
                  14,
                ),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: _EditorCommandBar(
                      canSave: canSave,
                      hasContent: hasContent,
                      saving: state.syncInProgress,
                      isCreating: widget.cardId == null,
                      onPreview: _openPreviewSheet,
                      onAIRewrite: _openAIRewriteSheet,
                      onSave: _saveCard,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleEditorChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildEditorSurface(ThemeData theme) {
    final bool canUsePrimaryCanvas =
        !_hasAnswerLine &&
        _bodyNodes.length == 1 &&
        _bodyNodes.first is _TextFlowNode;
    final _TextFlowNode? singleTextNode = canUsePrimaryCanvas
        ? _bodyNodes.first as _TextFlowNode
        : null;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          _SimpleToolbar(
            onToggleCloze: _toggleClozeAtSelection,
            onBold: () => _applyInlineStyle(InlineStyle.bold),
            onHighlight: () => _applyInlineStyle(InlineStyle.highlight),
            onUnderline: () => _applyInlineStyle(InlineStyle.underline),
            onFontDown: () => _applyInlineStyle(InlineStyle.fontSmall),
            onFontUp: () => _applyInlineStyle(InlineStyle.fontLarge),
            onInsertImage: _insertImage,
            onInsertAnswerLine: _insertAnswerLineAtCursor,
            onInsertSingleChoice: _insertSingleChoiceAtCursor,
            onInsertMultiChoice: _insertMultiChoiceAtCursor,
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _titleController,
                    focusNode: _titleFocusNode,
                    maxLines: 1,
                    textInputAction: TextInputAction.next,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                    decoration: const InputDecoration(
                      hintText: '输入题目（可选）',
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    onSubmitted: (_) => _focusFirstTextNode(),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: singleTextNode != null
                        ? _PrimaryTextCanvas(node: singleTextNode)
                        : Scrollbar(
                            thumbVisibility: true,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: _bodyNodes.length,
                              itemBuilder: (BuildContext context, int index) {
                                return _buildFlowNodeItem(
                                  node: _bodyNodes[index],
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowNodeItem({required _BodyFlowNode node}) {
    if (node is _TextFlowNode) {
      return _InlineTextNodeEditor(
        key: ValueKey<String>(node.id),
        node: node,
        expandedSurface: false,
      );
    }
    if (node is _AnswerLineFlowNode) {
      return const _InlineAnswerLineMarker();
    }
    if (node is _SingleChoiceFlowNode) {
      return SingleChoiceBlockCard(
        key: ValueKey<String>(node.id),
        data: node.data,
        embedded: true,
        autofocusQuestion: node.autofocusQuestion,
        onChanged: (SingleChoiceBlockData data) {
          node.data = data;
          _handleEditorChanged();
        },
        onDelete: () => _removeFlowNode(node.id),
      );
    }
    if (node is _MultiChoiceFlowNode) {
      return MultiChoiceBlockCard(
        key: ValueKey<String>(node.id),
        data: node.data,
        embedded: true,
        autofocusQuestion: node.autofocusQuestion,
        onChanged: (MultiChoiceBlockData data) {
          node.data = data;
          _handleEditorChanged();
        },
        onDelete: () => _removeFlowNode(node.id),
      );
    }
    final _ImageFlowNode imageNode = node as _ImageFlowNode;
    return _InlineImageNodeCard(
      key: ValueKey<String>(node.id),
      node: imageNode,
      onDelete: () => _removeFlowNode(imageNode.id),
    );
  }

  DeckModel? _resolveDeck(AppState state) {
    for (final DeckModel deck in state.decks) {
      if (deck.id == widget.deckId) {
        return deck;
      }
    }
    return null;
  }

  bool get _hasAnswerLine {
    return _bodyNodes.any((_BodyFlowNode node) => node is _AnswerLineFlowNode);
  }

  _DocumentSections get _documentSections {
    final List<_BodyFlowNode> promptNodes = <_BodyFlowNode>[];
    final List<_BodyFlowNode> answerNodes = <_BodyFlowNode>[];
    bool inAnswer = false;
    bool hasAnswerLine = false;

    for (final _BodyFlowNode node in _bodyNodes) {
      if (node is _AnswerLineFlowNode) {
        hasAnswerLine = true;
        inAnswer = true;
        continue;
      }
      if (inAnswer) {
        answerNodes.add(node);
      } else {
        promptNodes.add(node);
      }
    }

    return _DocumentSections(
      prompt: _encodeNodes(promptNodes),
      answer: _encodeNodes(answerNodes),
      hasAnswerLine: hasAnswerLine,
    );
  }

  String get _previewFrontContent {
    final String title = _titleController.text.trim();
    final String body = _documentSections.prompt;
    if (title.isEmpty) {
      return body;
    }
    if (body.isEmpty) {
      return title;
    }
    return '$title\n\n$body';
  }

  String get _previewAnswerContent => _documentSections.answer;

  bool get _hasMeaningfulContent {
    if (_titleController.text.trim().isNotEmpty) {
      return true;
    }
    for (final _BodyFlowNode node in _bodyNodes) {
      if (node is _TextFlowNode && node.controller.text.trim().isNotEmpty) {
        return true;
      }
      if (node is! _TextFlowNode && node is! _AnswerLineFlowNode) {
        return true;
      }
    }
    return false;
  }

  Future<void> _openPreviewSheet() async {
    await showAdaptiveSheet<void>(
      context: context,
      maxWidth: 860,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.78,
              child: _EditorPreviewPanel(
                front: _previewFrontContent,
                answer: _previewAnswerContent,
                isEmpty: !_hasMeaningfulContent,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Initialize the editor with prompt + answer content only once.
  void _ensureInitialized(AppState state) {
    if (_initialized) {
      return;
    }
    if (widget.cardId == null) {
      _titleController.text = '';
      _studyEnabled = true;
      _resetBodyNodes(<_BodyFlowNode>[_createTextNode(EditorRichText.empty)]);
      _initialized = true;
      return;
    }

    final CardModel? currentCard = state.cards.cast<CardModel?>().firstWhere(
      (CardModel? item) => item?.id == widget.cardId,
      orElse: () => null,
    );
    final CardDocumentParts parts = CardDocumentCodec.parse(
      currentCard?.content ?? '',
    );
    final _EditorSeed seed = currentCard == null
        ? const _EditorSeed(
            title: '',
            body: '',
            answer: '',
            hasAnswerLine: false,
          )
        : _seedFromCard(currentCard, parts);
    _titleController.text = seed.title;
    _studyEnabled = currentCard?.studyEnabled ?? false;
    _resetBodyNodes(
      _buildDocumentNodes(
        prompt: seed.body,
        answer: seed.answer,
        hasAnswerLine: seed.hasAnswerLine,
      ),
    );
    _initialized = true;
  }

  _EditorSeed _seedFromCard(CardModel currentCard, CardDocumentParts parts) {
    final String prompt = parts.prompt.trim();
    final String resolvedTitle = currentCard.title.isNotEmpty
        ? currentCard.title.trim()
        : (parts.prompt.split('\n').firstOrNull ?? '').trim();
    final String body = _stripLeadingTitle(prompt, resolvedTitle);
    return _EditorSeed(
      title: resolvedTitle,
      body: body,
      answer: parts.answer,
      hasAnswerLine: parts.hasAnswerLine || parts.answer.trim().isNotEmpty,
    );
  }

  String _stripLeadingTitle(String prompt, String title) {
    final String normalizedPrompt = prompt.trim();
    final String normalizedTitle = title.trim();
    if (normalizedPrompt.isEmpty || normalizedTitle.isEmpty) {
      return normalizedPrompt;
    }
    if (normalizedPrompt == normalizedTitle) {
      return '';
    }
    final String doubleBreakPrefix = '$normalizedTitle\n\n';
    if (normalizedPrompt.startsWith(doubleBreakPrefix)) {
      return normalizedPrompt.substring(doubleBreakPrefix.length).trim();
    }
    final String singleBreakPrefix = '$normalizedTitle\n';
    if (normalizedPrompt.startsWith(singleBreakPrefix)) {
      return normalizedPrompt.substring(singleBreakPrefix.length).trim();
    }
    return normalizedPrompt;
  }

  /// Save prompt + answer content back to the existing card schema.
  Future<void> _saveCard() async {
    final _CurrentEditorContent current = _currentEditorContent();
    final String title = current.title;
    final String content = current.content;
    if (content.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入题目或卡片内容')));
      return;
    }

    final AppStore store = ref.read(appStoreProvider.notifier);
    final bool success = widget.cardId == null
        ? await store.createCard(
            deckId: widget.deckId,
            title: title,
            content: content,
            note: '',
            tags: const <String>['dsl'],
            studyEnabled: _studyEnabled,
          )
        : await store.updateCard(
            cardId: widget.cardId!,
            title: title,
            content: content,
            note: '',
            tags: const <String>['dsl'],
            studyEnabled: _studyEnabled,
          );

    if (mounted && success) {
      Navigator.of(context).pop();
    }
  }

  _CurrentEditorContent _currentEditorContent() {
    final String title = _titleController.text.trim();
    final _DocumentSections sections = _documentSections;
    final String body = sections.prompt;
    final String answer = sections.answer;
    final String content = CardDocumentCodec.compose(
      prompt: title.isEmpty ? body : '$title\n\n$body'.trim(),
      answer: answer,
      includeAnswerLine: sections.hasAnswerLine,
    );
    return _CurrentEditorContent(title: title, content: content);
  }

  Future<void> _openAIRewriteSheet() async {
    final _CurrentEditorContent current = _currentEditorContent();
    if (current.content.trim().isEmpty) {
      _focusFirstTextNode();
      return;
    }
    final AIRewriteCandidate? candidate =
        await showModalBottomSheet<AIRewriteCandidate>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (BuildContext context) {
            return _AIRewriteCardSheet(
              cardId: widget.cardId,
              title: current.title,
              content: current.content,
            );
          },
        );
    if (candidate == null || !mounted) {
      return;
    }
    _applyAIRewriteCandidate(candidate);
  }

  void _applyAIRewriteCandidate(AIRewriteCandidate candidate) {
    final CardDocumentParts parts = CardDocumentCodec.parse(candidate.content);
    final String title = candidate.title.trim().isEmpty
        ? (firstNonEmptyLine(parts.prompt) ?? '')
        : candidate.title.trim();
    _titleController.text = title;
    _resetBodyNodes(
      _buildDocumentNodes(
        prompt: _stripLeadingTitle(parts.prompt, title),
        answer: parts.answer,
        hasAnswerLine: parts.hasAnswerLine || parts.answer.trim().isNotEmpty,
      ),
    );
    _handleEditorChanged();
  }

  /// Apply a visual inline style directly to the selected text.
  ///
  /// The user should see formatting immediately in the editor. We only encode
  /// these spans back to DSL at save time.
  void _applyInlineStyle(InlineStyle style) {
    final _TextFlowNode? node = _activeTextNode;
    if (node == null) {
      _focusFirstTextNode();
      return;
    }
    final TextSelection selection = node.controller.selection;
    if (!selection.isValid) {
      node.focusNode.requestFocus();
      return;
    }

    final int start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final int end = selection.start < selection.end
        ? selection.end
        : selection.start;
    if (start == end) {
      return;
    }

    final List<InlineStyleSpan> spans = applyInlineStyleToRange(
      spans: node.controller.model.spans,
      start: start,
      end: end,
      style: style,
    );
    node.controller.setSpans(spans, notify: true);
    node.focusNode.requestFocus();
    setState(() {});
  }

  void _toggleClozeAtSelection() {
    final _TextFlowNode? node = _activeTextNode;
    if (node == null) {
      _focusFirstTextNode();
      return;
    }
    final TextSelection selection = node.controller.selection;
    if (!selection.isValid) {
      node.focusNode.requestFocus();
      return;
    }

    final int start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final int end = selection.start < selection.end
        ? selection.end
        : selection.start;
    if (start == end) {
      return;
    }
    final String selectedText = node.controller.text.substring(start, end);
    if (selectedText.contains('\n')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('填空暂不支持跨行选择')));
      return;
    }

    final List<InlineStyleSpan> spans = List<InlineStyleSpan>.from(
      node.controller.model.spans,
    );
    final int exactIndex = spans.indexWhere(
      (InlineStyleSpan span) =>
          span.style == InlineStyle.cloze &&
          span.start == start &&
          span.end == end,
    );
    if (exactIndex >= 0) {
      spans.removeAt(exactIndex);
      node.controller.setSpans(spans, notify: true);
      node.focusNode.requestFocus();
      setState(() {});
      return;
    }

    final List<InlineStyleSpan> nextSpans = <InlineStyleSpan>[];
    for (final InlineStyleSpan span in spans) {
      final bool overlaps = start < span.end && end > span.start;
      if (!overlaps) {
        nextSpans.add(span);
        continue;
      }
      if (span.style == InlineStyle.cloze) {
        continue;
      }
      if (span.start < start) {
        nextSpans.add(
          InlineStyleSpan(start: span.start, end: start, style: span.style),
        );
      }
      if (span.end > end) {
        nextSpans.add(
          InlineStyleSpan(start: end, end: span.end, style: span.style),
        );
      }
    }
    nextSpans.add(
      InlineStyleSpan(start: start, end: end, style: InlineStyle.cloze),
    );
    node.controller.setSpans(nextSpans, notify: true);
    node.focusNode.requestFocus();
    setState(() {});
  }

  Future<void> _insertImage() async {
    final _ImageInsertMode? mode = await showAdaptiveSheet<_ImageInsertMode>(
      context: context,
      maxWidth: 420,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('选择本地图片'),
                onTap: () => Navigator.of(context).pop(_ImageInsertMode.local),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('输入图片链接'),
                onTap: () => Navigator.of(context).pop(_ImageInsertMode.remote),
              ),
            ],
          ),
        );
      },
    );
    if (mode == null) return;

    if (mode == _ImageInsertMode.local) {
      await _insertLocalImage();
      return;
    }
    await _insertRemoteImage();
  }

  Future<void> _insertLocalImage() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final PlatformFile file = result.files.first;
    final String? filePath = file.path;
    if (filePath == null || filePath.trim().isEmpty) return;
    final String alt = path.basenameWithoutExtension(filePath);
    _insertImageNodeAtCursor(src: filePath, alt: alt.isEmpty ? '图片' : alt);
  }

  Future<void> _insertRemoteImage() async {
    final TextEditingController urlController = TextEditingController();
    final TextEditingController altController = TextEditingController();
    final bool? confirmed = await showAdaptiveSheet<bool>(
      context: context,
      maxWidth: 520,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('插入图片链接', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '图片地址',
                  hintText: 'https://example.com/demo.png',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: altController,
                decoration: const InputDecoration(
                  labelText: '图片说明',
                  hintText: '可选',
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('插入'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) {
      urlController.dispose();
      altController.dispose();
      return;
    }

    final String src = urlController.text.trim();
    final String alt = altController.text.trim();
    urlController.dispose();
    altController.dispose();
    if (src.isEmpty) return;

    _insertImageNodeAtCursor(src: src, alt: alt.isEmpty ? '图片' : alt);
  }

  void _insertImageNodeAtCursor({required String src, required String alt}) {
    final String normalizedSrc = src.trim();
    if (normalizedSrc.isEmpty) return;

    final _TextFlowNode afterNode = _insertBodyNodeAtCursor(
      _ImageFlowNode(id: _uuid.v4(), alt: alt, src: normalizedSrc),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      afterNode.focusNode.requestFocus();
      afterNode.controller.selection = const TextSelection.collapsed(offset: 0);
    });
  }

  void _insertAnswerLineAtCursor() {
    if (_hasAnswerLine) {
      _focusTextAfterAnswerLine();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前卡片已经有一条答案线')));
      return;
    }

    final _TextFlowNode afterNode = _insertBodyNodeAtCursor(
      _AnswerLineFlowNode(id: _uuid.v4()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      afterNode.focusNode.requestFocus();
      afterNode.controller.selection = const TextSelection.collapsed(offset: 0);
    });
  }

  void _insertSingleChoiceAtCursor() {
    _insertBodyNodeAtCursor(
      _SingleChoiceFlowNode(
        id: _uuid.v4(),
        data: const SingleChoiceBlockData(
          question: '',
          options: <String>['选项 1', '选项 2'],
          correctIndex: 0,
        ),
        autofocusQuestion: true,
      ),
    );
  }

  void _focusTextAfterAnswerLine() {
    bool afterLine = false;
    for (final _BodyFlowNode node in _bodyNodes) {
      if (node is _AnswerLineFlowNode) {
        afterLine = true;
        continue;
      }
      if (afterLine && node is _TextFlowNode) {
        _activeTextNodeId = node.id;
        node.focusNode.requestFocus();
        node.controller.selection = TextSelection.collapsed(
          offset: node.controller.text.length,
        );
        return;
      }
    }
  }

  void _insertMultiChoiceAtCursor() {
    _insertBodyNodeAtCursor(
      _MultiChoiceFlowNode(
        id: _uuid.v4(),
        data: const MultiChoiceBlockData(
          question: '',
          options: <String>['选项 1', '选项 2', '选项 3'],
          correctIndexes: <int>[0, 1],
        ),
        autofocusQuestion: true,
      ),
    );
  }

  void _focusFirstTextNode() {
    final Iterable<_TextFlowNode> textNodes = _bodyNodes
        .whereType<_TextFlowNode>();
    final _TextFlowNode? first = textNodes.isNotEmpty ? textNodes.first : null;
    if (first == null) return;
    _activeTextNodeId = first.id;
    first.focusNode.requestFocus();
  }

  _TextFlowNode? get _activeTextNode {
    final List<_TextFlowNode> textNodes = _bodyNodes
        .whereType<_TextFlowNode>()
        .toList(growable: false);
    if (textNodes.isEmpty) {
      return null;
    }
    final String? id = _activeTextNodeId;
    if (id == null) {
      return textNodes.first;
    }
    for (final _TextFlowNode node in textNodes) {
      if (node.id == id) {
        return node;
      }
    }
    return textNodes.first;
  }

  void _disposeBodyNodes() {
    for (final _BodyFlowNode node in _bodyNodes) {
      if (node is _TextFlowNode) {
        node.controller.removeListener(_handleEditorChanged);
        node.controller.dispose();
        node.focusNode.dispose();
      }
    }
    _bodyNodes.clear();
  }

  void _resetBodyNodes(List<_BodyFlowNode> next) {
    _disposeBodyNodes();
    _bodyNodes.addAll(
      next.isEmpty
          ? <_BodyFlowNode>[_createTextNode(EditorRichText.empty)]
          : next,
    );
    final _TextFlowNode? first =
        _bodyNodes.whereType<_TextFlowNode>().isNotEmpty
        ? _bodyNodes.whereType<_TextFlowNode>().first
        : null;
    _activeTextNodeId = first?.id;
  }

  _TextFlowNode _createTextNode(EditorRichText initial) {
    final String id = _uuid.v4();
    final EditorRichTextController controller = EditorRichTextController(
      initial: initial,
    );
    controller.addListener(_handleEditorChanged);
    final FocusNode focusNode = FocusNode();
    focusNode.addListener(() {
      if (!focusNode.hasFocus) return;
      _activeTextNodeId = id;
    });
    return _TextFlowNode(id: id, controller: controller, focusNode: focusNode);
  }

  _TextFlowNode _ensureTrailingTextNode() {
    if (_bodyNodes.isNotEmpty && _bodyNodes.last is _TextFlowNode) {
      return _bodyNodes.last as _TextFlowNode;
    }
    final _TextFlowNode node = _createTextNode(EditorRichText.empty);
    setState(() {
      _bodyNodes.add(node);
      _activeTextNodeId = node.id;
    });
    return node;
  }

  _TextFlowNode _insertBodyNodeAtCursor(_BodyFlowNode insertedNode) {
    final _TextFlowNode target = _activeTextNode ?? _ensureTrailingTextNode();
    final TextSelection selection = target.controller.selection;
    final int cursor = selection.isValid
        ? selection.baseOffset.clamp(0, target.controller.text.length)
        : target.controller.text.length;
    final _RichTextSplit split = _splitRichText(
      target.controller.model,
      cursor,
    );

    target.controller.updateModel(split.before, notify: true);

    final int targetIndex = _bodyNodes.indexWhere((n) => n.id == target.id);
    final _TextFlowNode afterNode = _createTextNode(split.after);

    setState(() {
      _bodyNodes.insert(targetIndex + 1, insertedNode);
      _bodyNodes.insert(targetIndex + 2, afterNode);
      _activeTextNodeId = afterNode.id;
    });
    return afterNode;
  }

  void _removeFlowNode(String id) {
    final int index = _bodyNodes.indexWhere((n) => n.id == id);
    if (index < 0) return;
    setState(() {
      _bodyNodes.removeAt(index);
    });
    _mergeAdjacentTextNodesAround(index - 1);
  }

  void _mergeAdjacentTextNodesAround(int index) {
    if (index < 0 || index >= _bodyNodes.length - 1) return;
    final _BodyFlowNode left = _bodyNodes[index];
    final _BodyFlowNode right = _bodyNodes[index + 1];
    if (left is! _TextFlowNode || right is! _TextFlowNode) return;

    final EditorRichText merged = _mergeRichText(
      left.controller.model,
      right.controller.model,
    );
    left.controller.updateModel(merged, notify: true);
    right.controller.removeListener(_handleEditorChanged);
    right.controller.dispose();
    right.focusNode.dispose();
    setState(() {
      _bodyNodes.removeAt(index + 1);
      _activeTextNodeId = left.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      left.focusNode.requestFocus();
      left.controller.selection = TextSelection.collapsed(
        offset: left.controller.text.length,
      );
    });
  }

  List<_BodyFlowNode> _parseBodyNodes(String raw) {
    final String input = raw;
    if (input.trim().isEmpty) {
      return <_BodyFlowNode>[_createTextNode(EditorRichText.empty)];
    }

    final RegExp imageLine = RegExp(
      r'^\s*!img\[(.*?)\]\((.*?)\)\s*$',
      multiLine: true,
    );
    final List<_BodyFlowNode> nodes = <_BodyFlowNode>[];

    final List<String> lines = input.split('\n');
    final StringBuffer buffer = StringBuffer();

    void flushText() {
      final String chunk = buffer.toString().trimRight();
      buffer.clear();
      if (chunk.isEmpty) return;
      final EditorRichText model = transformInlineMarkdown(
        raw: chunk,
        caretOffset: chunk.length,
      );
      nodes.add(_createTextNode(model));
    }

    int index = 0;
    while (index < lines.length) {
      final String line = lines[index];
      if (line.trim() == _singleChoiceStartMarker) {
        flushText();
        final int startIndex = index;
        final List<String> blockLines = <String>[];
        int endIndex = index + 1;
        while (endIndex < lines.length &&
            lines[endIndex].trim() != _singleChoiceEndMarker) {
          blockLines.add(lines[endIndex]);
          endIndex += 1;
        }

        if (endIndex >= lines.length) {
          for (int i = startIndex; i < lines.length; i += 1) {
            buffer.writeln(lines[i]);
          }
          break;
        }

        final SingleChoiceBlockData? blockData = _parseSingleChoiceBlock(
          blockLines,
        );
        if (blockData == null) {
          for (int i = startIndex; i <= endIndex; i += 1) {
            buffer.writeln(lines[i]);
          }
        } else {
          nodes.add(_SingleChoiceFlowNode(id: _uuid.v4(), data: blockData));
        }
        index = endIndex + 1;
        continue;
      }
      if (line.trim() == _multiChoiceStartMarker) {
        flushText();
        final int startIndex = index;
        final List<String> blockLines = <String>[];
        int endIndex = index + 1;
        while (endIndex < lines.length &&
            lines[endIndex].trim() != _multiChoiceEndMarker) {
          blockLines.add(lines[endIndex]);
          endIndex += 1;
        }

        if (endIndex >= lines.length) {
          for (int i = startIndex; i < lines.length; i += 1) {
            buffer.writeln(lines[i]);
          }
          break;
        }

        final MultiChoiceBlockData? blockData = _parseMultiChoiceBlock(
          blockLines,
        );
        if (blockData == null) {
          for (int i = startIndex; i <= endIndex; i += 1) {
            buffer.writeln(lines[i]);
          }
        } else {
          nodes.add(_MultiChoiceFlowNode(id: _uuid.v4(), data: blockData));
        }
        index = endIndex + 1;
        continue;
      }

      final Match? match = imageLine.firstMatch(line);
      if (match != null) {
        flushText();
        final String alt = (match.group(1) ?? '').trim();
        final String src = (match.group(2) ?? '').trim();
        nodes.add(_ImageFlowNode(id: _uuid.v4(), alt: alt, src: src));
        index += 1;
        continue;
      }
      buffer.writeln(line);
      index += 1;
    }
    flushText();

    if (nodes.isEmpty || nodes.last is! _TextFlowNode) {
      nodes.add(_createTextNode(EditorRichText.empty));
    }
    return nodes;
  }

  List<_BodyFlowNode> _buildDocumentNodes({
    required String prompt,
    required String answer,
    required bool hasAnswerLine,
  }) {
    final List<_BodyFlowNode> promptNodes = _parseBodyNodes(prompt);
    if (!hasAnswerLine && answer.trim().isEmpty) {
      return promptNodes;
    }

    final List<_BodyFlowNode> answerNodes = _parseBodyNodes(answer);
    final List<_BodyFlowNode> nodes = <_BodyFlowNode>[
      ...promptNodes,
      _AnswerLineFlowNode(id: _uuid.v4()),
      ...answerNodes,
    ];

    if (nodes.isNotEmpty && nodes.last is _AnswerLineFlowNode) {
      nodes.add(_createTextNode(EditorRichText.empty));
    }

    return nodes;
  }

  String _encodeNodes(List<_BodyFlowNode> nodes) {
    final List<String> parts = <String>[];
    for (final _BodyFlowNode node in nodes) {
      if (node is _AnswerLineFlowNode) {
        continue;
      }
      if (node is _TextFlowNode) {
        final String text = EditorDocumentCodec.encodeSingleRichText(
          node.controller.model,
        );
        if (text.trim().isNotEmpty) {
          parts.add(text.trimRight());
        }
        continue;
      }
      if (node is _SingleChoiceFlowNode) {
        parts.add(_encodeSingleChoiceNode(node.data));
        continue;
      }
      if (node is _MultiChoiceFlowNode) {
        parts.add(_encodeMultiChoiceNode(node.data));
        continue;
      }
      final _ImageFlowNode img = node as _ImageFlowNode;
      parts.add('!img[${img.alt.trim()}](${img.src.trim()})');
    }
    return parts.join('\n\n').trim();
  }

  SingleChoiceBlockData? _parseSingleChoiceBlock(List<String> lines) {
    final List<String> questionLines = <String>[];
    final List<String> options = <String>[];
    int correctIndex = 0;
    bool seenCorrectOption = false;
    bool seenOption = false;

    for (final String rawLine in lines) {
      final String line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('Q:') || line.startsWith('Q：')) {
        questionLines.add(line.substring(2).trim());
        continue;
      }
      if (line.startsWith('*')) {
        options.add(line.substring(1).trim());
        correctIndex = options.length - 1;
        seenCorrectOption = true;
        seenOption = true;
        continue;
      }
      if (line.startsWith('-')) {
        options.add(line.substring(1).trim());
        seenOption = true;
        continue;
      }
      if (!seenOption) {
        questionLines.add(line);
        continue;
      }
      return null;
    }

    if (options.isEmpty) {
      return null;
    }

    if (!seenCorrectOption) {
      correctIndex = 0;
    }

    while (options.length < 2) {
      options.add('');
    }

    return SingleChoiceBlockData(
      question: questionLines.join('\n').trim(),
      options: options,
      correctIndex: correctIndex.clamp(0, options.length - 1),
    );
  }

  String _encodeSingleChoiceNode(SingleChoiceBlockData data) {
    final SingleChoiceBlockData normalized = data.normalized();
    final List<String> lines = <String>[
      _singleChoiceStartMarker,
      'Q: ${normalized.question}',
      for (int index = 0; index < normalized.options.length; index += 1)
        '${index == normalized.correctIndex ? '* ' : '- '}${normalized.options[index]}',
      _singleChoiceEndMarker,
    ];
    return lines.join('\n');
  }

  MultiChoiceBlockData? _parseMultiChoiceBlock(List<String> lines) {
    final List<String> questionLines = <String>[];
    final List<String> options = <String>[];
    final List<int> correctIndexes = <int>[];
    bool seenOption = false;

    for (final String rawLine in lines) {
      final String line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('Q:') || line.startsWith('Q：')) {
        questionLines.add(line.substring(2).trim());
        continue;
      }
      if (line.startsWith('*')) {
        options.add(line.substring(1).trim());
        correctIndexes.add(options.length - 1);
        seenOption = true;
        continue;
      }
      if (line.startsWith('-')) {
        options.add(line.substring(1).trim());
        seenOption = true;
        continue;
      }
      if (!seenOption) {
        questionLines.add(line);
        continue;
      }
      return null;
    }

    if (options.isEmpty) {
      return null;
    }
    if (correctIndexes.isEmpty) {
      correctIndexes.add(0);
    }

    while (options.length < 2) {
      options.add('');
    }

    return MultiChoiceBlockData(
      question: questionLines.join('\n').trim(),
      options: options,
      correctIndexes: correctIndexes,
    ).normalized();
  }

  String _encodeMultiChoiceNode(MultiChoiceBlockData data) {
    final MultiChoiceBlockData normalized = data.normalized();
    final Set<int> correctIndexes = normalized.correctIndexes.toSet();
    final List<String> lines = <String>[
      _multiChoiceStartMarker,
      'Q: ${normalized.question}',
      for (int index = 0; index < normalized.options.length; index += 1)
        '${correctIndexes.contains(index) ? '* ' : '- '}${normalized.options[index]}',
      _multiChoiceEndMarker,
    ];
    return lines.join('\n');
  }
}

sealed class _BodyFlowNode {
  const _BodyFlowNode({required this.id});
  final String id;
}

class _TextFlowNode extends _BodyFlowNode {
  const _TextFlowNode({
    required super.id,
    required this.controller,
    required this.focusNode,
  });

  final EditorRichTextController controller;
  final FocusNode focusNode;
}

class _ImageFlowNode extends _BodyFlowNode {
  const _ImageFlowNode({
    required super.id,
    required this.alt,
    required this.src,
  });

  final String alt;
  final String src;
}

class _AnswerLineFlowNode extends _BodyFlowNode {
  const _AnswerLineFlowNode({required super.id});
}

class _SingleChoiceFlowNode extends _BodyFlowNode {
  _SingleChoiceFlowNode({
    required super.id,
    required SingleChoiceBlockData data,
    this.autofocusQuestion = false,
  }) : data = data.normalized();

  SingleChoiceBlockData data;
  final bool autofocusQuestion;
}

class _MultiChoiceFlowNode extends _BodyFlowNode {
  _MultiChoiceFlowNode({
    required super.id,
    required MultiChoiceBlockData data,
    this.autofocusQuestion = false,
  }) : data = data.normalized();

  MultiChoiceBlockData data;
  final bool autofocusQuestion;
}

class _InlineTextNodeEditor extends StatelessWidget {
  const _InlineTextNodeEditor({
    super.key,
    required this.node,
    required this.expandedSurface,
  });

  final _TextFlowNode node;
  final bool expandedSurface;

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = node.controller.text.trim().isEmpty;
    final Widget field = TextField(
      controller: node.controller,
      focusNode: node.focusNode,
      minLines: expandedSurface ? 12 : (isEmpty ? 2 : 1),
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: node.controller.text.trim().isEmpty ? '继续输入内容…' : null,
      ),
    );

    if (!expandedSurface) {
      return field;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 320),
      child: field,
    );
  }
}

class _PrimaryTextCanvas extends StatelessWidget {
  const _PrimaryTextCanvas({required this.node});

  final _TextFlowNode node;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
      child: TextField(
        controller: node.controller,
        focusNode: node.focusNode,
        expands: true,
        minLines: null,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textAlignVertical: TextAlignVertical.top,
        scrollPadding: const EdgeInsets.only(bottom: 180),
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: '在这里直接写卡片正文\n\n需要答案线时，再在当前光标位置点一下上方“答案线”按钮。',
        ),
      ),
    );
  }
}

class _InlineImageNodeCard extends StatelessWidget {
  const _InlineImageNodeCard({
    super.key,
    required this.node,
    required this.onDelete,
  });

  final _ImageFlowNode node;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String src = node.src.trim();
    final bool isHttp = src.startsWith('http://') || src.startsWith('https://');
    final bool isAsset = src.startsWith('assets/');
    final bool isFile = src.startsWith('/') || src.startsWith('file://');

    Widget image;
    if (isHttp) {
      image = Image.network(src, fit: BoxFit.contain);
    } else if (isAsset) {
      image = Image.asset(src, fit: BoxFit.contain);
    } else if (isFile && !kIsWeb) {
      final String filePath = src.startsWith('file://')
          ? src.substring('file://'.length)
          : src;
      image = Image.file(File(filePath), fit: BoxFit.contain);
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Stack(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: image,
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Material(
              color: theme.colorScheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: const Icon(Icons.close),
                tooltip: '删除图片',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RichTextSplit {
  const _RichTextSplit({required this.before, required this.after});

  final EditorRichText before;
  final EditorRichText after;
}

_RichTextSplit _splitRichText(EditorRichText input, int offset) {
  final int cut = offset.clamp(0, input.text.length);
  final String leftText = input.text.substring(0, cut);
  final String rightText = input.text.substring(cut);

  final List<InlineStyleSpan> leftSpans = <InlineStyleSpan>[];
  final List<InlineStyleSpan> rightSpans = <InlineStyleSpan>[];
  for (final InlineStyleSpan span in input.spans) {
    if (span.end <= cut) {
      leftSpans.add(span);
      continue;
    }
    if (span.start >= cut) {
      rightSpans.add(
        InlineStyleSpan(
          start: span.start - cut,
          end: span.end - cut,
          style: span.style,
        ),
      );
      continue;
    }
    // Crosses the cut: split into two.
    leftSpans.add(
      InlineStyleSpan(start: span.start, end: cut, style: span.style),
    );
    rightSpans.add(
      InlineStyleSpan(start: 0, end: span.end - cut, style: span.style),
    );
  }

  return _RichTextSplit(
    before: EditorRichText(text: leftText, spans: leftSpans),
    after: EditorRichText(text: rightText, spans: rightSpans),
  );
}

EditorRichText _mergeRichText(EditorRichText left, EditorRichText right) {
  final String mergedText = '${left.text}${right.text}';
  final List<InlineStyleSpan> spans = <InlineStyleSpan>[
    ...left.spans,
    ...right.spans.map(
      (s) => InlineStyleSpan(
        start: s.start + left.text.length,
        end: s.end + left.text.length,
        style: s.style,
      ),
    ),
  ];
  return EditorRichText(text: mergedText, spans: spans);
}

class _EditorSeed {
  const _EditorSeed({
    required this.title,
    required this.body,
    required this.answer,
    required this.hasAnswerLine,
  });

  final String title;
  final String body;
  final String answer;
  final bool hasAnswerLine;
}

class _CurrentEditorContent {
  const _CurrentEditorContent({required this.title, required this.content});

  final String title;
  final String content;
}

class _DocumentSections {
  const _DocumentSections({
    required this.prompt,
    required this.answer,
    required this.hasAnswerLine,
  });

  final String prompt;
  final String answer;
  final bool hasAnswerLine;
}

class _AIRewriteCardSheet extends ConsumerStatefulWidget {
  const _AIRewriteCardSheet({
    required this.cardId,
    required this.title,
    required this.content,
  });

  final String? cardId;
  final String title;
  final String content;

  @override
  ConsumerState<_AIRewriteCardSheet> createState() =>
      _AIRewriteCardSheetState();
}

class _AIRewriteCardSheetState extends ConsumerState<_AIRewriteCardSheet> {
  final TextEditingController _instructionController = TextEditingController();
  String _rewriteType = 'improve';
  List<AIRewriteCandidate> _candidates = const <AIRewriteCandidate>[];

  static const List<_AIRewriteOption> _options = <_AIRewriteOption>[
    _AIRewriteOption(
      value: 'improve',
      icon: Icons.tune_rounded,
      label: '优化表达',
      description: '更聚焦、更可自评',
    ),
    _AIRewriteOption(
      value: 'simplify_answer',
      icon: Icons.compress_rounded,
      label: '简化答案',
      description: '减少单次记忆负担',
    ),
    _AIRewriteOption(
      value: 'make_cloze',
      icon: Icons.hide_source_outlined,
      label: '改填空',
      description: '遮住关键术语',
    ),
    _AIRewriteOption(
      value: 'make_choice',
      icon: Icons.radio_button_checked_outlined,
      label: '改单选',
      description: '生成选择题草稿',
    ),
    _AIRewriteOption(
      value: 'split',
      icon: Icons.call_split_rounded,
      label: '拆原子卡',
      description: '把大题拆小',
    ),
  ];

  @override
  void dispose() {
    _instructionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    final CardDocumentParts currentParts = CardDocumentCodec.parse(
      widget.content,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 820, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppDesign.radiusXl),
            ),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              top: 10,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'AI 优化卡片',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '先生成候选，再确认应用到当前编辑内容。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: state.syncInProgress
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: '关闭',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ReadonlySnippet(
                    title: '当前卡片',
                    content: currentParts.prompt,
                    secondary: currentParts.answer,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final _AIRewriteOption option in _options)
                        _AIRewriteOptionButton(
                          option: option,
                          selected: option.value == _rewriteType,
                          enabled: !state.syncInProgress,
                          onTap: () => setState(() {
                            _rewriteType = option.value;
                            _candidates = const <AIRewriteCandidate>[];
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _instructionController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '补充要求（可选）',
                      hintText: '例如：更适合考试，或把答案压到一句话。',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: state.syncInProgress ? null : _rewrite,
                    icon: state.syncInProgress
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high_outlined),
                    label: Text(state.syncInProgress ? '优化中…' : '生成优化方案'),
                  ),
                  if (state.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _AIInlineMessage(
                      icon: Icons.info_outline_rounded,
                      text: state.errorMessage!,
                      color: theme.colorScheme.error,
                    ),
                  ],
                  if (_candidates.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 18),
                    Text(
                      '候选版本',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final AIRewriteCandidate candidate
                        in _candidates) ...<Widget>[
                      _RewriteCandidateCard(candidate: candidate),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rewrite() async {
    final List<AIRewriteCandidate> candidates = await ref
        .read(appStoreProvider.notifier)
        .rewriteCardWithAI(
          cardId: widget.cardId,
          title: widget.title,
          content: widget.content,
          rewriteType: _rewriteType,
          instruction: _instructionController.text.trim(),
        );
    if (!mounted) {
      return;
    }
    setState(() => _candidates = candidates);
  }
}

class _AIRewriteOption {
  const _AIRewriteOption({
    required this.value,
    required this.icon,
    required this.label,
    required this.description,
  });

  final String value;
  final IconData icon;
  final String label;
  final String description;
}

class _AIRewriteOptionButton extends StatelessWidget {
  const _AIRewriteOptionButton({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _AIRewriteOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color borderColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.42)
        : theme.colorScheme.outlineVariant;
    final Color foreground = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: option.label,
      hint: option.description,
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppDesign.radiusMd),
          child: Container(
            width: 142,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDesign.radiusMd),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(option.icon, size: 17, color: foreground),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  option.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadonlySnippet extends StatelessWidget {
  const _ReadonlySnippet({
    required this.title,
    required this.content,
    this.secondary = '',
  });

  final String title;
  final String content;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String primary = content.trim().isEmpty ? '暂无题干内容' : content.trim();
    final String answer = secondary.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            primary,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          if (answer.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 8),
            Text(
              answer,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RewriteCandidateCard extends StatelessWidget {
  const _RewriteCandidateCard({required this.candidate});

  final AIRewriteCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CardDocumentParts parts = CardDocumentCodec.parse(candidate.content);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      candidate.title.isEmpty ? '优化候选' : candidate.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (candidate.changeSummary.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        candidate.changeSummary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(candidate),
                icon: const Icon(Icons.check_rounded),
                label: const Text('应用'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ReadonlySnippet(
            title: '候选内容',
            content: parts.prompt,
            secondary: parts.answer,
          ),
          if (candidate.qualityNotes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final String note in candidate.qualityNotes.take(4))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(AppDesign.radiusSm),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.16,
                        ),
                      ),
                    ),
                    child: Text(
                      note,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AIInlineMessage extends StatelessWidget {
  const _AIInlineMessage({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudyToggleCard extends StatelessWidget {
  const _StudyToggleCard({
    required this.value,
    required this.reviewOrder,
    required this.onChanged,
  });

  final bool value;
  final DeckReviewOrder reviewOrder;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('加入背诵', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  value
                      ? '这张卡会进入当前牌组的${reviewOrder.label}复习队列。'
                      : '默认只保存内容，不会自动进入复习列表。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _InlineAnswerLineMarker extends StatelessWidget {
  const _InlineAnswerLineMarker();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(
        thickness: 1.1,
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.95),
      ),
    );
  }
}

class _EditorCommandBar extends StatelessWidget {
  const _EditorCommandBar({
    required this.canSave,
    required this.hasContent,
    required this.saving,
    required this.isCreating,
    required this.onPreview,
    required this.onAIRewrite,
    required this.onSave,
  });

  final bool canSave;
  final bool hasContent;
  final bool saving;
  final bool isCreating;
  final VoidCallback onPreview;
  final VoidCallback onAIRewrite;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 560;
        final Widget status = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              hasContent ? Icons.circle : Icons.radio_button_unchecked_rounded,
              size: hasContent ? 8 : 14,
              color: hasContent
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                hasContent ? '草稿可保存' : '写下题干后可保存',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
        final List<Widget> actions = <Widget>[
          OutlinedButton.icon(
            onPressed: onPreview,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('预览'),
          ),
          OutlinedButton.icon(
            onPressed: saving || !hasContent ? null : onAIRewrite,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('AI 优化'),
          ),
          FilledButton.icon(
            onPressed: canSave ? onSave : null,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(isCreating ? Icons.add_rounded : Icons.check_rounded),
            label: Text(isCreating ? '创建卡片' : '保存修改'),
          ),
        ];

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              status,
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          );
        }

        return Row(
          children: <Widget>[
            Expanded(child: status),
            const SizedBox(width: 12),
            for (int i = 0; i < actions.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 8),
              actions[i],
            ],
          ],
        );
      },
    );
  }
}

class _SimpleToolbar extends StatelessWidget {
  const _SimpleToolbar({
    required this.onToggleCloze,
    required this.onBold,
    required this.onHighlight,
    required this.onUnderline,
    required this.onFontUp,
    required this.onFontDown,
    required this.onInsertImage,
    required this.onInsertAnswerLine,
    required this.onInsertSingleChoice,
    required this.onInsertMultiChoice,
  });

  final VoidCallback onToggleCloze;
  final VoidCallback onBold;
  final VoidCallback onHighlight;
  final VoidCallback onUnderline;
  final VoidCallback onFontUp;
  final VoidCallback onFontDown;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertAnswerLine;
  final VoidCallback onInsertSingleChoice;
  final VoidCallback onInsertMultiChoice;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDesign.radiusLg),
        ),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: <Widget>[
            _ToolbarButton(
              tooltip: '填空/取消填空',
              icon: Icons.hide_source_outlined,
              label: '填空',
              onTap: onToggleCloze,
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              tooltip: '加粗',
              icon: Icons.format_bold_rounded,
              label: '加粗',
              onTap: onBold,
            ),
            _ToolbarButton(
              tooltip: '荧光笔高亮',
              icon: Icons.highlight_alt_rounded,
              label: '高亮',
              onTap: onHighlight,
            ),
            _ToolbarButton(
              tooltip: '下划线',
              icon: Icons.format_underlined_rounded,
              label: '下划线',
              onTap: onUnderline,
            ),
            _ToolbarButton(
              tooltip: '字号缩小',
              icon: Icons.text_decrease_rounded,
              label: '缩小',
              onTap: onFontDown,
            ),
            _ToolbarButton(
              tooltip: '字号放大',
              icon: Icons.text_increase_rounded,
              label: '放大',
              onTap: onFontUp,
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              tooltip: '插入图片',
              icon: Icons.image_outlined,
              label: '图片',
              onTap: onInsertImage,
            ),
            _ToolbarButton(
              tooltip: '在当前光标位置插入答案线',
              icon: Icons.horizontal_rule_rounded,
              label: '答案线',
              onTap: onInsertAnswerLine,
            ),
            _ToolbarButton(
              tooltip: '插入单选题',
              icon: Icons.radio_button_checked_outlined,
              label: '单选',
              onTap: onInsertSingleChoice,
            ),
            _ToolbarButton(
              tooltip: '插入多选题',
              icon: Icons.check_box_outlined,
              label: '多选',
              onTap: onInsertMultiChoice,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

enum _ImageInsertMode { local, remote }

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDesign.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 24),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorPreviewPanel extends StatelessWidget {
  const _EditorPreviewPanel({
    required this.front,
    required this.answer,
    required this.isEmpty,
  });

  final String front;
  final String answer;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('实时预览', style: theme.textTheme.titleSmall),
                const Spacer(),
                Icon(
                  Icons.visibility_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '预览当前卡片效果。答案线下方内容会单独保存，复习时默认隐藏。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppDesign.radiusMd),
                child: ColoredBox(
                  color: theme.colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: isEmpty
                        ? Center(
                            child: Text(
                              '开始输入题目或正文后，这里会实时展示卡片效果。',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            child: DslCardView(
                              front: front,
                              back: answer,
                              revealed: false,
                              onReveal: null,
                              showBackInline: answer.trim().isNotEmpty,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
