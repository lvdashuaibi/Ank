import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'layout/responsive_layout.dart';
import '../core/app_store.dart';
import '../core/import/card_dsl_parser.dart';

const String _sampleDsl = '''
#deck: 英语
#tags: vocabulary, travel

How do you say "机场" in English?

@answer
airport
@end

===

#deck: 计算机网络
#tags: tcp, basics
#type: choice

TCP 属于哪类协议？

@answer
TCP 是面向连接的传输层协议。
@end
''';

class CardDslImportScreen extends ConsumerStatefulWidget {
  const CardDslImportScreen({super.key});

  @override
  ConsumerState<CardDslImportScreen> createState() =>
      _CardDslImportScreenState();
}

class _CardDslImportScreenState extends ConsumerState<CardDslImportScreen> {
  final TextEditingController _controller = TextEditingController();
  int? _lastImported;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    final String source = _controller.text;
    final CardDslParseResult preview = source.trim().isEmpty
        ? const CardDslParseResult(cards: <CardDslCard>[], errors: <String>[])
        : CardDslParser.parseDocument(source);
    final Set<String> deckNames = preview.cards
        .map((CardDslCard card) => card.deckName.trim())
        .where((String name) => name.isNotEmpty)
        .toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('导入 Card DSL')),
      body: AppPageScrollView(
        maxWidth: 1120,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.secondaryContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '批量导入结构化卡片',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '导入方式现在以 `@answer` 为主格式：直接写题面，用 `@answer ... @end` 包答案，多张卡用 `===` 分隔；旧的 `---front--- / ---back---` 仍兼容。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _ImportMetricChip(
                      icon: Icons.copy_all_outlined,
                      label: '识别 ${preview.cards.length} 张',
                    ),
                    _ImportMetricChip(
                      icon: Icons.folder_outlined,
                      label: '牌组 ${deckNames.length}',
                    ),
                    _ImportMetricChip(
                      icon: Icons.error_outline,
                      label: '错误 ${preview.errors.length}',
                    ),
                    _ImportMetricChip(
                      icon: Icons.notes_outlined,
                      label: '字数 ${source.trim().length}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _ImportMessageCard(
                    icon: Icons.tips_and_updates_outlined,
                    title: '当前实际支持',
                    message:
                        '1）推荐直接写题面，再用 `@answer ... @end` 写答案；2）多张卡推荐用 `===` 分隔；3）`#deck`、`#tags`、`#type`、`#difficulty` 可写在卡片头部；4）旧的 `---front--- / ---back---` 与 `@card` 包裹仍兼容。',
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 14),
                  Text('导入操作', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '建议先查看下方预览，再执行导入。导入过程中会自动同步到当前账号。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste_outlined),
                        label: const Text('粘贴内容'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _useSample,
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: const Text('插入示例'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _controller.clear();
                          _lastImported = null;
                        }),
                        icon: const Icon(Icons.clear),
                        label: const Text('清空'),
                      ),
                      FilledButton.icon(
                        onPressed: state.syncInProgress || preview.cards.isEmpty
                            ? null
                            : _import,
                        icon: state.syncInProgress
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.file_download_outlined),
                        label: const Text('开始导入'),
                      ),
                    ],
                  ),
                  if (_lastImported != null) ...<Widget>[
                    const SizedBox(height: 14),
                    _ImportMessageCard(
                      icon: Icons.check_circle_outline,
                      title: '导入完成',
                      message: '本次已成功导入 $_lastImported 张卡片。',
                      color: theme.colorScheme.primary,
                    ),
                  ],
                  if (state.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 14),
                    _ImportMessageCard(
                      icon: Icons.error_outline,
                      title: '导入提示',
                      message: state.errorMessage!,
                      color: theme.colorScheme.error,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('DSL 内容', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '推荐结构：卡片头部元信息 + 题面正文 + `@answer ... @end` 答案区。多张卡用 `===` 分隔；若仍使用 `---front--- / ---back---`，系统会按兼容模式解析。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    maxLines: 18,
                    decoration: const InputDecoration(
                      labelText: '粘贴卡片 DSL 内容',
                      alignLabelWithHint: true,
                      hintText:
                          '#deck: 英语\\n#tags: vocabulary, travel\\nQuestion\\n\\n@answer\\nAnswer\\n@end',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (source.trim().isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text('示例模板', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _copySample,
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('复制示例'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText(
                        _sampleDsl,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...<Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('导入预览', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      preview.cards.isEmpty
                          ? '当前内容还没有识别出可导入的卡片。'
                          : '以下是前 ${preview.cards.length > 3 ? 3 : preview.cards.length} 张卡片的预览。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (preview.cards.isEmpty)
                      _ImportMessageCard(
                        icon: Icons.info_outline,
                        title: '等待识别',
                        message:
                            '请检查 `@answer ... @end`、`===` 分隔符，或旧的 `---front--- / ---back---` 结构与标签写法。',
                        color: theme.colorScheme.primary,
                      )
                    else ...<Widget>[
                      for (final CardDslCard card in preview.cards.take(3))
                        _ImportPreviewTile(card: card),
                      if (preview.cards.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '还有 ${preview.cards.length - 3} 张卡片未展开显示。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (preview.errors.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('解析提示', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 10),
                      for (final String error in preview.errors.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ImportMessageCard(
                            icon: Icons.error_outline,
                            title: '格式提醒',
                            message: error,
                            color: theme.colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _handleChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _pasteFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.trim().isEmpty) {
      return;
    }
    setState(() {
      _controller.text = data.text!;
    });
  }

  void _useSample() {
    setState(() {
      _controller.text = _sampleDsl;
    });
  }

  Future<void> _copySample() async {
    await Clipboard.setData(const ClipboardData(text: _sampleDsl));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('示例模板已复制到剪贴板')));
  }

  Future<void> _import() async {
    final int count = await ref
        .read(appStoreProvider.notifier)
        .importCardDsl(_controller.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _lastImported = count;
    });
  }
}

class _ImportMetricChip extends StatelessWidget {
  const _ImportMetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.54 : 0.82,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.onSurface),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportMessageCard extends StatelessWidget {
  const _ImportMessageCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportPreviewTile extends StatelessWidget {
  const _ImportPreviewTile({required this.card});

  final CardDslCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String title = card.front
        .split('\n')
        .map((String line) => line.trim())
        .firstWhere((String line) => line.isNotEmpty, orElse: () => '未命名卡片');
    final String deckLabel = card.deckName.trim().isEmpty
        ? '默认牌组'
        : card.deckName.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.description_outlined,
            color: theme.colorScheme.primary,
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '牌组：$deckLabel · 标签 ${card.tags.length} 个',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
