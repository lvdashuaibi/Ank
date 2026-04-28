import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../card_dsl/dsl_view.dart';
import '../layout/responsive_layout.dart';
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
      appBar: AppBar(title: Text(widget.cardId == null ? '创建卡片' : '编辑卡片')),
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
            final Widget previewButton = OutlinedButton.icon(
              onPressed: _openPreviewSheet,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('预览'),
            );
            final Widget saveButton = FilledButton.icon(
              onPressed: canSave ? _saveCard : null,
              icon: state.syncInProgress
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(widget.cardId == null ? Icons.add : Icons.check),
              label: Text(widget.cardId == null ? '创建卡片' : '保存修改'),
            );
            final bool stackActions = constraints.maxWidth < 320;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                8,
                horizontalPadding,
                16,
              ),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: stackActions
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            previewButton,
                            const SizedBox(height: 12),
                            saveButton,
                          ],
                        )
                      : Row(
                          children: <Widget>[
                            Expanded(child: previewButton),
                            const SizedBox(width: 12),
                            Expanded(child: saveButton),
                          ],
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
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          _SimpleToolbar(
            onToggleCloze: _toggleClozeAtSelection,
            onBold: () => _applyInlineStyle(InlineStyle.bold),
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
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
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
    final String title = _titleController.text.trim();
    final _DocumentSections sections = _documentSections;
    final String body = sections.prompt;
    final String answer = sections.answer;
    final String content = CardDocumentCodec.compose(
      prompt: title.isEmpty ? body : '$title\n\n$body'.trim(),
      answer: answer,
      includeAnswerLine: sections.hasAnswerLine,
    );
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
          )
        : await store.updateCard(
            cardId: widget.cardId!,
            title: title,
            content: content,
            note: '',
            tags: const <String>['dsl'],
          );

    if (mounted && success) {
      Navigator.of(context).pop();
    }
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

    final List<InlineStyleSpan> spans = List<InlineStyleSpan>.from(
      node.controller.model.spans,
    )..add(InlineStyleSpan(start: start, end: end, style: style));
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

class _SimpleToolbar extends StatelessWidget {
  const _SimpleToolbar({
    required this.onToggleCloze,
    required this.onBold,
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
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _ToolbarButton(
            tooltip: '填空/取消填空',
            icon: Icons.hide_source_outlined,
            label: '填空',
            onTap: onToggleCloze,
          ),
          _ToolbarButton(
            tooltip: '加粗',
            icon: Icons.format_bold_rounded,
            label: '加粗',
            onTap: onBold,
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
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 28),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
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
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('实时预览', style: theme.textTheme.titleMedium),
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
                borderRadius: BorderRadius.circular(18),
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerLowest,
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
