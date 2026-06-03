import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'layout/responsive_layout.dart';
import 'card_dsl/dsl_plaintext.dart';
import 'card_dsl/dsl_view.dart';
import 'theme/app_design.dart';
import '../core/app_store.dart';
import '../core/card_document.dart';
import '../core/plain_choice_card.dart';

class AppShellScreen extends ConsumerWidget {
  const AppShellScreen({
    super.key,
    required this.navigationShell,
    required this.location,
  });

  final StatefulNavigationShell navigationShell;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppState state = ref.watch(appStoreProvider);

    if (state.isBootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!state.isAuthenticated) {
      return const AuthScreen();
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showRail = AppResponsive.useNavigationRail(
          constraints.maxWidth,
        );
        if (!showRail) {
          return Scaffold(
            body: navigationShell,
            bottomNavigationBar: _showsPrimaryTabBar(location)
                ? _AppBottomNav(
                    currentIndex: navigationShell.currentIndex,
                    onDestinationSelected: (int index) {
                      navigationShell.goBranch(
                        index,
                        initialLocation: index == navigationShell.currentIndex,
                      );
                    },
                  )
                : null,
          );
        }

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
            child: Row(
              children: <Widget>[
                _AppNavigationRail(
                  extended: AppResponsive.extendNavigationRail(
                    constraints.maxWidth,
                  ),
                  currentIndex: navigationShell.currentIndex,
                  onDestinationSelected: (int index) {
                    navigationShell.goBranch(
                      index,
                      initialLocation: index == navigationShell.currentIndex,
                    );
                  },
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(child: navigationShell),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  bool _isRegister = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(color: scheme.surface),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool isWide = constraints.maxWidth >= 760;
                    final Widget hero = Padding(
                      padding: EdgeInsets.only(right: isWide ? 28 : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _SectionBadge(
                            icon: Icons.auto_stories_outlined,
                            label: 'Ank Flashcard',
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '让复习、同步和 AI 生成在一个客户端里自然协作。',
                            style:
                                (isWide
                                        ? theme.textTheme.displaySmall
                                        : theme.textTheme.headlineMedium)
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      height: 1.12,
                                    ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '支持正式登录、PostgreSQL 持久化、服务端 FSRS 排期与 AI 草稿生成。你可以从 Web、macOS 和 iPhone 模拟器无缝体验同一套数据。',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: const <Widget>[
                              _MiniFeatureChip(icon: Icons.sync, label: '自动同步'),
                              _MiniFeatureChip(
                                icon: Icons.psychology_alt_outlined,
                                label: 'AI 草稿',
                              ),
                              _MiniFeatureChip(
                                icon: Icons.cloud_done_outlined,
                                label: '服务端排期',
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: const <Widget>[
                              _StatBadge(label: '跨端', value: 'Web+iOS'),
                              _StatBadge(label: '导入', value: 'DSL'),
                              _StatBadge(label: '排期', value: '服务端'),
                            ],
                          ),
                        ],
                      ),
                    );

                    final Widget formCard = Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: _AuthTab(
                                      label: '登录',
                                      selected: !_isRegister,
                                      onTap: () =>
                                          setState(() => _isRegister = false),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _AuthTab(
                                      label: '注册',
                                      selected: _isRegister,
                                      onTap: () =>
                                          setState(() => _isRegister = true),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(
                                _isRegister ? '创建账号' : '欢迎回来',
                                style: theme.textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isRegister
                                    ? '先创建你的专属账号，再开始管理牌组和复习计划。'
                                    : '登录后即可继续查看牌组、同步状态和今日复习任务。',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (state.errorMessage != null) ...<Widget>[
                                _InlineMessage(
                                  icon: Icons.error_outline,
                                  text: state.errorMessage!,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (_isRegister) ...<Widget>[
                                TextFormField(
                                  controller: _displayNameController,
                                  decoration: const InputDecoration(
                                    labelText: '显示名',
                                  ),
                                  validator: (String? value) {
                                    if (_isRegister &&
                                        (value == null ||
                                            value.trim().isEmpty)) {
                                      return '请输入显示名';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextFormField(
                                controller: _emailController,
                                decoration: const InputDecoration(
                                  labelText: '邮箱',
                                ),
                                validator: (String? value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return '请输入邮箱';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordController,
                                decoration: const InputDecoration(
                                  labelText: '密码',
                                ),
                                obscureText: true,
                                validator: (String? value) {
                                  if (value == null ||
                                      value.trim().length < 6) {
                                    return '密码至少 6 位';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _submit,
                                child: Text(_isRegister ? '注册并进入' : '登录'),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  '演示账号：demo_ios@ank.local / Demo123456',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Expanded(child: hero),
                          Expanded(child: formCard),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        hero,
                        const SizedBox(height: 24),
                        formCard,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_isRegister) {
      await ref
          .read(appStoreProvider.notifier)
          .register(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
            displayName: _displayNameController.text.trim(),
          );
      return;
    }
    await ref
        .read(appStoreProvider.notifier)
        .login(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
  }
}

class DeckListScreen extends ConsumerWidget {
  const DeckListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    final int totalCards = state.cards.length;
    final int dueCards = state.dueCards().length;
    Future<void> openCreateDeck({String? initialFolderId}) async {
      final String? deckId = await showAdaptiveSheet<String>(
        context: context,
        maxWidth: 720,
        isScrollControlled: true,
        builder: (BuildContext context) {
          return _CreateDeckSheet(initialFolderId: initialFolderId);
        },
      );
      if (!context.mounted || deckId == null || deckId.isEmpty) {
        return;
      }
      context.go('/deck/$deckId');
    }

    Future<void> openCreateFolder() async {
      await showAdaptiveSheet<String>(
        context: context,
        maxWidth: 520,
        isScrollControlled: true,
        builder: (BuildContext context) {
          return const _CreateFolderSheet();
        },
      );
    }

    Future<void> openFolderSettings(FolderModel folder) async {
      await showAdaptiveSheet<_FolderSheetResult>(
        context: context,
        maxWidth: 520,
        isScrollControlled: true,
        builder: (BuildContext context) {
          return _EditFolderSheet(folder: folder);
        },
      );
    }

    final List<FolderModel> folders = List<FolderModel>.from(state.folders)
      ..sort((FolderModel a, FolderModel b) => a.name.compareTo(b.name));
    final List<DeckModel> ungroupedDecks = state.ungroupedDecks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ank 学习空间'),
        actions: <Widget>[
          IconButton(
            onPressed: openCreateFolder,
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: '新建文件夹',
          ),
          IconButton(
            onPressed: () => openCreateDeck(),
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '新建牌组',
          ),
          IconButton(
            onPressed: () => context.go('/review'),
            icon: const Icon(Icons.play_circle_outline),
            tooltip: '开始复习',
          ),
        ],
      ),
      body: AppPageScrollView(
        maxWidth: 1120,
        children: <Widget>[
          if (state.errorMessage != null)
            _InfoPanel(
              icon: Icons.warning_amber_outlined,
              title: '当前存在提示',
              subtitle: state.errorMessage!,
              tint: theme.colorScheme.error,
            ),
          _HomeOverviewStrip(
            deckCount: state.decks.length,
            cardCount: totalCards,
            dueCount: dueCards,
            onCreateDeck: openCreateDeck,
            onStartReview: dueCards == 0 ? null : () => context.go('/review'),
            onImportDsl: () => context.go('/import/dsl'),
          ),
          if (state.syncInProgress)
            const _InfoPanel(
              icon: Icons.sync,
              title: '正在同步数据',
              subtitle: '客户端会自动推送内容编辑队列并拉取最新卡片快照。',
            ),
          if (state.pendingOperationCount > 0)
            _InfoPanel(
              icon: Icons.sync_problem_outlined,
              title: '待同步操作 ${state.pendingOperationCount} 条',
              subtitle: '网络恢复后会自动补传，也可以在设置页手动触发同步。',
            ),
          const SizedBox(height: 12),
          const _SectionHeader(
            title: '你的学习空间',
            subtitle: '先用文件夹归档，再在文件夹里继续拆分牌组和复习节奏。',
          ),
          if (state.decks.isEmpty && folders.isEmpty)
            _EmptyStateCard(
              icon: Icons.layers_clear_outlined,
              title: '还没有可用牌组',
              subtitle: '先创建文件夹或牌组开始整理内容；如果你已有结构化文本，也可以直接导入 DSL。',
              primaryActionLabel: '创建文件夹',
              onPrimaryAction: openCreateFolder,
              secondaryActionLabel: '创建牌组',
              onSecondaryAction: () => openCreateDeck(),
              tertiaryActionLabel: '导入 DSL',
              onTertiaryAction: () => context.go('/import/dsl'),
            )
          else ...<Widget>[
            for (final FolderModel folder in folders)
              _FolderDeckSection(
                folder: folder,
                decks: state.decksInFolder(folder.id),
                dueCount: state
                    .decksInFolder(folder.id)
                    .fold<int>(
                      0,
                      (int total, DeckModel deck) =>
                          total + state.dueCountForDeck(deck.id),
                    ),
                onEdit: () => openFolderSettings(folder),
                onCreateDeck: () => openCreateDeck(initialFolderId: folder.id),
              ),
            if (ungroupedDecks.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const _SectionHeader(title: '未分类牌组', subtitle: '这些牌组暂时不属于任何文件夹。'),
              for (final DeckModel deck in ungroupedDecks)
                _DeckSummaryCard(
                  deck: deck,
                  cardCount: state.cardCountForDeck(deck.id),
                  dueCount: state.dueCountForDeck(deck.id),
                  onTap: () => context.go('/deck/${deck.id}'),
                ),
            ],
            if (folders.isEmpty && ungroupedDecks.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
            ],
            if (folders.isNotEmpty && ungroupedDecks.isEmpty)
              _InfoPanel(
                icon: Icons.folder_copy_outlined,
                title: '所有牌组都已归档到文件夹',
                subtitle: '你也可以继续创建未分类牌组，之后再挪进文件夹。',
              ),
          ],
        ],
      ),
    );
  }
}

class DeckDetailScreen extends ConsumerStatefulWidget {
  const DeckDetailScreen({super.key, required this.deckId});

  final String deckId;

  @override
  ConsumerState<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends ConsumerState<DeckDetailScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedCardIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    final DeckModel? resolvedDeck = state.decks.cast<DeckModel?>().firstWhere(
      (DeckModel? item) => item?.id == widget.deckId,
      orElse: () => null,
    );
    if (resolvedDeck == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('牌组')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.folder_off_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text('这个牌组可能已被删除', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    '返回首页后可以继续查看其他牌组，或重新创建一个新的学习主题。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => context.go('/'),
                    child: const Text('返回首页'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final DeckModel deck = resolvedDeck;
    final bool selectionMode = _selectedCardIds.isNotEmpty;
    final String keyword = _searchController.text.trim().toLowerCase();
    final int studyEnabledCount = state
        .cardsByDeck(widget.deckId)
        .where((CardModel card) => card.studyEnabled)
        .length;
    final List<CardModel> cards = state.cardsByDeck(widget.deckId).where((
      CardModel card,
    ) {
      if (keyword.isEmpty) {
        return true;
      }
      return CardDocumentCodec.promptPreview(
            card.content,
          ).toLowerCase().contains(keyword) ||
          card.answer.toLowerCase().contains(keyword) ||
          card.tags.any((String tag) => tag.toLowerCase().contains(keyword));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selectionMode ? '已选 ${_selectedCardIds.length} 张' : deck.name,
        ),
        actions: <Widget>[
          if (selectionMode)
            TextButton(
              onPressed: () => setState(() => _selectedCardIds.clear()),
              child: const Text('取消'),
            ),
          if (selectionMode)
            IconButton(
              onPressed: _confirmDeleteSelectedCards,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除选中卡片',
            ),
          if (!selectionMode)
            IconButton(
              onPressed: () => _openDeckSettings(deck),
              icon: const Icon(Icons.tune_outlined),
              tooltip: '牌组设置',
            ),
          if (!selectionMode)
            IconButton(
              onPressed: () => _openAIGenerateSheet(deck),
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: 'AI 生成卡片',
            ),
          if (!selectionMode)
            IconButton(
              onPressed: () => context.go('/review?deck_id=${widget.deckId}'),
              icon: const Icon(Icons.play_arrow_outlined),
              tooltip: '复习本牌组',
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/deck/${widget.deckId}/add-card'),
        icon: const Icon(Icons.add),
        label: const Text('新增卡片'),
      ),
      body: AppPageScrollView(
        maxWidth: 1040,
        children: <Widget>[
          _DeckPageHeader(
            deck: deck,
            cardCount: state.cardCountForDeck(widget.deckId),
            dueCount: state.dueCountForDeck(widget.deckId),
            matchedCount: cards.length,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索正面、反面或标签',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _MetaChip(label: '新卡/天 ${deck.newCardsPerDay}'),
              _MetaChip(label: '最大复习 ${deck.maxReviewsPerDay}'),
              _MetaChip(
                label: '已加入背诵 $studyEnabledCount',
                color: theme.colorScheme.secondaryContainer,
              ),
              _MetaChip(
                label: selectionMode
                    ? '已选择 ${_selectedCardIds.length} 张'
                    : '长按进入批量选择',
                color: selectionMode
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (cards.isEmpty)
            _EmptyStateCard(
              icon: keyword.isEmpty
                  ? Icons.note_add_outlined
                  : Icons.search_off_outlined,
              title: keyword.isEmpty ? '这个牌组还没有卡片' : '没有找到匹配卡片',
              subtitle: keyword.isEmpty
                  ? '先创建第一张卡片，或者从 DSL 批量导入内容。'
                  : '试试更换关键词，或清空搜索后查看全部卡片。',
              primaryActionLabel: keyword.isEmpty ? '新增卡片' : '清空搜索',
              onPrimaryAction: () {
                if (keyword.isEmpty) {
                  context.go('/deck/${widget.deckId}/add-card');
                  return;
                }
                setState(() => _searchController.clear());
              },
              secondaryActionLabel: keyword.isEmpty ? '导入 DSL' : '新增卡片',
              onSecondaryAction: () {
                if (keyword.isEmpty) {
                  context.go('/import/dsl');
                  return;
                }
                context.go('/deck/${widget.deckId}/add-card');
              },
              tertiaryActionLabel: keyword.isEmpty ? 'AI 生成' : null,
              onTertiaryAction: keyword.isEmpty
                  ? () => _openAIGenerateSheet(deck)
                  : null,
            )
          else
            Card(
              child: Column(
                children: <Widget>[
                  _DeckDatabaseHeader(
                    countLabel: '${cards.length} 张卡片',
                    selectionLabel: selectionMode
                        ? '已选择 ${_selectedCardIds.length} 张'
                        : '长按多选',
                  ),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  for (
                    int index = 0;
                    index < cards.length;
                    index += 1
                  ) ...<Widget>[
                    _DeckCardListItem(
                      card: cards[index],
                      selectionMode: selectionMode,
                      selected: _selectedCardIds.contains(cards[index].id),
                      onLongPress: () => _toggleSelection(cards[index].id),
                      onTap: () {
                        if (selectionMode) {
                          _toggleSelection(cards[index].id);
                        } else {
                          context.go(
                            '/deck/${widget.deckId}/card/${cards[index].id}/edit',
                          );
                        }
                      },
                      onToggleStudyEnabled: selectionMode
                          ? null
                          : () => _toggleCardStudyEnabled(cards[index]),
                    ),
                    if (index != cards.length - 1)
                      Divider(
                        height: 1,
                        indent: 52,
                        color: theme.colorScheme.outlineVariant,
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _toggleSelection(String cardId) {
    setState(() {
      if (_selectedCardIds.contains(cardId)) {
        _selectedCardIds.remove(cardId);
      } else {
        _selectedCardIds.add(cardId);
      }
    });
  }

  Future<void> _deleteSelectedCards() async {
    final List<String> ids = _selectedCardIds.toList();
    await ref.read(appStoreProvider.notifier).deleteCards(ids);
    if (mounted) {
      setState(() {
        _selectedCardIds.clear();
      });
    }
  }

  Future<void> _toggleCardStudyEnabled(CardModel card) async {
    final bool success = await ref
        .read(appStoreProvider.notifier)
        .updateCardStudyEnabled(
          cardId: card.id,
          studyEnabled: !card.studyEnabled,
        );
    if (!mounted || success) {
      return;
    }
    final String message =
        ref.read(appStoreProvider).errorMessage ?? '更新背诵状态失败';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDeleteSelectedCards() async {
    if (_selectedCardIds.isEmpty) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除已选卡片？'),
          content: Text('将删除 ${_selectedCardIds.length} 张卡片，此操作不可撤销。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认删除'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _deleteSelectedCards();
    }
  }

  Future<void> _openDeckSettings(DeckModel deck) async {
    final _DeckSheetResult? result = await showAdaptiveSheet<_DeckSheetResult>(
      context: context,
      maxWidth: 720,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return _EditDeckSheet(deck: deck);
      },
    );
    if (!mounted || result == null) {
      return;
    }
    if (result == _DeckSheetResult.deleted) {
      context.go('/');
    }
  }

  Future<void> _openAIGenerateSheet(DeckModel deck) async {
    ref.read(appStoreProvider.notifier).clearGeneratedCards();
    await showAdaptiveSheet<bool>(
      context: context,
      maxWidth: 760,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return _AIGenerateCardsSheet(deck: deck);
      },
    );
  }
}

enum _DeckSheetResult { saved, deleted }

enum _FolderSheetResult { saved, deleted }

const String _noFolderSelection = '__none__';

class _EditDeckSheet extends ConsumerStatefulWidget {
  const _EditDeckSheet({required this.deck});

  final DeckModel deck;

  @override
  ConsumerState<_EditDeckSheet> createState() => _EditDeckSheetState();
}

class _EditDeckSheetState extends ConsumerState<_EditDeckSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _newCardsController;
  late final TextEditingController _maxReviewsController;
  late String _selectedIcon;
  late String _selectedColor;
  late String? _selectedFolderId;
  late DeckReviewOrder _selectedReviewOrder;
  bool _submitting = false;
  bool _deleting = false;
  String? _inlineError;

  bool get _busy => _submitting || _deleting;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.deck.name);
    _descriptionController = TextEditingController(
      text: widget.deck.description,
    );
    _newCardsController = TextEditingController(
      text: widget.deck.newCardsPerDay.toString(),
    );
    _maxReviewsController = TextEditingController(
      text: widget.deck.maxReviewsPerDay.toString(),
    );
    _selectedIcon = _normalizeDeckIconChoice(widget.deck.icon);
    _selectedColor = _normalizeDeckColorChoice(widget.deck.colorHex);
    _selectedFolderId = widget.deck.folderId;
    _selectedReviewOrder = widget.deck.reviewOrder;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _newCardsController.dispose();
    _maxReviewsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    final List<FolderModel> folders = List<FolderModel>.from(state.folders)
      ..sort((FolderModel a, FolderModel b) => a.name.compareTo(b.name));
    final Color deckColor = _parseDeckColor(_selectedColor, theme);
    final String previewName = _nameController.text.trim().isEmpty
        ? '牌组名称'
        : _nameController.text.trim();
    final String previewDescription = _descriptionController.text.trim().isEmpty
        ? '整理主题、图标和每日节奏，让这个牌组更清晰。'
        : _descriptionController.text.trim();
    final String previewNewCards = _newCardsController.text.trim().isEmpty
        ? '20'
        : _newCardsController.text.trim();
    final String previewMaxReviews = _maxReviewsController.text.trim().isEmpty
        ? '200'
        : _maxReviewsController.text.trim();
    final String previewFolder = _selectedFolderId == null
        ? '未分类'
        : folders
                  .cast<FolderModel?>()
                  .firstWhere(
                    (FolderModel? item) => item?.id == _selectedFolderId,
                    orElse: () => null,
                  )
                  ?.name ??
              '未分类';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('牌组设置', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    '在这里调整名称、图标和每日节奏；删除牌组也放在同一个入口里。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: deckColor.withValues(
                        alpha: theme.brightness == Brightness.dark
                            ? 0.22
                            : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: deckColor.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: deckColor.withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.28
                                  : 0.16,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            _deckIconFor(_selectedIcon),
                            color: deckColor,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                previewName,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                previewDescription,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  _MetaChip(label: '文件夹 $previewFolder'),
                                  _MetaChip(
                                    label: '背诵 ${_selectedReviewOrder.label}',
                                  ),
                                  _MetaChip(label: '新卡/天 $previewNewCards'),
                                  _MetaChip(label: '最大复习 $previewMaxReviews'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TextFormField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '牌组名称',
                            hintText: '例如：英语核心词汇 / 操作系统 / 面试题',
                          ),
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入牌组名称';
                            }
                            return null;
                          },
                          onChanged: (_) => setState(() => _inlineError = null),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descriptionController,
                          minLines: 2,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: '说明（可选）',
                            hintText: '简单描述这个牌组的主题或使用场景。',
                          ),
                          onChanged: (_) => setState(() => _inlineError = null),
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder:
                              (
                                BuildContext context,
                                BoxConstraints constraints,
                              ) {
                                final bool compact = constraints.maxWidth < 520;
                                final Widget newCardsField = TextFormField(
                                  controller: _newCardsController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: '新卡/天',
                                    hintText: '20',
                                  ),
                                  validator: (String? value) {
                                    final int? parsed = int.tryParse(
                                      (value ?? '').trim(),
                                    );
                                    if (parsed == null || parsed <= 0) {
                                      return '请输入大于 0 的整数';
                                    }
                                    return null;
                                  },
                                  onChanged: (_) =>
                                      setState(() => _inlineError = null),
                                );
                                final Widget maxReviewsField = TextFormField(
                                  controller: _maxReviewsController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: '最大复习/天',
                                    hintText: '200',
                                  ),
                                  validator: (String? value) {
                                    final int? parsed = int.tryParse(
                                      (value ?? '').trim(),
                                    );
                                    if (parsed == null || parsed <= 0) {
                                      return '请输入大于 0 的整数';
                                    }
                                    return null;
                                  },
                                  onChanged: (_) =>
                                      setState(() => _inlineError = null),
                                );

                                if (compact) {
                                  return Column(
                                    children: <Widget>[
                                      newCardsField,
                                      const SizedBox(height: 12),
                                      maxReviewsField,
                                    ],
                                  );
                                }

                                return Row(
                                  children: <Widget>[
                                    Expanded(child: newCardsField),
                                    const SizedBox(width: 12),
                                    Expanded(child: maxReviewsField),
                                  ],
                                );
                              },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedFolderId ?? _noFolderSelection,
                          decoration: const InputDecoration(labelText: '所属文件夹'),
                          items: <DropdownMenuItem<String>>[
                            const DropdownMenuItem<String>(
                              value: _noFolderSelection,
                              child: Text('未分类'),
                            ),
                            ...folders.map(
                              (FolderModel folder) => DropdownMenuItem<String>(
                                value: folder.id,
                                child: Text(folder.name),
                              ),
                            ),
                          ],
                          onChanged: (String? value) {
                            setState(() {
                              _selectedFolderId =
                                  value == null || value == _noFolderSelection
                                  ? null
                                  : value;
                              _inlineError = null;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        Text('背诵顺序', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: DeckReviewOrder.values.map((
                            DeckReviewOrder order,
                          ) {
                            return ChoiceChip(
                              label: Text(order.label),
                              selected: _selectedReviewOrder == order,
                              onSelected: (_) {
                                setState(() {
                                  _selectedReviewOrder = order;
                                  _inlineError = null;
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Text('图标', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _deckIconChoices.map((
                            _DeckIconChoice item,
                          ) {
                            final bool selected = _selectedIcon == item.raw;
                            return _DeckIconChoiceChip(
                              label: item.label,
                              icon: _deckIconFor(item.raw),
                              selected: selected,
                              onTap: () {
                                setState(() {
                                  _selectedIcon = item.raw;
                                  _inlineError = null;
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Text('颜色', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _deckColorChoices.map((String colorHex) {
                            return _DeckColorChoice(
                              color: _parseDeckColor(colorHex, theme),
                              selected: _selectedColor == colorHex,
                              onTap: () {
                                setState(() {
                                  _selectedColor = colorHex;
                                  _inlineError = null;
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '修改后会立即同步到服务端；如果想彻底清掉这个主题，也可以直接在下方删除。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (_inlineError != null) ...<Widget>[
                          const SizedBox(height: 14),
                          _InlineMessage(
                            icon: Icons.error_outline,
                            text: _inlineError!,
                            color: theme.colorScheme.error,
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('取消'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _busy ? null : _submit,
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_circle_outline),
                                label: Text(_submitting ? '保存中…' : '保存设置'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Divider(color: theme.colorScheme.outlineVariant),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _confirmDelete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.32,
                              ),
                            ),
                          ),
                          icon: _deleting
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      theme.colorScheme.error,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                          label: Text(_deleting ? '删除中…' : '删除牌组'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '删除后会同时移除这个牌组里的所有卡片与相关复习记录，且不能撤销。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final int? newCardsPerDay = int.tryParse(_newCardsController.text.trim());
    final int? maxReviewsPerDay = int.tryParse(
      _maxReviewsController.text.trim(),
    );
    if (newCardsPerDay == null ||
        newCardsPerDay <= 0 ||
        maxReviewsPerDay == null ||
        maxReviewsPerDay <= 0) {
      setState(() => _inlineError = '请填写有效的每日节奏');
      return;
    }

    setState(() {
      _submitting = true;
      _inlineError = null;
    });
    final DeckModel? updated = await ref
        .read(appStoreProvider.notifier)
        .updateDeck(
          deckId: widget.deck.id,
          name: _nameController.text,
          description: _descriptionController.text,
          icon: _selectedIcon,
          colorHex: _selectedColor,
          folderId: _selectedFolderId,
          reviewOrder: _selectedReviewOrder,
          newCardsPerDay: newCardsPerDay,
          maxReviewsPerDay: maxReviewsPerDay,
        );
    if (!mounted) {
      return;
    }
    if (updated == null) {
      setState(() {
        _submitting = false;
        _inlineError =
            ref.read(appStoreProvider).errorMessage ?? '保存牌组设置失败，请稍后重试';
      });
      return;
    }
    Navigator.of(context).pop(_DeckSheetResult.saved);
  }

  Future<void> _confirmDelete() async {
    final String deckName = _nameController.text.trim().isEmpty
        ? widget.deck.name
        : _nameController.text.trim();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除这个牌组？'),
          content: Text('「$deckName」里的卡片和对应复习记录都会一起删除，此操作不可撤销。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('确认删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _deleting = true;
      _inlineError = null;
    });
    final bool deleted = await ref
        .read(appStoreProvider.notifier)
        .deleteDeck(widget.deck.id);
    if (!mounted) {
      return;
    }
    if (!deleted) {
      setState(() {
        _deleting = false;
        _inlineError =
            ref.read(appStoreProvider).errorMessage ?? '删除牌组失败，请稍后重试';
      });
      return;
    }
    Navigator.of(context).pop(_DeckSheetResult.deleted);
  }
}

class _CreateFolderSheet extends ConsumerStatefulWidget {
  const _CreateFolderSheet();

  @override
  ConsumerState<_CreateFolderSheet> createState() => _CreateFolderSheetState();
}

class _CreateFolderSheetState extends ConsumerState<_CreateFolderSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  bool _submitting = false;
  String? _inlineError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('创建文件夹', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    '文件夹在牌组之上，用来归档同一主题下的多个牌组。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '文件夹名称',
                        hintText: '例如：英语 / 面试 / 专业课',
                      ),
                      validator: (String? value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入文件夹名称';
                        }
                        return null;
                      },
                      onChanged: (_) => setState(() => _inlineError = null),
                    ),
                  ),
                  if (_inlineError != null) ...<Widget>[
                    const SizedBox(height: 14),
                    _InlineMessage(
                      icon: Icons.error_outline,
                      text: _inlineError!,
                      color: theme.colorScheme.error,
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.create_new_folder_outlined),
                          label: Text(_submitting ? '创建中…' : '创建文件夹'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _inlineError = null;
    });
    final FolderModel? created = await ref
        .read(appStoreProvider.notifier)
        .createFolder(name: _nameController.text);
    if (!mounted) {
      return;
    }
    if (created == null) {
      setState(() {
        _submitting = false;
        _inlineError =
            ref.read(appStoreProvider).errorMessage ?? '创建文件夹失败，请稍后重试';
      });
      return;
    }
    Navigator.of(context).pop(created.id);
  }
}

class _EditFolderSheet extends ConsumerStatefulWidget {
  const _EditFolderSheet({required this.folder});

  final FolderModel folder;

  @override
  ConsumerState<_EditFolderSheet> createState() => _EditFolderSheetState();
}

class _EditFolderSheetState extends ConsumerState<_EditFolderSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _submitting = false;
  bool _deleting = false;
  String? _inlineError;

  bool get _busy => _submitting || _deleting;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.folder.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('文件夹设置', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    '删除文件夹不会删除里面的牌组，只会把它们移到未分类。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '文件夹名称',
                        hintText: '例如：英语 / 面试 / 专业课',
                      ),
                      validator: (String? value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入文件夹名称';
                        }
                        return null;
                      },
                      onChanged: (_) => setState(() => _inlineError = null),
                    ),
                  ),
                  if (_inlineError != null) ...<Widget>[
                    const SizedBox(height: 14),
                    _InlineMessage(
                      icon: Icons.error_outline,
                      text: _inlineError!,
                      color: theme.colorScheme.error,
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(_submitting ? '保存中…' : '保存设置'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _confirmDelete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(
                        color: theme.colorScheme.error.withValues(alpha: 0.32),
                      ),
                    ),
                    icon: _deleting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.colorScheme.error,
                              ),
                            ),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(_deleting ? '删除中…' : '删除文件夹'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _inlineError = null;
    });
    final FolderModel? updated = await ref
        .read(appStoreProvider.notifier)
        .updateFolder(folderId: widget.folder.id, name: _nameController.text);
    if (!mounted) {
      return;
    }
    if (updated == null) {
      setState(() {
        _submitting = false;
        _inlineError =
            ref.read(appStoreProvider).errorMessage ?? '保存文件夹失败，请稍后重试';
      });
      return;
    }
    Navigator.of(context).pop(_FolderSheetResult.saved);
  }

  Future<void> _confirmDelete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除这个文件夹？'),
          content: Text('删除后，里面的牌组会移到未分类，但不会被删除。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('确认删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _deleting = true;
      _inlineError = null;
    });
    final bool deleted = await ref
        .read(appStoreProvider.notifier)
        .deleteFolder(widget.folder.id);
    if (!mounted) {
      return;
    }
    if (!deleted) {
      setState(() {
        _deleting = false;
        _inlineError =
            ref.read(appStoreProvider).errorMessage ?? '删除文件夹失败，请稍后重试';
      });
      return;
    }
    Navigator.of(context).pop(_FolderSheetResult.deleted);
  }
}

class _CreateDeckSheet extends ConsumerStatefulWidget {
  const _CreateDeckSheet({this.initialFolderId});

  final String? initialFolderId;

  @override
  ConsumerState<_CreateDeckSheet> createState() => _CreateDeckSheetState();
}

class _CreateDeckSheetState extends ConsumerState<_CreateDeckSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedIcon = _deckIconChoices.first.raw;
  String _selectedColor = _deckColorChoices.first;
  String? _selectedFolderId;
  DeckReviewOrder _selectedReviewOrder = DeckReviewOrder.sequential;
  bool _submitting = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _selectedFolderId = widget.initialFolderId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    final List<FolderModel> folders = List<FolderModel>.from(state.folders)
      ..sort((FolderModel a, FolderModel b) => a.name.compareTo(b.name));
    final Color deckColor = _parseDeckColor(_selectedColor, theme);
    final String previewName = _nameController.text.trim().isEmpty
        ? '新牌组'
        : _nameController.text.trim();
    final String previewDescription = _descriptionController.text.trim().isEmpty
        ? '把同一主题的卡片整理到这里，后续可以继续补卡和复习。'
        : _descriptionController.text.trim();
    final String previewFolder = _selectedFolderId == null
        ? '未分类'
        : folders
                  .cast<FolderModel?>()
                  .firstWhere(
                    (FolderModel? item) => item?.id == _selectedFolderId,
                    orElse: () => null,
                  )
                  ?.name ??
              '未分类';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('创建牌组', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    '先建立一个主题容器，再往里面持续添加卡片。默认复习节奏会自动套用。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: deckColor.withValues(
                        alpha: theme.brightness == Brightness.dark
                            ? 0.22
                            : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: deckColor.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: deckColor.withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.28
                                  : 0.16,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            _deckIconFor(_selectedIcon),
                            color: deckColor,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                previewName,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                previewDescription,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  _MetaChip(label: '文件夹 $previewFolder'),
                                  _MetaChip(
                                    label: '背诵 ${_selectedReviewOrder.label}',
                                  ),
                                  const _MetaChip(label: '新卡/天 20'),
                                  const _MetaChip(label: '最大复习 200'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TextFormField(
                          controller: _nameController,
                          autofocus: true,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '牌组名称',
                            hintText: '例如：英语核心词汇 / 操作系统 / 面试题',
                          ),
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入牌组名称';
                            }
                            return null;
                          },
                          onChanged: (_) => setState(() => _inlineError = null),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descriptionController,
                          minLines: 2,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: '说明（可选）',
                            hintText: '简单描述这个牌组的主题或使用场景。',
                          ),
                          onChanged: (_) => setState(() => _inlineError = null),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedFolderId ?? _noFolderSelection,
                          decoration: const InputDecoration(labelText: '所属文件夹'),
                          items: <DropdownMenuItem<String>>[
                            const DropdownMenuItem<String>(
                              value: _noFolderSelection,
                              child: Text('未分类'),
                            ),
                            ...folders.map(
                              (FolderModel folder) => DropdownMenuItem<String>(
                                value: folder.id,
                                child: Text(folder.name),
                              ),
                            ),
                          ],
                          onChanged: (String? value) {
                            setState(() {
                              _selectedFolderId =
                                  value == null || value == _noFolderSelection
                                  ? null
                                  : value;
                              _inlineError = null;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        Text('背诵顺序', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: DeckReviewOrder.values.map((
                            DeckReviewOrder order,
                          ) {
                            return ChoiceChip(
                              label: Text(order.label),
                              selected: _selectedReviewOrder == order,
                              onSelected: (_) {
                                setState(() {
                                  _selectedReviewOrder = order;
                                  _inlineError = null;
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Text('图标', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _deckIconChoices.map((
                            _DeckIconChoice item,
                          ) {
                            final bool selected = _selectedIcon == item.raw;
                            return _DeckIconChoiceChip(
                              label: item.label,
                              icon: _deckIconFor(item.raw),
                              selected: selected,
                              onTap: () =>
                                  setState(() => _selectedIcon = item.raw),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Text('颜色', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _deckColorChoices.map((String colorHex) {
                            return _DeckColorChoice(
                              color: _parseDeckColor(colorHex, theme),
                              selected: _selectedColor == colorHex,
                              onTap: () =>
                                  setState(() => _selectedColor = colorHex),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '默认会使用「新卡/天 20」「最大复习 200」，创建后也可以在牌组设置里继续调整。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (_inlineError != null) ...<Widget>[
                          const SizedBox(height: 14),
                          _InlineMessage(
                            icon: Icons.error_outline,
                            text: _inlineError!,
                            color: theme.colorScheme.error,
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _submitting
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('取消'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _submitting ? null : _submit,
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.create_new_folder_outlined,
                                      ),
                                label: Text(_submitting ? '创建中…' : '创建牌组'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _inlineError = null;
    });
    final DeckModel? created = await ref
        .read(appStoreProvider.notifier)
        .createDeck(
          name: _nameController.text,
          description: _descriptionController.text,
          icon: _selectedIcon,
          colorHex: _selectedColor,
          folderId: _selectedFolderId,
          reviewOrder: _selectedReviewOrder,
        );
    if (!mounted) {
      return;
    }
    if (created == null) {
      setState(() {
        _submitting = false;
        _inlineError =
            ref.read(appStoreProvider).errorMessage ?? '创建牌组失败，请稍后重试';
      });
      return;
    }
    Navigator.of(context).pop(created.id);
  }
}

class _AIGenerateCardsSheet extends ConsumerStatefulWidget {
  const _AIGenerateCardsSheet({required this.deck});

  final DeckModel deck;

  @override
  ConsumerState<_AIGenerateCardsSheet> createState() =>
      _AIGenerateCardsSheetState();
}

class _AIGenerateCardsSheetState extends ConsumerState<_AIGenerateCardsSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _topicController;
  final TextEditingController _contextController = TextEditingController();
  final TextEditingController _countController = TextEditingController();
  final TextEditingController _maxAnswerCharsController = TextEditingController(
    text: '80',
  );
  final TextEditingController _policyRulesController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  _AIGenerateSourceMode _sourceMode = _AIGenerateSourceMode.topic;
  String _difficulty = 'medium';
  String _atomicityLevel = 'strict';
  String _answerStyle = 'one_sentence';
  bool _saveToReview = false;
  bool _pickingFile = false;
  bool _saving = false;
  bool _chatSending = false;
  bool _jobsExpanded = true;
  PlatformFile? _selectedFile;
  String? _inlineError;
  final Set<int> _selectedDraftIndexes = <int>{};
  final List<_AICardChatMessage> _chatMessages = <_AICardChatMessage>[
    const _AICardChatMessage(
      role: 'assistant',
      content: '可以直接告诉我你想怎么设计卡片。生成后，点进任意单张草稿就能继续微调。',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _topicController = TextEditingController(text: widget.deck.name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appStoreProvider.notifier).refreshAIGenerationJobs();
    });
  }

  @override
  void dispose() {
    _topicController.dispose();
    _contextController.dispose();
    _countController.dispose();
    _maxAnswerCharsController.dispose();
    _policyRulesController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    final List<AIGeneratedCard> generated = state.generatedCards;
    final AIDocumentSummary? document = state.generatedDocument;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'AI 生成卡片',
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '为「${widget.deck.name}」生成一组可编辑草稿，确认后再保存到牌组。',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: state.syncInProgress || _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close),
                        tooltip: '关闭',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TextFormField(
                          controller: _topicController,
                          decoration: const InputDecoration(
                            labelText: '主题',
                            hintText: '例如：操作系统进程调度 / CET-4 高频词',
                          ),
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入生成主题';
                            }
                            return null;
                          },
                          onChanged: (_) => setState(() => _inlineError = null),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<_AIGenerateSourceMode>(
                          segments:
                              const <ButtonSegment<_AIGenerateSourceMode>>[
                                ButtonSegment<_AIGenerateSourceMode>(
                                  value: _AIGenerateSourceMode.topic,
                                  icon: Icon(Icons.edit_note_outlined),
                                  label: Text('输入内容'),
                                ),
                                ButtonSegment<_AIGenerateSourceMode>(
                                  value: _AIGenerateSourceMode.file,
                                  icon: Icon(Icons.upload_file_outlined),
                                  label: Text('导入文件'),
                                ),
                              ],
                          selected: <_AIGenerateSourceMode>{_sourceMode},
                          onSelectionChanged:
                              (Set<_AIGenerateSourceMode> value) {
                                setState(() {
                                  _sourceMode = value.first;
                                  _inlineError = null;
                                });
                              },
                        ),
                        const SizedBox(height: 12),
                        _AIChatDesignerPanel(
                          controller: _chatController,
                          messages: _chatMessages,
                          sending: _chatSending || state.syncInProgress,
                          onSend: _sendChatMessage,
                        ),
                        const SizedBox(height: 12),
                        if (_sourceMode == _AIGenerateSourceMode.topic)
                          TextFormField(
                            controller: _contextController,
                            minLines: 3,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: '补充背景（可选）',
                              hintText: '粘贴课程大纲、知识点列表或你想覆盖的范围。',
                            ),
                            onChanged: (_) =>
                                setState(() => _inlineError = null),
                          )
                        else
                          _AIFilePickerCard(
                            file: _selectedFile,
                            picking: _pickingFile,
                            onPick: _pickFile,
                          ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder:
                              (
                                BuildContext context,
                                BoxConstraints constraints,
                              ) {
                                final bool compact = constraints.maxWidth < 520;
                                final Widget countField = TextFormField(
                                  controller: _countController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: '生成数量（可选）',
                                    hintText: '留空，由 AI 根据材料自动拆分',
                                  ),
                                  validator: (String? value) {
                                    final String raw = (value ?? '').trim();
                                    if (raw.isEmpty) {
                                      return null;
                                    }
                                    final int? parsed = int.tryParse(raw);
                                    if (parsed == null ||
                                        parsed < 1 ||
                                        parsed > 20) {
                                      return '请输入 1-20，或留空';
                                    }
                                    return null;
                                  },
                                  onChanged: (_) =>
                                      setState(() => _inlineError = null),
                                );
                                final Widget difficultyField =
                                    DropdownButtonFormField<String>(
                                      initialValue: _difficulty,
                                      decoration: const InputDecoration(
                                        labelText: '难度',
                                      ),
                                      items: const <DropdownMenuItem<String>>[
                                        DropdownMenuItem<String>(
                                          value: 'easy',
                                          child: Text('入门'),
                                        ),
                                        DropdownMenuItem<String>(
                                          value: 'medium',
                                          child: Text('标准'),
                                        ),
                                        DropdownMenuItem<String>(
                                          value: 'hard',
                                          child: Text('进阶'),
                                        ),
                                      ],
                                      onChanged: (String? value) {
                                        if (value == null) return;
                                        setState(() {
                                          _difficulty = value;
                                          _inlineError = null;
                                        });
                                      },
                                    );
                                if (compact) {
                                  return Column(
                                    children: <Widget>[
                                      countField,
                                      const SizedBox(height: 12),
                                      difficultyField,
                                    ],
                                  );
                                }
                                return Row(
                                  children: <Widget>[
                                    Expanded(child: countField),
                                    const SizedBox(width: 12),
                                    Expanded(child: difficultyField),
                                  ],
                                );
                              },
                        ),
                        const SizedBox(height: 12),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: const Text('拆卡规则'),
                          initiallyExpanded: true,
                          children: <Widget>[
                            LayoutBuilder(
                              builder:
                                  (
                                    BuildContext context,
                                    BoxConstraints constraints,
                                  ) {
                                    final bool compact =
                                        constraints.maxWidth < 520;
                                    final Widget atomicityField =
                                        DropdownButtonFormField<String>(
                                          initialValue: _atomicityLevel,
                                          decoration: const InputDecoration(
                                            labelText: '原子性',
                                          ),
                                          items:
                                              const <DropdownMenuItem<String>>[
                                                DropdownMenuItem<String>(
                                                  value: 'strict',
                                                  child: Text('严格'),
                                                ),
                                                DropdownMenuItem<String>(
                                                  value: 'balanced',
                                                  child: Text('平衡'),
                                                ),
                                                DropdownMenuItem<String>(
                                                  value: 'flexible',
                                                  child: Text('灵活'),
                                                ),
                                              ],
                                          onChanged: (String? value) {
                                            if (value == null) return;
                                            setState(() {
                                              _atomicityLevel = value;
                                              _inlineError = null;
                                            });
                                          },
                                        );
                                    final Widget answerStyleField =
                                        DropdownButtonFormField<String>(
                                          initialValue: _answerStyle,
                                          decoration: const InputDecoration(
                                            labelText: '答案形式',
                                          ),
                                          items:
                                              const <DropdownMenuItem<String>>[
                                                DropdownMenuItem<String>(
                                                  value: 'short_phrase',
                                                  child: Text('短词'),
                                                ),
                                                DropdownMenuItem<String>(
                                                  value: 'one_sentence',
                                                  child: Text('一句话'),
                                                ),
                                                DropdownMenuItem<String>(
                                                  value: 'bullet_points',
                                                  child: Text('要点'),
                                                ),
                                              ],
                                          onChanged: (String? value) {
                                            if (value == null) return;
                                            setState(() {
                                              _answerStyle = value;
                                              _inlineError = null;
                                            });
                                          },
                                        );
                                    if (compact) {
                                      return Column(
                                        children: <Widget>[
                                          atomicityField,
                                          const SizedBox(height: 12),
                                          answerStyleField,
                                        ],
                                      );
                                    }
                                    return Row(
                                      children: <Widget>[
                                        Expanded(child: atomicityField),
                                        const SizedBox(width: 12),
                                        Expanded(child: answerStyleField),
                                      ],
                                    );
                                  },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _maxAnswerCharsController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '答案字数上限',
                                hintText: '80',
                              ),
                              validator: (String? value) {
                                final int? parsed = int.tryParse(
                                  (value ?? '').trim(),
                                );
                                if (parsed == null ||
                                    parsed < 12 ||
                                    parsed > 600) {
                                  return '请输入 12-600';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _policyRulesController,
                              minLines: 2,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: '额外要求（可选）',
                                hintText: '例如：更贴近教育学考试，避免宽泛论述题。',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_inlineError != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _InlineMessage(
                      icon: Icons.error_outline,
                      text: _inlineError!,
                      color: theme.colorScheme.error,
                    ),
                  ],
                  if (state.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _InlineMessage(
                      icon: Icons.info_outline,
                      text: state.errorMessage!,
                      color: theme.colorScheme.tertiary,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: state.syncInProgress ? null : _generate,
                          icon: state.syncInProgress
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_outlined),
                          label: Text(state.syncInProgress ? '生成中…' : '生成草稿'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: state.syncInProgress
                              ? null
                              : _startBackgroundGeneration,
                          icon: const Icon(Icons.cloud_sync_outlined),
                          label: const Text('后台生成'),
                        ),
                      ),
                    ],
                  ),
                  if (state.aiGenerationJobs.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    _AIGenerationJobsCard(
                      jobs: state.aiGenerationJobs,
                      expanded: _jobsExpanded,
                      onToggleExpanded: () =>
                          setState(() => _jobsExpanded = !_jobsExpanded),
                      onRefresh: state.syncInProgress ? null : _refreshJobs,
                      onApply: _applyJobResult,
                    ),
                  ],
                  if (generated.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 18),
                    if (document != null) ...<Widget>[
                      _AIDocumentSummaryCard(document: document),
                      const SizedBox(height: 12),
                    ],
                    _SectionHeader(
                      title: '生成结果',
                      subtitle:
                          '已选择 ${_effectiveSelectedDraftIndexes(generated.length).length} / ${generated.length} 张，可部分保存、单张微调或合并所选。',
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        ActionChip(
                          avatar: const Icon(Icons.done_all_rounded, size: 18),
                          label: const Text('全选'),
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _selectedDraftIndexes
                                    ..clear()
                                    ..addAll(
                                      Iterable<int>.generate(generated.length),
                                    );
                                }),
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.remove_done_rounded,
                            size: 18,
                          ),
                          label: const Text('取消选择'),
                          onPressed: _saving
                              ? null
                              : () => setState(_selectedDraftIndexes.clear),
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.call_merge_rounded,
                            size: 18,
                          ),
                          label: const Text('合并所选'),
                          onPressed:
                              _effectiveSelectedDraftIndexes(
                                        generated.length,
                                      ).length <
                                      2 ||
                                  state.syncInProgress ||
                                  _saving
                              ? null
                              : _mergeSelectedDrafts,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (int index = 0; index < generated.length; index += 1)
                      _GeneratedCardPreview(
                        index: index,
                        item: generated[index],
                        selected: _effectiveSelectedDraftIndexes(
                          generated.length,
                        ).contains(index),
                        onSelectedChanged: _saving
                            ? null
                            : (bool selected) =>
                                  _setDraftSelected(index, selected),
                        onRewrite: state.syncInProgress || _saving
                            ? null
                            : () => _openGeneratedCardChat(index),
                        onSplit: state.syncInProgress || _saving
                            ? null
                            : () => _splitGeneratedCard(index),
                      ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: _saveToReview,
                      onChanged: _saving
                          ? null
                          : (bool value) =>
                                setState(() => _saveToReview = value),
                      title: const Text('保存后加入背诵'),
                      subtitle: const Text('开启后会进入服务端 FSRS 复习队列。'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => ref
                                      .read(appStoreProvider.notifier)
                                      .clearGeneratedCards(),
                            child: const Text('清空结果'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _saveGenerated,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              _saving
                                  ? '保存中…'
                                  : '保存所选 ${_effectiveSelectedDraftIndexes(generated.length).length} 张',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _inlineError = null);
    final GenerationPolicy policy = _buildPolicy();
    final int cardCount = _requestedCardCount();
    if (_sourceMode == _AIGenerateSourceMode.file) {
      final PlatformFile? file = _selectedFile;
      if (file == null || file.bytes == null) {
        setState(() => _inlineError = '请选择 PDF、TXT 或 Markdown 文件');
        return;
      }
      await ref
          .read(appStoreProvider.notifier)
          .generateCardsFromFile(
            filename: file.name,
            bytes: file.bytes!,
            topic: _topicController.text.trim(),
            cardCount: cardCount,
            difficulty: _difficulty,
            policy: policy,
          );
      _selectAllGeneratedDrafts();
      return;
    }
    await ref
        .read(appStoreProvider.notifier)
        .generateCards(
          topic: _topicController.text.trim(),
          context: _contextController.text.trim(),
          cardCount: cardCount,
          difficulty: _difficulty,
          policy: policy,
        );
    _selectAllGeneratedDrafts();
  }

  Future<void> _startBackgroundGeneration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _inlineError = null);
    final AppStore store = ref.read(appStoreProvider.notifier);
    final GenerationPolicy policy = _buildPolicy();
    final int cardCount = _requestedCardCount();
    AIGenerationJob? job;
    if (_sourceMode == _AIGenerateSourceMode.file) {
      final PlatformFile? file = _selectedFile;
      if (file == null || file.bytes == null) {
        setState(() => _inlineError = '请选择 PDF、TXT 或 Markdown 文件');
        return;
      }
      job = await store.startAIGenerationJobFromFile(
        filename: file.name,
        bytes: file.bytes!,
        topic: _topicController.text.trim(),
        cardCount: cardCount,
        difficulty: _difficulty,
        policy: policy,
      );
    } else {
      job = await store.startAIGenerationJob(
        topic: _topicController.text.trim(),
        context: _contextController.text.trim(),
        cardCount: cardCount,
        difficulty: _difficulty,
        policy: policy,
      );
    }
    if (!mounted || job == null) {
      return;
    }
    setState(() {
      _jobsExpanded = true;
      _inlineError = '已转入后台生成，可关闭窗口，稍后从后台任务取回结果。';
    });
  }

  int _requestedCardCount() {
    return int.tryParse(_countController.text.trim()) ?? 0;
  }

  void _selectAllGeneratedDrafts() {
    if (!mounted) return;
    final int count = ref.read(appStoreProvider).generatedCards.length;
    setState(() {
      _selectedDraftIndexes
        ..clear()
        ..addAll(Iterable<int>.generate(count));
    });
  }

  Set<int> _effectiveSelectedDraftIndexes(int draftCount) {
    final Set<int> selected = _selectedDraftIndexes
        .where((int index) => index >= 0 && index < draftCount)
        .toSet();
    if (selected.isEmpty && draftCount > 0) {
      return Set<int>.from(Iterable<int>.generate(draftCount));
    }
    return selected;
  }

  void _setDraftSelected(int index, bool selected) {
    setState(() {
      if (selected) {
        _selectedDraftIndexes.add(index);
      } else {
        _selectedDraftIndexes.remove(index);
      }
    });
  }

  Future<void> _refreshJobs() async {
    await ref.read(appStoreProvider.notifier).refreshAIGenerationJobs();
  }

  void _applyJobResult(AIGenerationJob job) {
    ref.read(appStoreProvider.notifier).applyAIGenerationJobResult(job);
    _selectAllGeneratedDrafts();
  }

  Future<void> _sendChatMessage() async {
    final String text = _chatController.text.trim();
    if (text.isEmpty || _chatSending) {
      return;
    }
    final _AICardChatMessage userMessage = _AICardChatMessage(
      role: 'user',
      content: text,
    );
    setState(() {
      _chatMessages.add(userMessage);
      _chatController.clear();
      _chatSending = true;
      _inlineError = null;
    });
    final AICardChatResponse? response = await ref
        .read(appStoreProvider.notifier)
        .chatWithGeneratedCards(
          topic: _topicController.text.trim(),
          instruction: text,
          cardCount: _requestedCardCount(),
          difficulty: _difficulty,
          messages: _chatMessages
              .map(
                (_AICardChatMessage message) => <String, String>{
                  'role': message.role,
                  'content': message.content,
                },
              )
              .toList(),
          policy: _buildPolicy(),
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _chatSending = false;
      if (response != null && response.assistantMessage.trim().isNotEmpty) {
        _chatMessages.add(
          _AICardChatMessage(
            role: 'assistant',
            content: response.assistantMessage,
          ),
        );
      }
    });
    if (response != null) {
      _selectAllGeneratedDrafts();
    }
  }

  GenerationPolicy _buildPolicy() {
    return GenerationPolicy(
      name: '当前生成规则',
      subject: _topicController.text.trim(),
      atomicityLevel: _atomicityLevel,
      answerStyle: _answerStyle,
      maxAnswerChars: int.tryParse(_maxAnswerCharsController.text.trim()) ?? 80,
      preferredCardTypes: const <String>[
        'basic',
        'cloze',
        'single_choice',
        'multi_choice',
      ],
      splitStrategy: 'by_heading',
      coverageMode: 'balanced',
      customRules: _policyRulesController.text.trim(),
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _pickingFile = true;
      _inlineError = null;
    });
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf', 'txt', 'md', 'markdown'],
        withData: true,
      );
      if (!mounted) {
        return;
      }
      if (result == null || result.files.isEmpty) {
        setState(() => _inlineError = '没有选择文件');
        return;
      }
      final PlatformFile file = result.files.single;
      if (file.bytes == null) {
        setState(() => _inlineError = '无法读取文件内容，请换一个本地文件再试');
        return;
      }
      setState(() => _selectedFile = file);
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _inlineError = '打开文件选择器失败：${error.message ?? error.code}');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _inlineError = '打开文件选择器失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _pickingFile = false);
      }
    }
  }

  Future<void> _saveGenerated() async {
    final int draftCount = ref.read(appStoreProvider).generatedCards.length;
    final Set<int> selected = _effectiveSelectedDraftIndexes(draftCount);
    if (selected.isEmpty) {
      setState(() => _inlineError = '请选择至少一张要保存的草稿');
      return;
    }
    setState(() {
      _saving = true;
      _inlineError = null;
    });
    await ref
        .read(appStoreProvider.notifier)
        .saveGeneratedCardsToDeck(
          widget.deck.id,
          studyEnabled: _saveToReview,
          selectedIndexes: selected.toList(),
        );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (ref.read(appStoreProvider).generatedCards.isEmpty) {
      Navigator.of(context).pop(true);
    } else {
      _selectAllGeneratedDrafts();
    }
  }

  Future<void> _openGeneratedCardChat(int index) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _AIGeneratedDraftChatSheet(
        cardIndex: index,
        topic: _topicController.text.trim(),
        difficulty: _difficulty,
        policy: _buildPolicy(),
      ),
    );
    if (!mounted) {
      return;
    }
    _selectAllGeneratedDrafts();
  }

  Future<void> _splitGeneratedCard(int index) async {
    final AICardChatResponse? response = await ref
        .read(appStoreProvider.notifier)
        .chatWithGeneratedCards(
          topic: _topicController.text.trim(),
          instruction: '请把这张卡拆成多张更小、更原子的卡片。',
          operation: 'split',
          selectedIndexes: <int>[index],
          cardCount: 0,
          difficulty: _difficulty,
          messages: const <Map<String, String>>[],
          policy: _buildPolicy(),
        );
    if (mounted && response != null) {
      _selectAllGeneratedDrafts();
    }
  }

  Future<void> _mergeSelectedDrafts() async {
    final List<int> selected = _effectiveSelectedDraftIndexes(
      ref.read(appStoreProvider).generatedCards.length,
    ).toList()..sort();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _AIMergeDraftsSheet(
        selectedIndexes: selected,
        topic: _topicController.text.trim(),
        difficulty: _difficulty,
        policy: _buildPolicy(),
      ),
    );
    if (mounted) {
      _selectAllGeneratedDrafts();
    }
  }
}

class _AICardChatMessage {
  const _AICardChatMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class _AIChatDesignerPanel extends StatelessWidget {
  const _AIChatDesignerPanel({
    required this.controller,
    required this.messages,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final List<_AICardChatMessage> messages;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.chat_bubble_outline_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('对话式制卡', style: theme.textTheme.titleMedium),
                ),
                Text(
                  '卡片在下方预览',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(minHeight: 130, maxHeight: 220),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: ListView.separated(
                reverse: true,
                itemCount: messages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int reversedIndex) {
                  final int index = messages.length - 1 - reversedIndex;
                  final _AICardChatMessage message = messages[index];
                  return _AIChatBubble(message: message);
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '告诉 AI 你的制卡/微调需求',
                      hintText: '例如：把这些卡改得更像考试选择题，答案更短。',
                    ),
                    onSubmitted: (_) {
                      if (!sending) {
                        onSend();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: sending ? null : onSend,
                  icon: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  tooltip: sending ? '发送中' : '发送',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AIChatBubble extends StatelessWidget {
  const _AIChatBubble({required this.message});

  final _AICardChatMessage message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool fromUser = message.role == 'user';
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fromUser ? scheme.primaryContainer : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Text(
              message.content,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: fromUser ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AIGenerationJobsCard extends StatelessWidget {
  const _AIGenerationJobsCard({
    required this.jobs,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onRefresh,
    required this.onApply,
  });

  final List<AIGenerationJob> jobs;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback? onRefresh;
  final ValueChanged<AIGenerationJob> onApply;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.cloud_done_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('后台任务', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '刷新任务',
                ),
                IconButton(
                  onPressed: onToggleExpanded,
                  icon: Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  tooltip: expanded ? '收起' : '展开',
                ),
              ],
            ),
            if (expanded) ...<Widget>[
              const SizedBox(height: 8),
              for (final AIGenerationJob job in jobs.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AIGenerationJobTile(job: job, onApply: onApply),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AIGenerationJobTile extends StatelessWidget {
  const _AIGenerationJobTile({required this.job, required this.onApply});

  final AIGenerationJob job;
  final ValueChanged<AIGenerationJob> onApply;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String title = job.sourceName.trim().isEmpty
        ? '后台生成任务'
        : job.sourceName;
    final bool running = job.status == 'running';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            running
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    job.status == 'succeeded'
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    color: job.status == 'succeeded'
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    job.status == 'succeeded'
                        ? '${job.resultItems.length} 张草稿可取回'
                        : job.status == 'failed'
                        ? firstNonEmptyLine(job.errorMessage) ?? '生成失败'
                        : '生成中 ${(job.progress.clamp(0, 1) * 100).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: job.hasResult ? () => onApply(job) : null,
              child: const Text('取回'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AIGeneratedDraftChatSheet extends ConsumerStatefulWidget {
  const _AIGeneratedDraftChatSheet({
    required this.cardIndex,
    required this.topic,
    required this.difficulty,
    required this.policy,
  });

  final int cardIndex;
  final String topic;
  final String difficulty;
  final GenerationPolicy policy;

  @override
  ConsumerState<_AIGeneratedDraftChatSheet> createState() =>
      _AIGeneratedDraftChatSheetState();
}

class _AIGeneratedDraftChatSheetState
    extends ConsumerState<_AIGeneratedDraftChatSheet> {
  final TextEditingController _controller = TextEditingController();
  final List<_AICardChatMessage> _messages = <_AICardChatMessage>[
    const _AICardChatMessage(
      role: 'assistant',
      content: '我会只围绕这张草稿调整；也可以直接让我拆成多张更小的卡。',
    ),
  ];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    final AIGeneratedCard? item =
        widget.cardIndex >= 0 && widget.cardIndex < state.generatedCards.length
        ? state.generatedCards[widget.cardIndex]
        : null;
    final CardDocumentParts parts = CardDocumentCodec.parse(
      item?.content ?? '',
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '微调第 ${widget.cardIndex + 1} 张草稿',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _sending
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: '关闭',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _GeneratedDraftSnippet(
                    title: item?.title ?? '当前草稿',
                    prompt: parts.prompt,
                    answer: parts.answer,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppDesign.radiusMd),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      reverse: true,
                      itemCount: _messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int reversedIndex) {
                        final int index = _messages.length - 1 - reversedIndex;
                        return _AIChatBubble(message: _messages[index]);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: '告诉 AI 如何改这张卡',
                            hintText: '例如：答案更短，题干更像考试题。',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: _sending ? null : () => _send('refine'),
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        tooltip: '发送',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _sending ? null : () => _send('split'),
                    icon: const Icon(Icons.call_split_rounded),
                    label: const Text('拆成多张原子卡'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _send(String operation) async {
    final String text = _controller.text.trim();
    final String instruction = operation == 'split' && text.isEmpty
        ? '请拆成多张更小、更原子的卡片。'
        : text;
    if (instruction.isEmpty || _sending) {
      return;
    }
    setState(() {
      _messages.add(_AICardChatMessage(role: 'user', content: instruction));
      _controller.clear();
      _sending = true;
    });
    final AICardChatResponse? response = await ref
        .read(appStoreProvider.notifier)
        .chatWithGeneratedCards(
          topic: widget.topic,
          instruction: instruction,
          operation: operation,
          selectedIndexes: <int>[widget.cardIndex],
          cardCount: 0,
          difficulty: widget.difficulty,
          messages: _messages
              .map(
                (_AICardChatMessage message) => <String, String>{
                  'role': message.role,
                  'content': message.content,
                },
              )
              .toList(),
          policy: widget.policy,
        );
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (response != null && response.assistantMessage.trim().isNotEmpty) {
        _messages.add(
          _AICardChatMessage(
            role: 'assistant',
            content: response.assistantMessage,
          ),
        );
      }
    });
  }
}

class _AIMergeDraftsSheet extends ConsumerStatefulWidget {
  const _AIMergeDraftsSheet({
    required this.selectedIndexes,
    required this.topic,
    required this.difficulty,
    required this.policy,
  });

  final List<int> selectedIndexes;
  final String topic;
  final String difficulty;
  final GenerationPolicy policy;

  @override
  ConsumerState<_AIMergeDraftsSheet> createState() =>
      _AIMergeDraftsSheetState();
}

class _AIMergeDraftsSheetState extends ConsumerState<_AIMergeDraftsSheet> {
  final TextEditingController _controller = TextEditingController(
    text: '合并成一张对比卡，保留核心区别和联系。',
  );
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    final List<AIGeneratedCard> selected = widget.selectedIndexes
        .where((int index) => index >= 0 && index < state.generatedCards.length)
        .map((int index) => state.generatedCards[index])
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '合并 ${selected.length} 张草稿',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: '关闭',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final AIGeneratedCard item in selected.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _GeneratedDraftSnippet(
                      title: item.title,
                      prompt: CardDocumentCodec.promptPreview(item.content),
                      answer: CardDocumentCodec.parse(item.content).answer,
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '合并要求'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _sending ? null : _merge,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.call_merge_rounded),
                  label: Text(_sending ? '合并中…' : '合并所选草稿'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _merge() async {
    setState(() => _sending = true);
    final AICardChatResponse? response = await ref
        .read(appStoreProvider.notifier)
        .chatWithGeneratedCards(
          topic: widget.topic,
          instruction: _controller.text.trim(),
          operation: 'merge',
          selectedIndexes: widget.selectedIndexes,
          cardCount: 0,
          difficulty: widget.difficulty,
          messages: const <Map<String, String>>[],
          policy: widget.policy,
        );
    if (!mounted) return;
    setState(() => _sending = false);
    if (response != null) {
      Navigator.of(context).pop();
    }
  }
}

class _GeneratedCardPreview extends StatelessWidget {
  const _GeneratedCardPreview({
    required this.index,
    required this.item,
    required this.selected,
    required this.onSelectedChanged,
    required this.onRewrite,
    required this.onSplit,
  });

  final int index;
  final AIGeneratedCard item;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;
  final VoidCallback? onRewrite;
  final VoidCallback? onSplit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CardDocumentParts parts = CardDocumentCodec.parse(item.content);
    final AIQualityReport? quality = item.qualityReport;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Checkbox(
                  value: selected,
                  onChanged: onSelectedChanged == null
                      ? null
                      : (bool? value) => onSelectedChanged!(value ?? false),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.title.isEmpty ? '未命名卡片' : item.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onRewrite,
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                  label: const Text('微调'),
                ),
                IconButton(
                  onPressed: onSplit,
                  icon: const Icon(Icons.call_split_rounded),
                  tooltip: '拆成多张',
                ),
              ],
            ),
            if (quality != null || item.sourceLocation.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  if (quality != null)
                    _MetaChip(
                      label: quality.hasViolations
                          ? '需检查 ${quality.violations.length}'
                          : '规则通过',
                    ),
                  if (quality != null)
                    _MetaChip(
                      label: '质量 ${(quality.score.clamp(0, 1) * 100).round()}%',
                    ),
                  if (item.sourceLocation.isNotEmpty)
                    _MetaChip(label: item.sourceLocation),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              CardDocumentCodec.promptPreview(item.content),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            if (parts.answer.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                parts.answer,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (item.tags.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final String tag in item.tags.take(5))
                    _MetaChip(label: tag),
                ],
              ),
            ],
            if (quality != null && quality.violations.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                quality.violations.first.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AIGeneratedDraftRewriteSheet extends ConsumerStatefulWidget {
  const _AIGeneratedDraftRewriteSheet({required this.item});

  final AIGeneratedCard item;

  @override
  ConsumerState<_AIGeneratedDraftRewriteSheet> createState() =>
      _AIGeneratedDraftRewriteSheetState();
}

class _AIGeneratedDraftRewriteSheetState
    extends ConsumerState<_AIGeneratedDraftRewriteSheet> {
  final TextEditingController _instructionController = TextEditingController();
  String _rewriteType = 'improve';
  List<AIRewriteCandidate> _candidates = const <AIRewriteCandidate>[];

  static const List<_DraftRewriteAction> _actions = <_DraftRewriteAction>[
    _DraftRewriteAction(
      value: 'improve',
      icon: Icons.tune_rounded,
      label: '优化表达',
    ),
    _DraftRewriteAction(
      value: 'simplify_answer',
      icon: Icons.compress_rounded,
      label: '简化答案',
    ),
    _DraftRewriteAction(
      value: 'make_cloze',
      icon: Icons.hide_source_outlined,
      label: '改填空',
    ),
    _DraftRewriteAction(
      value: 'split',
      icon: Icons.call_split_rounded,
      label: '拆原子卡',
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
    final CardDocumentParts parts = CardDocumentCodec.parse(
      widget.item.content,
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '微调这张草稿',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '生成候选后再应用，不会直接保存到牌组。',
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
                  const SizedBox(height: 12),
                  _GeneratedDraftSnippet(
                    title: widget.item.title,
                    prompt: parts.prompt,
                    answer: parts.answer,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final _DraftRewriteAction action in _actions)
                        ChoiceChip(
                          avatar: Icon(action.icon, size: 17),
                          label: Text(action.label),
                          selected: _rewriteType == action.value,
                          onSelected: state.syncInProgress
                              ? null
                              : (bool selected) {
                                  if (!selected) return;
                                  setState(() {
                                    _rewriteType = action.value;
                                    _candidates = const <AIRewriteCandidate>[];
                                  });
                                },
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
                      hintText: '例如：更适合教育学考试，答案压到一句话。',
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
                    label: Text(state.syncInProgress ? '微调中…' : '生成微调候选'),
                  ),
                  if (state.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _InlineMessage(
                      icon: Icons.info_outline,
                      text: state.errorMessage!,
                      color: theme.colorScheme.error,
                    ),
                  ],
                  if (_candidates.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(
                      '候选版本',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final AIRewriteCandidate candidate in _candidates)
                      _GeneratedRewriteCandidateCard(candidate: candidate),
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
          title: widget.item.title,
          content: widget.item.content,
          rewriteType: _rewriteType,
          instruction: _instructionController.text.trim(),
        );
    if (!mounted) {
      return;
    }
    setState(() => _candidates = candidates);
  }
}

class _DraftRewriteAction {
  const _DraftRewriteAction({
    required this.value,
    required this.icon,
    required this.label,
  });

  final String value;
  final IconData icon;
  final String label;
}

class _GeneratedDraftSnippet extends StatelessWidget {
  const _GeneratedDraftSnippet({
    required this.title,
    required this.prompt,
    required this.answer,
  });

  final String title;
  final String prompt;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
            title.isEmpty ? '当前草稿' : title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            prompt.trim().isEmpty ? '暂无题干' : prompt.trim(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          if (answer.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 8),
            Text(
              answer.trim(),
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

class _GeneratedRewriteCandidateCard extends StatelessWidget {
  const _GeneratedRewriteCandidateCard({required this.candidate});

  final AIRewriteCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CardDocumentParts parts = CardDocumentCodec.parse(candidate.content);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                        candidate.title.isEmpty ? '微调候选' : candidate.title,
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
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(candidate),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('应用'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              parts.prompt.trim().isEmpty ? candidate.content : parts.prompt,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (parts.answer.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                parts.answer.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (candidate.qualityNotes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final String note in candidate.qualityNotes.take(4))
                    _MetaChip(label: note),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _AIGenerateSourceMode { topic, file }

class _AIFilePickerCard extends StatelessWidget {
  const _AIFilePickerCard({
    required this.file,
    required this.picking,
    required this.onPick,
  });

  final PlatformFile? file;
  final bool picking;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PlatformFile? selected = file;
    final Widget leading = Icon(
      Icons.picture_as_pdf_outlined,
      color: theme.colorScheme.primary,
    );
    final Widget details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          selected == null ? '选择 PDF / Markdown / TXT 文件' : selected.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          selected == null
              ? '支持教材章节、知识点集合；Markdown 图片会保留引用和图注，扫描 PDF 暂不做 OCR。'
              : '${_formatFileSize(selected.size)} · 可复制文本 PDF / Markdown / TXT',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final Widget pickButton = OutlinedButton.icon(
      onPressed: picking ? null : onPick,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(96, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      icon: picking
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload_file_outlined, size: 18),
      label: Text(selected == null ? '选择' : '更换'),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 380;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    leading,
                    const SizedBox(width: 12),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: pickButton),
              ],
            );
          }
          return Row(
            children: <Widget>[
              leading,
              const SizedBox(width: 12),
              Expanded(child: details),
              const SizedBox(width: 12),
              pickButton,
            ],
          );
        },
      ),
    );
  }
}

class _AIDocumentSummaryCard extends StatelessWidget {
  const _AIDocumentSummaryCard({required this.document});

  final AIDocumentSummary document;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.description_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _MetaChip(label: '文本 ${document.textLength} 字'),
                if (document.pageCount > 0)
                  _MetaChip(label: 'PDF ${document.pageCount} 页'),
                if (document.chunkCount > 0)
                  _MetaChip(label: '切分 ${document.chunkCount} 段'),
                if (document.imageCount > 0)
                  _MetaChip(label: '图片引用 ${document.imageCount} 个'),
              ],
            ),
            if (document.imageCount > 0) ...<Widget>[
              const SizedBox(height: 8),
              _InlineMessage(
                icon: Icons.image_outlined,
                text:
                    '已把 Markdown 图片引用和 alt 文本加入上下文；当前不会自动 OCR 图片像素内容，请确保正文或图注写出关键知识点。',
                color: theme.colorScheme.tertiary,
              ),
              if (document.images.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final AIImportedImage image in document.images.take(4))
                      _MetaChip(
                        label:
                            '${image.isRemote ? '远程' : '本地'}图：${image.alt.isEmpty ? image.source : image.alt}',
                      ),
                  ],
                ),
              ],
            ],
            if (document.textPreview.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                document.textPreview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, this.deckId});

  final String? deckId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _sessionTotal = 0;
  bool _revealed = false;
  String? _activeCardId;
  String? _sessionDeckId;
  ReviewRating? _submittingRating;
  List<String> _sessionQueueCardIds = <String>[];
  Timer? _queueRefreshTimer;
  DateTime? _queueRefreshTarget;

  @override
  void dispose() {
    _queueRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final List<CardModel> plannedQueue = state.dueCards(deckId: widget.deckId);
    if (_sessionDeckId != widget.deckId) {
      _sessionDeckId = widget.deckId;
      _sessionTotal = 0;
      _sessionQueueCardIds = <String>[];
      _queueRefreshTimer?.cancel();
      _queueRefreshTarget = null;
      _activeCardId = null;
      _revealed = false;
      _submittingRating = null;
    }
    if (_sessionQueueCardIds.isEmpty && plannedQueue.isNotEmpty) {
      _sessionQueueCardIds = plannedQueue
          .map((CardModel card) => card.id)
          .toList();
      _sessionTotal = _sessionQueueCardIds.length;
    }
    final Map<String, CardModel> plannedQueueById = <String, CardModel>{
      for (final CardModel card in plannedQueue) card.id: card,
    };
    List<CardModel> dueCards = _sessionQueueCardIds
        .map((String id) => plannedQueueById[id])
        .whereType<CardModel>()
        .toList();
    if (dueCards.isEmpty && plannedQueue.isNotEmpty) {
      _sessionQueueCardIds = plannedQueue
          .map((CardModel card) => card.id)
          .toList();
      _sessionTotal = _sessionQueueCardIds.length;
      dueCards = plannedQueue;
    }
    if (dueCards.length > _sessionTotal) {
      _sessionTotal = dueCards.length;
    }
    final int reviewTotal = _sessionTotal == 0
        ? dueCards.length
        : _sessionTotal;
    final int completedCount = reviewTotal == 0
        ? 0
        : (reviewTotal - dueCards.length).clamp(0, reviewTotal);
    _scheduleQueueRefreshIfNeeded(state, dueCards);

    if (dueCards.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('今日复习')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _SectionBadge(
                    icon: reviewTotal > 0
                        ? Icons.check_circle_outline
                        : Icons.schedule_outlined,
                    label: reviewTotal > 0 ? '本轮已完成' : '暂无待复习',
                  ),
                  const SizedBox(height: 20),
                  Text(
                    reviewTotal > 0
                        ? '你已经完成了本轮 $reviewTotal 张卡片。'
                        : '当前没有到期卡片，可以先去创建新卡片。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    reviewTotal > 0
                        ? '现在可以回到牌组继续整理内容，或者稍后再开始新的复习。'
                        : '返回牌组看看有没有需要补充的新内容。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.dashboard_outlined),
                    label: Text(reviewTotal > 0 ? '返回牌组' : '去牌组看看'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final CardModel currentCard = dueCards.first;
    if (_activeCardId != currentCard.id) {
      _activeCardId = currentCard.id;
      _revealed = false;
    }
    final PlainChoiceQuestion? plainChoice = PlainChoiceQuestion.tryParse(
      prompt: currentCard.prompt,
      answer: currentCard.answer,
    );
    final String reviewFront = plainChoice?.toDsl() ?? currentCard.prompt;
    final bool hasInteractive = dslHasInteractiveContent(reviewFront);
    final bool hasHiddenAnswer = currentCard.answer.trim().isNotEmpty;
    final bool requiresReveal = hasInteractive || hasHiddenAnswer;
    final bool canRate = !requiresReveal || _revealed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日复习'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Text('第 ${completedCount + 1} / $reviewTotal'),
          ),
        ],
      ),
      body: AppPageScrollView(
        maxWidth: 920,
        bottomPadding: 32,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: <Widget>[
          LinearProgressIndicator(
            value: reviewTotal == 0 ? 0 : completedCount / reviewTotal,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _MetaChip(label: '已完成 $completedCount / $reviewTotal'),
              if (widget.deckId != null) const _MetaChip(label: '当前为牌组复习'),
            ],
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DslCardView(
                    key: ValueKey<String>('review-${currentCard.id}'),
                    front: reviewFront,
                    back: currentCard.answer,
                    revealed: _revealed,
                    onReveal: requiresReveal
                        ? () => setState(() => _revealed = true)
                        : null,
                    showBackInline: false,
                    revealLabel: hasInteractive ? '提交答案' : '查看答案',
                  ),
                  if (currentCard.note.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    _InfoPanel(
                      icon: Icons.sticky_note_2_outlined,
                      title: '备注',
                      subtitle: currentCard.note,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: canRate
                ? _buildRatingControls(context, currentCard.id)
                : Container(
                    key: const ValueKey<String>('rating-hint'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          hasInteractive
                              ? Icons.task_alt_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hasInteractive ? '先提交答案，再选择评分。' : '先查看答案，再选择评分。',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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

  String _labelFor(ReviewRating rating) {
    switch (rating) {
      case ReviewRating.again:
        return '没想起';
      case ReviewRating.hard:
        return '想起但卡住';
      case ReviewRating.good:
        return '正常想起';
      case ReviewRating.easy:
        return '一眼就会';
    }
  }

  String _descriptionFor(ReviewRating rating) {
    switch (rating) {
      case ReviewRating.again:
        return '看答案前没有回忆出来';
      case ReviewRating.hard:
        return '想起来了，但慢或不确定';
      case ReviewRating.good:
        return '能稳定回忆，基本准确';
      case ReviewRating.easy:
        return '秒答且非常确定';
    }
  }

  IconData _iconFor(ReviewRating rating) {
    switch (rating) {
      case ReviewRating.again:
        return Icons.refresh_rounded;
      case ReviewRating.hard:
        return Icons.hourglass_bottom_rounded;
      case ReviewRating.good:
        return Icons.check_circle_outline_rounded;
      case ReviewRating.easy:
        return Icons.bolt_rounded;
    }
  }

  Color _ratingColor(BuildContext context, ReviewRating rating) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    switch (rating) {
      case ReviewRating.again:
        return scheme.error;
      case ReviewRating.hard:
        return scheme.tertiary;
      case ReviewRating.good:
        return scheme.primary;
      case ReviewRating.easy:
        return const Color(0xFF0F9D7A);
    }
  }

  Widget _buildRatingControls(BuildContext context, String cardId) {
    return LayoutBuilder(
      key: const ValueKey<String>('rating-controls'),
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 600;
        final double itemWidth = compact
            ? (constraints.maxWidth - 8) / 2
            : (constraints.maxWidth - 24) / 4;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final ReviewRating rating in ReviewRating.values)
              SizedBox(
                width: itemWidth,
                child: _ReviewRatingButton(
                  icon: _iconFor(rating),
                  label: _labelFor(rating),
                  description: _descriptionFor(rating),
                  color: _ratingColor(context, rating),
                  loading: _submittingRating == rating,
                  onPressed: _submittingRating == null
                      ? () => _submit(rating, cardId)
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _submit(ReviewRating rating, String cardId) async {
    if (_submittingRating != null) {
      return;
    }
    setState(() => _submittingRating = rating);
    final CardModel? updated = await ref
        .read(appStoreProvider.notifier)
        .submitReview(cardId: cardId, rating: rating);
    if (!mounted) return;
    if (updated == null) {
      final String message =
          ref.read(appStoreProvider).errorMessage ?? '提交评分失败，请稍后重试';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      setState(() => _submittingRating = null);
      return;
    }
    setState(() {
      _sessionQueueCardIds.remove(cardId);
      _revealed = false;
      _submittingRating = null;
    });
  }

  void _scheduleQueueRefreshIfNeeded(
    AppState state,
    List<CardModel> visibleDueCards,
  ) {
    if (visibleDueCards.isNotEmpty) {
      _queueRefreshTimer?.cancel();
      _queueRefreshTimer = null;
      _queueRefreshTarget = null;
      return;
    }
    final DateTime now = DateTime.now();
    DateTime? nextDueAt;
    for (final CardModel card in state.cards) {
      if (!card.studyEnabled) {
        continue;
      }
      if (widget.deckId != null && card.deckId != widget.deckId) {
        continue;
      }
      final DateTime dueDate = card.state.dueDate;
      if (!dueDate.isAfter(now)) {
        continue;
      }
      if (nextDueAt == null || dueDate.isBefore(nextDueAt)) {
        nextDueAt = dueDate;
      }
    }
    if (nextDueAt == null) {
      _queueRefreshTimer?.cancel();
      _queueRefreshTimer = null;
      _queueRefreshTarget = null;
      return;
    }
    final Duration delay =
        nextDueAt.difference(now) + const Duration(seconds: 1);
    if ((_queueRefreshTimer?.isActive ?? false) &&
        _queueRefreshTarget == nextDueAt) {
      return;
    }
    _queueRefreshTimer?.cancel();
    _queueRefreshTarget = nextDueAt;
    _queueRefreshTimer = Timer(delay, () {
      if (!mounted) {
        return;
      }
      _queueRefreshTarget = null;
      setState(() {});
    });
  }
}

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppState state = ref.watch(appStoreProvider);
    final int totalCards = state.cards.length;
    final int dueCards = state.dueCards().length;
    final int localCards = state.cards
        .where((CardModel item) => item.id.startsWith('local_'))
        .length;
    final int studyCards = state.cards
        .where((CardModel item) => item.studyEnabled)
        .length;
    final int draftCards = totalCards - studyCards;
    final DateTime now = DateTime.now();
    final List<CardModel> nextDueCards =
        state.cards
            .where((CardModel item) => item.studyEnabled)
            .where((CardModel item) => item.state.dueDate.isAfter(now))
            .toList()
          ..sort(
            (CardModel a, CardModel b) =>
                a.state.dueDate.compareTo(b.state.dueDate),
          );
    final DateTime? nextDueAt = nextDueCards.isEmpty
        ? null
        : nextDueCards.first.state.dueDate;
    final List<_DeckDueSummary> deckDueSummaries =
        state.decks
            .map(
              (DeckModel deck) => _DeckDueSummary(
                deck: deck,
                dueCount: state.dueCountForDeck(deck.id),
                cardCount: state.cardCountForDeck(deck.id),
              ),
            )
            .where((_DeckDueSummary item) => item.cardCount > 0)
            .toList()
          ..sort((_DeckDueSummary a, _DeckDueSummary b) {
            final int dueCompare = b.dueCount.compareTo(a.dueCount);
            if (dueCompare != 0) {
              return dueCompare;
            }
            return a.deck.name.compareTo(b.deck.name);
          });
    final List<_UpcomingLoad> upcomingLoads = _buildUpcomingLoads(
      state.cards,
      now,
    );
    final double dueRatio = totalCards == 0 ? 0 : dueCards / totalCards;
    final double localRatio = totalCards == 0 ? 0 : localCards / totalCards;
    final double studyRatio = totalCards == 0 ? 0 : studyCards / totalCards;
    final double syncHealth = state.pendingOperationCount >= 5
        ? 0
        : 1 - (state.pendingOperationCount / 5);

    return Scaffold(
      appBar: AppBar(title: const Text('学习统计')),
      body: AppPageScrollView(
        maxWidth: 1120,
        children: <Widget>[
          _HeroPanel(
            title: '学习统计',
            subtitle: '从复习进度、同步队列和本地临时数据三个维度观察当前状态。',
            trailing: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _StatBadge(label: '完成', value: '${state.completedToday}'),
                _StatBadge(
                  label: '同步队列',
                  value: '${state.pendingOperationCount}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _MetricCard(title: '牌组数量', value: '${state.decks.length}'),
              _MetricCard(title: '卡片总数', value: '$totalCards'),
              _MetricCard(title: '已加入背诵', value: '$studyCards'),
              _MetricCard(title: '草稿卡片', value: '$draftCards'),
              _MetricCard(title: '待复习卡片', value: '$dueCards'),
              _MetricCard(title: '今日完成', value: '${state.completedToday}'),
              _MetricCard(
                title: '内容待同步',
                value: '${state.pendingOperationCount}',
              ),
              _MetricCard(title: '本地临时卡片', value: '$localCards'),
            ],
          ),
          const SizedBox(height: 18),
          const _SectionHeader(
            title: '状态洞察',
            subtitle: '从复习负载、同步健康和本地草稿三个角度快速判断当前状态',
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool compact = constraints.maxWidth < 840;
              final double cardWidth = compact
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 24) / 3;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  SizedBox(
                    width: cardWidth,
                    child: _StatusSummaryCard(
                      icon: Icons.schedule_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      title: '复习负载',
                      valueLabel: '$dueCards / $totalCards',
                      subtitle: dueCards == 0
                          ? '当前没有到期卡片，可以继续补充新内容。'
                          : dueCards > 20
                          ? '待复习卡片较多，建议优先清理今日队列。'
                          : '复习压力适中，适合继续推进今日任务。',
                      progress: dueRatio,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _StatusSummaryCard(
                      icon: Icons.sync_outlined,
                      color: state.pendingOperationCount == 0
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.tertiary,
                      title: '同步健康',
                      valueLabel: state.pendingOperationCount == 0
                          ? '稳定'
                          : '${state.pendingOperationCount} 条待同步',
                      subtitle: state.pendingOperationCount == 0
                          ? '本地与远端状态一致，没有待补传的操作。'
                          : '存在待同步操作，网络恢复后会自动继续补传。',
                      progress: syncHealth,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _StatusSummaryCard(
                      icon: Icons.cloud_off_outlined,
                      color: localCards == 0
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondary,
                      title: '本地草稿占比',
                      valueLabel: '$localCards 张',
                      subtitle: localCards == 0
                          ? '当前没有本地临时卡片，数据一致性较好。'
                          : '存在尚未完全同步的本地卡片，可在网络恢复后检查。',
                      progress: localRatio,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool compact = constraints.maxWidth < 840;
              final double cardWidth = compact
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  SizedBox(
                    width: cardWidth,
                    child: _StatusSummaryCard(
                      icon: Icons.school_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      title: '背诵覆盖',
                      valueLabel: '$studyCards / $totalCards',
                      subtitle: draftCards == 0
                          ? '所有卡片都已加入背诵队列。'
                          : '还有 $draftCards 张草稿未加入背诵，可以先检查内容再启用。',
                      progress: studyRatio,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _NextDueCard(nextDueAt: nextDueAt),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          const _SectionHeader(
            title: '未来 7 天',
            subtitle: '按到期日期预估近期复习负载，方便提前判断压力。',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  for (final _UpcomingLoad load in upcomingLoads)
                    _UpcomingLoadRow(load: load),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _SectionHeader(
            title: '牌组分布',
            subtitle: '优先处理待复习数量高的牌组，避免积压集中爆发。',
          ),
          if (deckDueSummaries.isEmpty)
            const _InfoPanel(
              icon: Icons.inbox_outlined,
              title: '暂无卡片分布',
              subtitle: '创建卡片并加入背诵后，这里会显示各牌组的复习负载。',
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    for (final _DeckDueSummary summary in deckDueSummaries.take(
                      6,
                    ))
                      _DeckDueRow(summary: summary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeckDueSummary {
  const _DeckDueSummary({
    required this.deck,
    required this.dueCount,
    required this.cardCount,
  });

  final DeckModel deck;
  final int dueCount;
  final int cardCount;
}

class _UpcomingLoad {
  const _UpcomingLoad({
    required this.day,
    required this.label,
    required this.count,
    required this.maxCount,
  });

  final DateTime day;
  final String label;
  final int count;
  final int maxCount;
}

List<_UpcomingLoad> _buildUpcomingLoads(List<CardModel> cards, DateTime now) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final List<int> counts = List<int>.filled(7, 0);
  for (final CardModel card in cards) {
    if (!card.studyEnabled) {
      continue;
    }
    final DateTime due = card.state.dueDate.toLocal();
    final DateTime dueDay = DateTime(due.year, due.month, due.day);
    final int offset = dueDay.difference(today).inDays;
    if (offset < 0 || offset >= counts.length) {
      continue;
    }
    counts[offset] += 1;
  }
  final int maxCount = counts.fold<int>(
    1,
    (int current, int value) => value > current ? value : current,
  );
  return <_UpcomingLoad>[
    for (int index = 0; index < counts.length; index += 1)
      _UpcomingLoad(
        day: today.add(Duration(days: index)),
        label: index == 0
            ? '今天'
            : index == 1
            ? '明天'
            : DateFormat('MM-dd').format(today.add(Duration(days: index))),
        count: counts[index],
        maxCount: maxCount,
      ),
  ];
}

class _NextDueCard extends StatelessWidget {
  const _NextDueCard({required this.nextDueAt});

  final DateTime? nextDueAt;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.event_available_outlined,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('下一张到期', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    nextDueAt == null ? '暂无未来到期卡片' : _formatDateTime(nextDueAt),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingLoadRow extends StatelessWidget {
  const _UpcomingLoadRow({required this.load});

  final _UpcomingLoad load;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double progress = load.maxCount == 0 ? 0 : load.count / load.maxCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          SizedBox(width: 54, child: Text(load.label)),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(
              '${load.count}',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckDueRow extends StatelessWidget {
  const _DeckDueRow({required this.summary});

  final _DeckDueSummary summary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double progress = summary.cardCount == 0
        ? 0
        : summary.dueCount / summary.cardCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _parseDeckColor(
                summary.deck.colorHex,
                theme,
              ).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _deckIconFor(summary.deck.icon),
              size: 19,
              color: _parseDeckColor(summary.deck.colorHex, theme),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(summary.deck.name, style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${summary.dueCount}/${summary.cardCount}',
            style: theme.textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: AppPageScrollView(
        maxWidth: 920,
        children: <Widget>[
          const _HeroPanel(
            title: '设置与同步',
            subtitle: '统一查看同步状态、AI 配置能力和本地账号会话。',
          ),
          Card(
            child: ListTile(
              title: const Text('立即同步'),
              subtitle: Text(
                state.lastSyncAt == null
                    ? '尚未完成同步'
                    : '上次同步：${_formatDateTime(state.lastSyncAt)}',
              ),
              trailing: const Icon(Icons.sync),
              onTap: () =>
                  ref.read(appStoreProvider.notifier).refreshRemoteData(),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('导入 Card DSL'),
              subtitle: const Text('粘贴 @card ... @end 格式文本并批量生成卡片'),
              trailing: const Icon(Icons.file_download_outlined),
              onTap: () => context.go('/import/dsl'),
            ),
          ),
          if (state.pendingOperations.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '待同步队列（${state.pendingOperations.length}）',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    for (final SyncOperation operation
                        in state.pendingOperations)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          leading: _PendingOperationAvatar(
                            operationType: operation.type,
                          ),
                          title: Text(_syncOperationTitle(operation.type)),
                          subtitle: Text(
                            '${_syncOperationSummary(operation)}\n${_formatDateTime(operation.occurredAt)}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Card(
            child: ListTile(
              title: Text(
                '退出登录',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: const Text('会清理本地 session 和缓存的牌组/卡片数据。'),
              trailing: Icon(Icons.logout, color: theme.colorScheme.error),
              onTap: () => ref.read(appStoreProvider.notifier).logout(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppBottomNav extends StatelessWidget {
  const _AppBottomNav({
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: '牌组',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: '复习',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class _AppNavigationRail extends StatelessWidget {
  const _AppNavigationRail({
    required this.extended,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final bool extended;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: NavigationRail(
        extended: extended,
        minWidth: 76,
        minExtendedWidth: 224,
        selectedIndex: currentIndex,
        labelType: extended ? null : NavigationRailLabelType.selected,
        groupAlignment: -0.72,
        useIndicator: true,
        onDestinationSelected: onDestinationSelected,
        leading: Padding(
          padding: EdgeInsets.fromLTRB(extended ? 18 : 12, 18, 12, 28),
          child: extended
              ? Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppDesign.radiusMd),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(
                            AppDesign.radiusSm,
                          ),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.auto_stories_outlined,
                          color: theme.colorScheme.onSurface,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text('Ank', style: theme.textTheme.titleMedium),
                          Text(
                            'Workspace',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppDesign.radiusMd),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.auto_stories_outlined,
                    color: theme.colorScheme.onSurface,
                    size: 20,
                  ),
                ),
        ),
        destinations: const <NavigationRailDestination>[
          NavigationRailDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: Text('牌组'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: Text('复习'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: Text('统计'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: Text('设置'),
          ),
        ],
      ),
    );
  }
}

bool _showsPrimaryTabBar(String location) {
  return const <String>{'/', '/stats', '/settings'}.contains(location);
}

class _ReviewRatingButton extends StatelessWidget {
  const _ReviewRatingButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onPressed,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Tooltip(
      message: '$label：$description',
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.08),
          disabledForegroundColor: color.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          minimumSize: const Size.fromHeight(64),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withValues(alpha: 0.18)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  )
                : Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color.withValues(alpha: 0.86),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DeckCardKind { basic, singleChoice, multiChoice, cloze }

class _DeckCardListItem extends StatelessWidget {
  const _DeckCardListItem({
    required this.card,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.onToggleStudyEnabled,
  });

  final CardModel card;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onToggleStudyEnabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isLocalDraft = card.id.startsWith('local_');
    final _DeckCardKind kind = _deckCardKindFor(card);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDesign.radiusSm),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.16)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _DeckCardLeadingIndicator(
                selectionMode: selectionMode,
                selected: selected,
                isLocalDraft: isLocalDraft,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _deckCardListTitle(card),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (kind != _DeckCardKind.basic) ...<Widget>[
                      const SizedBox(width: 8),
                      _DeckCardTypeBadge(kind: kind),
                    ],
                    if (isLocalDraft && !selectionMode) ...<Widget>[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 15,
                        color: theme.colorScheme.tertiary,
                      ),
                    ],
                    if (!selectionMode) ...<Widget>[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: card.studyEnabled ? '移出背诵' : '加入背诵',
                        child: InkResponse(
                          onTap: onToggleStudyEnabled,
                          radius: 20,
                          child: Icon(
                            card.studyEnabled
                                ? Icons.bookmark_added_outlined
                                : Icons.bookmark_add_outlined,
                            size: 18,
                            color: card.studyEnabled
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.76,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckCardLeadingIndicator extends StatelessWidget {
  const _DeckCardLeadingIndicator({
    required this.selectionMode,
    required this.selected,
    required this.isLocalDraft,
  });

  final bool selectionMode;
  final bool selected;
  final bool isLocalDraft;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (selectionMode) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 0 : 1.6,
          ),
        ),
        alignment: Alignment.center,
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: 15,
                color: theme.colorScheme.onPrimary,
              )
            : null,
      );
    }

    final Color background = isLocalDraft
        ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.72)
        : theme.colorScheme.surfaceContainer;
    final Color foreground = isLocalDraft
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      alignment: Alignment.center,
      child: Icon(
        isLocalDraft ? Icons.cloud_off_outlined : Icons.description_outlined,
        size: 13,
        color: foreground,
      ),
    );
  }
}

class _DeckCardTypeBadge extends StatelessWidget {
  const _DeckCardTypeBadge({required this.kind});

  final _DeckCardKind kind;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color background = switch (kind) {
      _DeckCardKind.singleChoice => theme.colorScheme.primaryContainer,
      _DeckCardKind.multiChoice => theme.colorScheme.tertiaryContainer,
      _DeckCardKind.cloze => theme.colorScheme.secondaryContainer,
      _DeckCardKind.basic => theme.colorScheme.surfaceContainerHighest,
    };
    final Color foreground = switch (kind) {
      _DeckCardKind.singleChoice => theme.colorScheme.onPrimaryContainer,
      _DeckCardKind.multiChoice => theme.colorScheme.onTertiaryContainer,
      _DeckCardKind.cloze => theme.colorScheme.onSecondaryContainer,
      _DeckCardKind.basic => theme.colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        _deckCardKindLabel(kind),
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w500,
          height: 1,
        ),
      ),
    );
  }
}

class _PendingOperationAvatar extends StatelessWidget {
  const _PendingOperationAvatar({required this.operationType});

  final String operationType;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final IconData icon = switch (operationType) {
      'create_card' => Icons.add_circle_outline,
      'update_card' => Icons.edit_outlined,
      'delete_card' => Icons.delete_outline,
      'submit_review' => Icons.task_alt_outlined,
      _ => Icons.sync_outlined,
    };
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 18),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusSummaryCard extends StatelessWidget {
  const _StatusSummaryCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.valueLabel,
    required this.subtitle,
    required this.progress,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String valueLabel;
  final String subtitle;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double normalized = progress.clamp(0, 1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppDesign.radiusSm),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        valueLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: normalized,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.tertiaryActionLabel,
    this.onTertiaryAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryActionLabel;
  final VoidCallback onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final String? tertiaryActionLabel;
  final VoidCallback? onTertiaryAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(AppDesign.radiusLg),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: <Widget>[
                FilledButton(
                  onPressed: onPrimaryAction,
                  child: Text(primaryActionLabel),
                ),
                if (secondaryActionLabel != null && onSecondaryAction != null)
                  OutlinedButton(
                    onPressed: onSecondaryAction,
                    child: Text(secondaryActionLabel!),
                  ),
                if (tertiaryActionLabel != null && onTertiaryAction != null)
                  TextButton(
                    onPressed: onTertiaryAction,
                    child: Text(tertiaryActionLabel!),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(height: 16),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _HomeOverviewStrip extends StatelessWidget {
  const _HomeOverviewStrip({
    required this.deckCount,
    required this.cardCount,
    required this.dueCount,
    required this.onCreateDeck,
    required this.onStartReview,
    required this.onImportDsl,
  });

  final int deckCount;
  final int cardCount;
  final int dueCount;
  final VoidCallback onCreateDeck;
  final VoidCallback? onStartReview;
  final VoidCallback onImportDsl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _HomeOverviewMetric(
                icon: Icons.dashboard_outlined,
                label: '牌组',
                value: '$deckCount',
              ),
              _HomeOverviewMetric(
                icon: Icons.style_outlined,
                label: '卡片',
                value: '$cardCount',
              ),
              _HomeOverviewMetric(
                icon: Icons.schedule_outlined,
                label: '待复习',
                value: '$dueCount',
                emphasized: dueCount > 0,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: onCreateDeck,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('新建牌组'),
              ),
              OutlinedButton.icon(
                onPressed: onStartReview,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                icon: const Icon(Icons.play_arrow_outlined, size: 18),
                label: const Text('开始复习'),
              ),
              TextButton.icon(
                onPressed: onImportDsl,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('导入 DSL'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeOverviewMetric extends StatelessWidget {
  const _HomeOverviewMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color background = emphasized
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerLow;
    final Color foreground = emphasized
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface;
    final Color iconColor = emphasized
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: emphasized
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color resolvedTint = tint ?? theme.colorScheme.primary;
    return Card(
      child: ListTile(
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: resolvedTint.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppDesign.radiusSm),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Icon(icon, color: resolvedTint, size: 18),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.58 : 0.8,
        ),
        borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.color, this.foregroundColor});

  final String label;
  final Color? color;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color resolvedBackground =
        color ?? theme.colorScheme.surfaceContainerHighest;
    final Color resolvedForeground =
        foregroundColor ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: resolvedForeground,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _DeckPageHeader extends StatelessWidget {
  const _DeckPageHeader({
    required this.deck,
    required this.cardCount,
    required this.dueCount,
    required this.matchedCount,
  });

  final DeckModel deck;
  final int cardCount;
  final int dueCount;
  final int matchedCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color deckColor = _parseDeckColor(deck.colorHex, theme);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: deckColor.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.2 : 0.1,
                  ),
                  borderRadius: BorderRadius.circular(AppDesign.radiusLg),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                alignment: Alignment.center,
                child: Icon(_deckIconFor(deck.icon), color: deckColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      deck.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (deck.description.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        deck.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _MetaChip(label: '$cardCount 张卡片'),
              _MetaChip(label: '待复习 $dueCount'),
              _MetaChip(label: '当前显示 $matchedCount'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeckDatabaseHeader extends StatelessWidget {
  const _DeckDatabaseHeader({
    required this.countLabel,
    required this.selectionLabel,
  });

  final String countLabel;
  final String selectionLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.view_list_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '卡片数据库',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '$countLabel · $selectionLabel',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderDeckSection extends ConsumerWidget {
  const _FolderDeckSection({
    required this.folder,
    required this.decks,
    required this.dueCount,
    required this.onEdit,
    required this.onCreateDeck,
  });

  final FolderModel folder;
  final List<DeckModel> decks;
  final int dueCount;
  final VoidCallback onEdit;
  final VoidCallback onCreateDeck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppState state = ref.watch(appStoreProvider);
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppDesign.radiusSm),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.folder_copy_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(folder.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _MetaChip(label: '牌组 ${decks.length}'),
                          _MetaChip(label: '待复习 $dueCount'),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.more_horiz_rounded),
                  tooltip: '文件夹设置',
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (decks.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppDesign.radiusMd),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '这个文件夹里还没有牌组，可以直接在这里创建一个。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: onCreateDeck,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新建牌组'),
                    ),
                  ],
                ),
              )
            else ...<Widget>[
              for (final DeckModel deck in decks)
                _DeckSummaryCard(
                  deck: deck,
                  cardCount: state.cardCountForDeck(deck.id),
                  dueCount: state.dueCountForDeck(deck.id),
                  onTap: () => context.go('/deck/${deck.id}'),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onCreateDeck,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('在该文件夹中创建牌组'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeckSummaryCard extends StatelessWidget {
  const _DeckSummaryCard({
    required this.deck,
    required this.cardCount,
    required this.dueCount,
    required this.onTap,
  });

  final DeckModel deck;
  final int cardCount;
  final int dueCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color deckColor = _parseDeckColor(deck.colorHex, theme);
    return Card(
      child: Semantics(
        button: true,
        label: deck.name,
        hint: '打开牌组',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDesign.radiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: deckColor.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.1,
                    ),
                    borderRadius: BorderRadius.circular(AppDesign.radiusSm),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _deckIconFor(deck.icon),
                    color: deckColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(deck.name, style: theme.textTheme.titleMedium),
                      if (deck.description.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(
                          deck.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _MetaChip(label: '$cardCount 张卡片'),
                          _MetaChip(
                            label: '待复习 $dueCount',
                            color: deckColor.withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.24
                                  : 0.12,
                            ),
                            foregroundColor: deckColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeckIconChoiceChip extends StatelessWidget {
  const _DeckIconChoiceChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 18,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckColorChoice extends StatelessWidget {
  const _DeckColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? theme.colorScheme.onSurface : color,
            width: selected ? 2.6 : 1.2,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: 0.24),
              blurRadius: selected ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: selected
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

class _SectionBadge extends StatelessWidget {
  const _SectionBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.56 : 0.82,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _MiniFeatureChip extends StatelessWidget {
  const _MiniFeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.56 : 0.82,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '尚未同步';
  }
  return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final double kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

String _deckCardListTitle(CardModel card) {
  final List<String> candidates = <String>[
    card.title,
    firstNonEmptyLine(card.prompt) ?? '',
    CardDocumentCodec.promptPreview(card.content),
  ];
  for (final String candidate in candidates) {
    final String resolved = dslToPlainText(candidate).trim();
    if (resolved.isNotEmpty) {
      return resolved;
    }
  }
  return '未命名卡片';
}

_DeckCardKind _deckCardKindFor(CardModel card) {
  final String prompt = card.prompt;
  if (prompt.contains('{multi-choice}')) {
    return _DeckCardKind.multiChoice;
  }
  if (prompt.contains('{single-choice}')) {
    return _DeckCardKind.singleChoice;
  }
  if (RegExp(r'\{\{[^}]+\}\}|___\([^)]*\)___|_{3,}').hasMatch(prompt)) {
    return _DeckCardKind.cloze;
  }
  return _DeckCardKind.basic;
}

String _deckCardKindLabel(_DeckCardKind kind) {
  switch (kind) {
    case _DeckCardKind.basic:
      return '普通';
    case _DeckCardKind.singleChoice:
      return '单选';
    case _DeckCardKind.multiChoice:
      return '多选';
    case _DeckCardKind.cloze:
      return '填空';
  }
}

const List<_DeckIconChoice> _deckIconChoices = <_DeckIconChoice>[
  _DeckIconChoice(raw: 'book', label: '课程'),
  _DeckIconChoice(raw: 'brain', label: '记忆'),
  _DeckIconChoice(raw: 'globe', label: '语言'),
  _DeckIconChoice(raw: 'note', label: '笔记'),
  _DeckIconChoice(raw: 'idea', label: '概念'),
  _DeckIconChoice(raw: 'target', label: '考试'),
  _DeckIconChoice(raw: 'science', label: '科学'),
];

const List<String> _deckColorChoices = <String>[
  '#4ECDC4',
  '#5B8DEF',
  '#8B5CF6',
  '#F59E0B',
  '#EF6C8F',
  '#0F9D7A',
  '#F97316',
  '#6B7280',
];

String _syncOperationTitle(String type) {
  switch (type) {
    case 'create_card':
      return '待创建卡片';
    case 'update_card':
      return '待更新卡片';
    case 'delete_card':
      return '待删除卡片';
    case 'submit_review':
      return '旧版待同步复习结果';
    default:
      return '待同步操作';
  }
}

String _syncOperationSummary(SyncOperation operation) {
  switch (operation.type) {
    case 'create_card':
      return '网络恢复后会自动创建并补传内容。';
    case 'update_card':
      return '本地修改已保存，稍后将自动同步到服务端。';
    case 'delete_card':
      return '待从服务端删除对应卡片。';
    case 'submit_review':
      return '旧版本地评分记录，建议联网后重新确认复习状态。';
    default:
      return '等待网络恢复后自动处理。';
  }
}

class _DeckIconChoice {
  const _DeckIconChoice({required this.raw, required this.label});

  final String raw;
  final String label;
}

Color _parseDeckColor(String colorHex, ThemeData theme) {
  final String hex = colorHex.trim().replaceFirst('#', '');
  if (hex.length != 6 && hex.length != 8) {
    return theme.colorScheme.primary;
  }
  final String normalized = hex.length == 6 ? 'FF$hex' : hex;
  final int? value = int.tryParse(normalized, radix: 16);
  if (value == null) {
    return theme.colorScheme.primary;
  }
  return Color(value);
}

String _normalizeDeckColorChoice(String colorHex) {
  final String hex = colorHex.trim().replaceFirst('#', '').toUpperCase();
  if (hex.length != 6) {
    return _deckColorChoices.first;
  }
  final String normalized = '#$hex';
  for (final String candidate in _deckColorChoices) {
    if (candidate.toUpperCase() == normalized) {
      return candidate;
    }
  }
  return _deckColorChoices.first;
}

IconData _deckIconFor(String raw) {
  switch (raw.trim()) {
    case '📚':
    case 'book':
      return Icons.auto_stories_outlined;
    case '🧠':
    case 'brain':
      return Icons.psychology_alt_outlined;
    case '🌍':
    case 'globe':
      return Icons.public_outlined;
    case '📝':
    case 'note':
      return Icons.edit_note_outlined;
    case '💡':
    case 'idea':
      return Icons.lightbulb_outline;
    case '🎯':
    case 'target':
      return Icons.gps_fixed_outlined;
    case '🧪':
    case 'science':
      return Icons.science_outlined;
    default:
      return Icons.style_outlined;
  }
}

String _normalizeDeckIconChoice(String raw) {
  switch (raw.trim()) {
    case '📚':
    case 'book':
      return 'book';
    case '🧠':
    case 'brain':
      return 'brain';
    case '🌍':
    case 'globe':
      return 'globe';
    case '📝':
    case 'note':
      return 'note';
    case '💡':
    case 'idea':
      return 'idea';
    case '🎯':
    case 'target':
      return 'target';
    case '🧪':
    case 'science':
      return 'science';
    default:
      return _deckIconChoices.first.raw;
  }
}

class _AuthTab extends StatelessWidget {
  const _AuthTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
