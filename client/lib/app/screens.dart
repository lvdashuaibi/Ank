import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'layout/responsive_layout.dart';
import 'card_dsl/dsl_plaintext.dart';
import 'card_dsl/dsl_view.dart';
import '../core/app_store.dart';
import '../core/card_document.dart';

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
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.6),
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
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              scheme.primaryContainer.withValues(alpha: isDark ? 0.34 : 0.78),
              scheme.secondaryContainer.withValues(alpha: isDark ? 0.26 : 0.6),
              scheme.surface,
            ],
          ),
        ),
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
                                      fontWeight: FontWeight.w800,
                                      height: 1.1,
                                    ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '支持正式登录、PostgreSQL 持久化、离线同步队列与 AI 草稿生成。你可以从 Web、macOS 和 iPhone 模拟器无缝体验同一套数据。',
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
                                icon: Icons.offline_bolt_outlined,
                                label: '离线可用',
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
                              _StatBadge(label: '同步', value: '在线/离线'),
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
    Future<void> openCreateDeck() async {
      final String? deckId = await showAdaptiveSheet<String>(
        context: context,
        maxWidth: 720,
        isScrollControlled: true,
        builder: (BuildContext context) {
          return const _CreateDeckSheet();
        },
      );
      if (!context.mounted || deckId == null || deckId.isEmpty) {
        return;
      }
      context.go('/deck/$deckId');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ank 学习空间'),
        actions: <Widget>[
          IconButton(
            onPressed: openCreateDeck,
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
              subtitle: '客户端会自动推送离线队列并拉取最新卡片快照。',
            ),
          if (state.pendingOperationCount > 0)
            _InfoPanel(
              icon: Icons.sync_problem_outlined,
              title: '待同步操作 ${state.pendingOperationCount} 条',
              subtitle: '网络恢复后会自动补传，也可以在设置页手动触发同步。',
            ),
          const SizedBox(height: 12),
          const _SectionHeader(title: '你的牌组', subtitle: '按牌组管理卡片、复习节奏和同步状态'),
          if (state.decks.isEmpty)
            _EmptyStateCard(
              icon: Icons.layers_clear_outlined,
              title: '还没有可用牌组',
              subtitle: '先创建一个牌组开始整理内容；如果你已有结构化文本，也可以直接导入 DSL。',
              primaryActionLabel: '创建牌组',
              onPrimaryAction: openCreateDeck,
              secondaryActionLabel: '导入 DSL',
              onSecondaryAction: () => context.go('/import/dsl'),
            )
          else
            for (final DeckModel deck in state.decks)
              _DeckSummaryCard(
                deck: deck,
                cardCount: state.cardCountForDeck(deck.id),
                dueCount: state.dueCountForDeck(deck.id),
                onTap: () => context.go('/deck/${deck.id}'),
              ),
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
        maxWidth: 1120,
        children: <Widget>[
          _HeroPanel(
            title: deck.name,
            subtitle: deck.description,
            trailing: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _StatBadge(
                  label: '卡片',
                  value: '${state.cardCountForDeck(widget.deckId)}',
                ),
                _StatBadge(
                  label: '待复习',
                  value: '${state.dueCountForDeck(widget.deckId)}',
                ),
                _StatBadge(label: '命中', value: '${cards.length}'),
              ],
            ),
          ),
          const SizedBox(height: 8),
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
            )
          else
            for (final CardModel card in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _DeckCardListItem(
                  card: card,
                  selectionMode: selectionMode,
                  selected: _selectedCardIds.contains(card.id),
                  onLongPress: () => _toggleSelection(card.id),
                  onTap: () {
                    if (selectionMode) {
                      _toggleSelection(card.id);
                    } else {
                      context.go('/deck/${widget.deckId}/card/${card.id}/edit');
                    }
                  },
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
}

enum _DeckSheetResult { saved, deleted }

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
    final ThemeData theme = Theme.of(context);
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

class _CreateDeckSheet extends ConsumerStatefulWidget {
  const _CreateDeckSheet();

  @override
  ConsumerState<_CreateDeckSheet> createState() => _CreateDeckSheetState();
}

class _CreateDeckSheetState extends ConsumerState<_CreateDeckSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedIcon = _deckIconChoices.first.raw;
  String _selectedColor = _deckColorChoices.first;
  bool _submitting = false;
  String? _inlineError;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color deckColor = _parseDeckColor(_selectedColor, theme);
    final String previewName = _nameController.text.trim().isEmpty
        ? '新牌组'
        : _nameController.text.trim();
    final String previewDescription = _descriptionController.text.trim().isEmpty
        ? '把同一主题的卡片整理到这里，后续可以继续补卡和复习。'
        : _descriptionController.text.trim();

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
                                children: const <Widget>[
                                  _MetaChip(label: '新卡/天 20'),
                                  _MetaChip(label: '最大复习 200'),
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
  List<String> _sessionQueueCardIds = <String>[];

  @override
  Widget build(BuildContext context) {
    final AppState state = ref.watch(appStoreProvider);
    final List<CardModel> plannedQueue = state.dueCards(deckId: widget.deckId);
    if (_sessionDeckId != widget.deckId) {
      _sessionDeckId = widget.deckId;
      _sessionTotal = 0;
      _sessionQueueCardIds = <String>[];
      _activeCardId = null;
      _revealed = false;
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
    final bool hasInteractive = dslHasInteractiveContent(currentCard.prompt);
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
                    front: currentCard.prompt,
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
                ? Row(
                    key: const ValueKey<String>('rating-row'),
                    children: <Widget>[
                      for (
                        int index = 0;
                        index < ReviewRating.values.length;
                        index += 1
                      ) ...<Widget>[
                        Expanded(
                          child: _ReviewRatingButton(
                            icon: _iconFor(ReviewRating.values[index]),
                            label: _labelFor(ReviewRating.values[index]),
                            hint: _hintFor(ReviewRating.values[index]),
                            color: _ratingColor(
                              context,
                              ReviewRating.values[index],
                            ),
                            onPressed: () => _submit(
                              ReviewRating.values[index],
                              currentCard.id,
                            ),
                          ),
                        ),
                        if (index != ReviewRating.values.length - 1)
                          const SizedBox(width: 8),
                      ],
                    ],
                  )
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
        return '重来';
      case ReviewRating.hard:
        return '困难';
      case ReviewRating.good:
        return '良好';
      case ReviewRating.easy:
        return '简单';
    }
  }

  String _hintFor(ReviewRating rating) {
    switch (rating) {
      case ReviewRating.again:
        return '完全没想起，需要尽快再看';
      case ReviewRating.hard:
        return '勉强想起，建议缩短间隔';
      case ReviewRating.good:
        return '正常回忆成功，按标准节奏推进';
      case ReviewRating.easy:
        return '非常轻松，可以拉长复习间隔';
    }
  }

  IconData _iconFor(ReviewRating rating) {
    switch (rating) {
      case ReviewRating.again:
        return Icons.refresh_rounded;
      case ReviewRating.hard:
        return Icons.trending_flat_rounded;
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

  Future<void> _submit(ReviewRating rating, String cardId) async {
    await ref
        .read(appStoreProvider.notifier)
        .submitReview(cardId: cardId, rating: rating);
    if (!mounted) return;
    setState(() {
      _revealed = false;
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
    final double dueRatio = totalCards == 0 ? 0 : dueCards / totalCards;
    final double localRatio = totalCards == 0 ? 0 : localCards / totalCards;
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
            subtitle: '从复习进度、离线同步和本地临时数据三个维度观察当前状态。',
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
              _MetricCard(title: '待复习卡片', value: '$dueCards'),
              _MetricCard(title: '今日完成', value: '${state.completedToday}'),
              _MetricCard(
                title: '离线待同步',
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
    return NavigationBar(
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
      color: theme.colorScheme.surface,
      child: NavigationRail(
        extended: extended,
        minWidth: 84,
        minExtendedWidth: 200,
        selectedIndex: currentIndex,
        labelType: extended ? null : NavigationRailLabelType.selected,
        groupAlignment: -0.78,
        useIndicator: true,
        onDestinationSelected: onDestinationSelected,
        leading: Padding(
          padding: EdgeInsets.fromLTRB(extended ? 24 : 14, 20, 14, 24),
          child: extended
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.auto_stories_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Ank',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                )
              : Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.auto_stories_outlined,
                    color: theme.colorScheme.primary,
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
  return const <String>{
    '/',
    '/review',
    '/stats',
    '/settings',
  }.contains(location);
}

class _ReviewRatingButton extends StatelessWidget {
  const _ReviewRatingButton({
    required this.icon,
    required this.label,
    required this.hint,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String hint;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Tooltip(
      message: hint,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.08),
          disabledForegroundColor: color.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withValues(alpha: 0.18)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
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
  });

  final CardModel card;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isLocalDraft = card.id.startsWith('local_');
    final _DeckCardKind kind = _deckCardKindFor(card);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.34)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
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
                          fontWeight: FontWeight.w700,
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
        : theme.colorScheme.surfaceContainerHighest;
    final Color foreground = isLocalDraft
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
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
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _deckCardKindLabel(kind),
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
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
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: theme.colorScheme.primary),
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
          padding: const EdgeInsets.all(18),
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
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryActionLabel;
  final VoidCallback onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
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
    final Color titleColor = theme.colorScheme.onSurface;
    final Color subtitleColor = theme.colorScheme.onSurface.withValues(
      alpha: 0.76,
    );
    return Container(
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
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(color: subtitleColor),
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
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
              FilledButton.tonalIcon(
                onPressed: onStartReview,
                style: FilledButton.styleFrom(
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
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surface;
    final Color foreground = emphasized
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    final Color iconColor = emphasized
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
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
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: emphasized
                  ? foreground.withValues(alpha: 0.84)
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
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
          Text(title, style: Theme.of(context).textTheme.titleLarge),
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: resolvedTint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: resolvedTint),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.58 : 0.8,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: resolvedForeground.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: resolvedForeground,
          fontWeight: FontWeight.w700,
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
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: deckColor.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.28 : 0.14,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _deckIconFor(deck.icon),
                  color: deckColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(deck.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      deck.description,
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
      return '待同步复习结果';
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
      return '本次评分已离线保存，稍后将自动补交。';
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
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
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
