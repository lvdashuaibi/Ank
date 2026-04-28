import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'auth/session_store.dart';
import 'card_document.dart';
import 'database/local_cache.dart';
import 'fsrs_scheduler.dart';
import 'import/card_dsl_parser.dart';
import 'network/api_client.dart';

export 'fsrs_scheduler.dart' show FsrsScheduler, FsrsState, ReviewRating;

final StateNotifierProvider<AppStore, AppState> appStoreProvider =
    StateNotifierProvider<AppStore, AppState>((Ref ref) => AppStore());

class DeckModel {
  const DeckModel({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.colorHex,
    this.newCardsPerDay = 20,
    this.maxReviewsPerDay = 200,
  });

  final String id;
  final String name;
  final String description;
  final String icon;
  final String colorHex;
  final int newCardsPerDay;
  final int maxReviewsPerDay;

  factory DeckModel.fromJson(Map<String, dynamic> json) {
    return DeckModel(
      id: json['id'] as String,
      name: (json['name'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      icon: (json['icon'] ?? '📚') as String,
      colorHex: (json['color'] ?? '#4ECDC4') as String,
      newCardsPerDay: (json['new_cards_per_day'] as num?)?.toInt() ?? 20,
      maxReviewsPerDay: (json['max_reviews_per_day'] as num?)?.toInt() ?? 200,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'color': colorHex,
      'new_cards_per_day': newCardsPerDay,
      'max_reviews_per_day': maxReviewsPerDay,
    };
  }
}

class CardModel {
  const CardModel({
    required this.id,
    required this.clientId,
    required this.deckId,
    required this.title,
    required this.content,
    required this.tags,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.state,
  });

  final String id;
  final String clientId;
  final String deckId;
  final String title;
  final String content;
  final List<String> tags;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final FsrsState state;

  String get prompt => CardDocumentCodec.parse(content).prompt;
  String get answer => CardDocumentCodec.parse(content).answer;
  bool get hasAnswerLine => CardDocumentCodec.parse(content).hasAnswerLine;

  factory CardModel.fromJson(Map<String, dynamic> json) {
    final String content = (json['content'] ?? '') as String;
    final String legacyFront = (json['front'] ?? '') as String;
    final String legacyBack = (json['back'] ?? '') as String;
    final String resolvedContent = content.isNotEmpty
        ? content
        : CardDocumentCodec.compose(prompt: legacyFront, answer: legacyBack);
    final CardDocumentParts parts = CardDocumentCodec.parse(resolvedContent);
    return CardModel(
      id: json['id'] as String,
      clientId: (json['client_id'] ?? json['id'] ?? '') as String,
      deckId: json['deck_id'] as String,
      title: ((json['title'] as String?)?.isNotEmpty ?? false)
          ? json['title'] as String
          : (firstNonEmptyLine(parts.prompt) ?? ''),
      content: resolvedContent,
      tags: ((json['tags'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic item) => item.toString())
          .toList(),
      note: (json['note'] ?? '') as String,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
      state: FsrsState(
        state:
            (json['state']?['state'] as num?)?.toInt() ??
            (json['state'] as num?)?.toInt() ??
            0,
        difficulty: _doubleValue(json, const <String>[
          'state.difficulty',
          'difficulty',
        ]),
        stability: _doubleValue(json, const <String>[
          'state.stability',
          'stability',
        ]),
        retrievability: _doubleValue(json, const <String>[
          'state.retrievability',
          'retrievability',
        ]),
        dueDate:
            _parseDate(_nested(json, 'state.due_date') ?? json['due_date']) ??
            DateTime.now(),
        lastReviewAt: _parseDate(
          _nested(json, 'state.last_review_at') ?? json['last_review_at'],
        ),
        reps: _intValue(json, const <String>['state.reps', 'reps']),
        lapses: _intValue(json, const <String>['state.lapses', 'lapses']),
        elapsedDays: _doubleValue(json, const <String>[
          'state.elapsed_days',
          'elapsed_days',
        ]),
        scheduledDays: _doubleValue(json, const <String>[
          'state.scheduled_days',
          'scheduled_days',
        ]),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    final CardDocumentParts parts = CardDocumentCodec.parse(content);
    return <String, dynamic>{
      'id': id,
      'client_id': clientId,
      'deck_id': deckId,
      'title': title,
      'content': content,
      'front': parts.prompt,
      'back': parts.answer,
      'tags': tags,
      'note': note,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'state': <String, dynamic>{
        'state': state.state,
        'difficulty': state.difficulty,
        'stability': state.stability,
        'retrievability': state.retrievability,
        'due_date': state.dueDate.toIso8601String(),
        'last_review_at': state.lastReviewAt?.toIso8601String(),
        'reps': state.reps,
        'lapses': state.lapses,
        'elapsed_days': state.elapsedDays,
        'scheduled_days': state.scheduledDays,
      },
    };
  }
}

class SyncOperation {
  const SyncOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.occurredAt,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime occurredAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      'payload': payload,
      'occurred_at': occurredAt.toIso8601String(),
    };
  }

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    final dynamic payload = json['payload'];
    return SyncOperation(
      id: json['id'] as String,
      type: json['type'] as String,
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{},
      occurredAt: _parseDate(json['occurred_at']) ?? DateTime.now(),
    );
  }
}

class AIGeneratedCard {
  const AIGeneratedCard({
    required this.title,
    required this.content,
    required this.tags,
    required this.note,
  });

  final String title;
  final String content;
  final List<String> tags;
  final String note;

  factory AIGeneratedCard.fromJson(Map<String, dynamic> json) {
    final String content = (json['content'] ?? '') as String;
    final String legacyFront = (json['front'] ?? '') as String;
    final String legacyBack = (json['back'] ?? '') as String;
    final String resolvedContent = content.isNotEmpty
        ? content
        : CardDocumentCodec.compose(prompt: legacyFront, answer: legacyBack);
    final CardDocumentParts parts = CardDocumentCodec.parse(resolvedContent);
    return AIGeneratedCard(
      title: ((json['title'] as String?)?.isNotEmpty ?? false)
          ? json['title'] as String
          : (firstNonEmptyLine(parts.prompt) ?? ''),
      content: resolvedContent,
      tags: ((json['tags'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic item) => item.toString())
          .toList(),
      note: (json['note'] ?? '') as String,
    );
  }
}

class AppState {
  const AppState({
    required this.decks,
    required this.cards,
    required this.completedToday,
    required this.reviewedReviewTodayByDeck,
    required this.introducedNewTodayByDeck,
    required this.isBootstrapping,
    required this.syncInProgress,
    required this.pendingOperations,
    required this.generatedCards,
    this.accessToken,
    this.email,
    this.displayName,
    this.errorMessage,
    this.lastSyncAt,
    this.dailyProgressDayKey,
  });

  final List<DeckModel> decks;
  final List<CardModel> cards;
  final int completedToday;
  final Map<String, int> reviewedReviewTodayByDeck;
  final Map<String, int> introducedNewTodayByDeck;
  final bool isBootstrapping;
  final bool syncInProgress;
  final List<SyncOperation> pendingOperations;
  final List<AIGeneratedCard> generatedCards;
  final String? accessToken;
  final String? email;
  final String? displayName;
  final String? errorMessage;
  final DateTime? lastSyncAt;
  final String? dailyProgressDayKey;

  bool get isAuthenticated => accessToken != null && accessToken!.isNotEmpty;
  int get pendingOperationCount => pendingOperations.length;

  AppState copyWith({
    List<DeckModel>? decks,
    List<CardModel>? cards,
    int? completedToday,
    Map<String, int>? reviewedReviewTodayByDeck,
    Map<String, int>? introducedNewTodayByDeck,
    bool? isBootstrapping,
    bool? syncInProgress,
    List<SyncOperation>? pendingOperations,
    List<AIGeneratedCard>? generatedCards,
    String? accessToken,
    String? email,
    String? displayName,
    String? errorMessage,
    DateTime? lastSyncAt,
    String? dailyProgressDayKey,
    bool clearSession = false,
    bool clearError = false,
  }) {
    return AppState(
      decks: decks ?? this.decks,
      cards: cards ?? this.cards,
      completedToday: completedToday ?? this.completedToday,
      reviewedReviewTodayByDeck:
          reviewedReviewTodayByDeck ?? this.reviewedReviewTodayByDeck,
      introducedNewTodayByDeck:
          introducedNewTodayByDeck ?? this.introducedNewTodayByDeck,
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      syncInProgress: syncInProgress ?? this.syncInProgress,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      generatedCards: generatedCards ?? this.generatedCards,
      accessToken: clearSession ? null : accessToken ?? this.accessToken,
      email: clearSession ? null : email ?? this.email,
      displayName: clearSession ? null : displayName ?? this.displayName,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      dailyProgressDayKey: dailyProgressDayKey ?? this.dailyProgressDayKey,
    );
  }

  List<CardModel> cardsByDeck(String deckId) {
    return cards.where((CardModel card) => card.deckId == deckId).toList()
      ..sort((CardModel a, CardModel b) => a.createdAt.compareTo(b.createdAt));
  }

  List<CardModel> dueCards({String? deckId}) {
    final _DailyReviewProgress progress = _effectiveDailyProgress(this);
    return _buildDailyReviewQueue(
      decks: decks,
      cards: cards,
      deckId: deckId,
      reviewedReviewTodayByDeck: progress.reviewedReviewTodayByDeck,
      introducedNewTodayByDeck: progress.introducedNewTodayByDeck,
    );
  }

  int dueCountForDeck(String deckId) => dueCards(deckId: deckId).length;
  int cardCountForDeck(String deckId) => cardsByDeck(deckId).length;
}

class _DailyReviewProgress {
  const _DailyReviewProgress({
    required this.dayKey,
    required this.reviewedReviewTodayByDeck,
    required this.introducedNewTodayByDeck,
  });

  final String dayKey;
  final Map<String, int> reviewedReviewTodayByDeck;
  final Map<String, int> introducedNewTodayByDeck;
}

class _DeckQueueSelection {
  const _DeckQueueSelection({
    required this.learningCards,
    required this.reviewCards,
    required this.newCards,
  });

  final List<CardModel> learningCards;
  final List<CardModel> reviewCards;
  final List<CardModel> newCards;
}

_DailyReviewProgress _effectiveDailyProgress(AppState state) {
  final String todayKey = _todayKey();
  if (state.dailyProgressDayKey != todayKey) {
    return _DailyReviewProgress(
      dayKey: todayKey,
      reviewedReviewTodayByDeck: const <String, int>{},
      introducedNewTodayByDeck: const <String, int>{},
    );
  }
  return _DailyReviewProgress(
    dayKey: state.dailyProgressDayKey ?? todayKey,
    reviewedReviewTodayByDeck: state.reviewedReviewTodayByDeck,
    introducedNewTodayByDeck: state.introducedNewTodayByDeck,
  );
}

List<CardModel> _buildDailyReviewQueue({
  required List<DeckModel> decks,
  required List<CardModel> cards,
  required Map<String, int> reviewedReviewTodayByDeck,
  required Map<String, int> introducedNewTodayByDeck,
  String? deckId,
}) {
  final Map<String, DeckModel> deckById = <String, DeckModel>{
    for (final DeckModel deck in decks) deck.id: deck,
  };
  final Map<String, List<CardModel>> grouped = <String, List<CardModel>>{};
  for (final CardModel card in cards) {
    if (!card.state.isDue) {
      continue;
    }
    if (deckId != null && card.deckId != deckId) {
      continue;
    }
    grouped.putIfAbsent(card.deckId, () => <CardModel>[]).add(card);
  }

  final Iterable<String> deckIds = deckId == null
      ? grouped.keys
      : <String>[deckId];
  final List<CardModel> learningCards = <CardModel>[];
  final List<CardModel> reviewCards = <CardModel>[];
  final List<CardModel> newCards = <CardModel>[];

  for (final String currentDeckId in deckIds) {
    final List<CardModel> deckCards = grouped[currentDeckId] ?? <CardModel>[];
    if (deckCards.isEmpty) {
      continue;
    }
    final _DeckQueueSelection selection = _selectDeckQueue(
      deckCards: deckCards,
      deck: deckById[currentDeckId],
      reviewedReviewCount: reviewedReviewTodayByDeck[currentDeckId] ?? 0,
      introducedNewCount: introducedNewTodayByDeck[currentDeckId] ?? 0,
    );
    learningCards.addAll(selection.learningCards);
    reviewCards.addAll(selection.reviewCards);
    newCards.addAll(selection.newCards);
  }

  learningCards.sort(_compareReviewCardPriority);
  reviewCards.sort(_compareReviewCardPriority);
  newCards.sort(_compareNewCardPriority);
  return <CardModel>[...learningCards, ...reviewCards, ...newCards];
}

_DeckQueueSelection _selectDeckQueue({
  required List<CardModel> deckCards,
  required DeckModel? deck,
  required int reviewedReviewCount,
  required int introducedNewCount,
}) {
  final List<CardModel> learningCards =
      deckCards
          .where(
            (CardModel card) => card.state.state == 1 || card.state.state == 3,
          )
          .toList()
        ..sort(_compareReviewCardPriority);
  final List<CardModel> reviewCards =
      deckCards.where((CardModel card) => card.state.state == 2).toList()
        ..sort(_compareReviewCardPriority);
  final List<CardModel> newCards =
      deckCards.where((CardModel card) => card.state.state == 0).toList()
        ..sort(_compareNewCardPriority);

  final int maxReviewsPerDay = math.max(deck?.maxReviewsPerDay ?? 200, 0);
  final int newCardsPerDay = math.max(deck?.newCardsPerDay ?? 20, 0);
  final int remainingReviewSlots = math.max(
    maxReviewsPerDay - reviewedReviewCount,
    0,
  );
  final int remainingNewSlots = math.max(
    newCardsPerDay - introducedNewCount,
    0,
  );

  return _DeckQueueSelection(
    learningCards: learningCards,
    reviewCards: reviewCards.take(remainingReviewSlots).toList(),
    newCards: newCards.take(remainingNewSlots).toList(),
  );
}

int _compareReviewCardPriority(CardModel left, CardModel right) {
  final int dueCompare = left.state.dueDate.compareTo(right.state.dueDate);
  if (dueCompare != 0) {
    return dueCompare;
  }
  final int lastReviewCompare = (left.state.lastReviewAt ?? left.createdAt)
      .compareTo(right.state.lastReviewAt ?? right.createdAt);
  if (lastReviewCompare != 0) {
    return lastReviewCompare;
  }
  return left.createdAt.compareTo(right.createdAt);
}

int _compareNewCardPriority(CardModel left, CardModel right) {
  final int createdCompare = left.createdAt.compareTo(right.createdAt);
  if (createdCompare != 0) {
    return createdCompare;
  }
  return left.id.compareTo(right.id);
}

String _todayKey([DateTime? value]) {
  final DateTime now = value ?? DateTime.now();
  final DateTime local = now.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

class AppStore extends StateNotifier<AppState> {
  AppStore()
    : _apiClient = ApiClient(),
      _fsrsScheduler = const FsrsScheduler(),
      _sessionStore = SessionStore(),
      _localCache = LocalCache(),
      _uuid = const Uuid(),
      super(
        const AppState(
          decks: <DeckModel>[],
          cards: <CardModel>[],
          completedToday: 0,
          reviewedReviewTodayByDeck: <String, int>{},
          introducedNewTodayByDeck: <String, int>{},
          isBootstrapping: true,
          syncInProgress: false,
          pendingOperations: <SyncOperation>[],
          generatedCards: <AIGeneratedCard>[],
        ),
      ) {
    bootstrap();
  }

  final ApiClient _apiClient;
  final FsrsScheduler _fsrsScheduler;
  final SessionStore _sessionStore;
  final LocalCache _localCache;
  final Uuid _uuid;

  Map<String, dynamic> _buildCardPayload({
    required String clientId,
    required String title,
    required String content,
    required String note,
    required List<String> tags,
  }) {
    final CardDocumentParts parts = CardDocumentCodec.parse(content);
    return <String, dynamic>{
      'client_id': clientId,
      'title': title,
      'content': content,
      // Backward compatibility:
      // Some running backends still only persist `front` / `back`.
      // Sending both avoids creating blank cards when the server ignores
      // the newer `content` field.
      'front': parts.prompt,
      'back': parts.answer,
      'note': note,
      'tags': tags,
    };
  }

  Future<void> bootstrap() async {
    final List<Map<String, dynamic>> deckRows = await _localCache.loadDecks();
    final List<Map<String, dynamic>> cardRows = await _localCache.loadCards();
    final List<Map<String, dynamic>> operationRows = await _localCache
        .loadSyncOperations();
    final StoredSession? session = await _sessionStore.readSession();

    state = state.copyWith(
      decks: deckRows.map(DeckModel.fromJson).toList(),
      cards: cardRows.map(CardModel.fromJson).toList(),
      pendingOperations: operationRows.map(SyncOperation.fromJson).toList(),
      accessToken: session?.accessToken,
      email: session?.email,
      displayName: session?.displayName,
      isBootstrapping: false,
      clearError: true,
    );

    if (session != null) {
      await refreshRemoteData();
    }
  }

  void _ensureDailyProgressFresh() {
    final _DailyReviewProgress progress = _effectiveDailyProgress(state);
    if (state.dailyProgressDayKey == progress.dayKey) {
      return;
    }
    state = state.copyWith(
      completedToday: 0,
      reviewedReviewTodayByDeck: const <String, int>{},
      introducedNewTodayByDeck: const <String, int>{},
      dailyProgressDayKey: progress.dayKey,
    );
  }

  void _recordReviewProgress(CardModel cardBeforeReview) {
    final _DailyReviewProgress progress = _effectiveDailyProgress(state);
    final Map<String, int> reviewedReviewTodayByDeck = Map<String, int>.from(
      progress.reviewedReviewTodayByDeck,
    );
    final Map<String, int> introducedNewTodayByDeck = Map<String, int>.from(
      progress.introducedNewTodayByDeck,
    );

    if (cardBeforeReview.state.state == 2) {
      reviewedReviewTodayByDeck[cardBeforeReview.deckId] =
          (reviewedReviewTodayByDeck[cardBeforeReview.deckId] ?? 0) + 1;
    } else if (cardBeforeReview.state.state == 0) {
      introducedNewTodayByDeck[cardBeforeReview.deckId] =
          (introducedNewTodayByDeck[cardBeforeReview.deckId] ?? 0) + 1;
    }

    state = state.copyWith(
      completedToday: progress.dayKey == state.dailyProgressDayKey
          ? state.completedToday + 1
          : 1,
      reviewedReviewTodayByDeck: reviewedReviewTodayByDeck,
      introducedNewTodayByDeck: introducedNewTodayByDeck,
      dailyProgressDayKey: progress.dayKey,
    );
  }

  Future<String?> _ensureDeckByName({
    required String token,
    required String deckName,
  }) async {
    final String trimmed = deckName.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    for (final DeckModel deck in state.decks) {
      if (deck.name.trim() == trimmed) {
        return deck.id;
      }
    }
    final Map<String, dynamic> created = await _apiClient.createDeck(
      token: token,
      payload: <String, dynamic>{
        'name': trimmed,
        'description': 'Imported from Card DSL',
        'color': '#4ECDC4',
        'icon': '📥',
        'new_cards_per_day': 20,
        'max_reviews_per_day': 200,
      },
    );
    final DeckModel deck = DeckModel.fromJson(created);
    state = state.copyWith(decks: <DeckModel>[...state.decks, deck]);
    return deck.id;
  }

  Future<int> importCardDsl(String dslText) async {
    final String? token = state.accessToken;
    if (token == null || token.isEmpty) {
      state = state.copyWith(errorMessage: '请先登录后再导入卡片');
      return 0;
    }

    final CardDslParseResult result = CardDslParser.parseDocument(dslText);
    if (result.cards.isEmpty) {
      state = state.copyWith(
        errorMessage: result.errors.isEmpty
            ? '未识别到任何卡片（推荐使用 @answer ... @end；旧的 ---front--- / ---back--- 也兼容）'
            : result.errors.first,
      );
      return 0;
    }

    state = state.copyWith(syncInProgress: true, clearError: true);
    int imported = 0;
    try {
      for (final CardDslCard card in result.cards) {
        final String? deckId =
            await _ensureDeckByName(token: token, deckName: card.deckName) ??
            (state.decks.isNotEmpty ? state.decks.first.id : null);
        if (deckId == null) {
          continue;
        }
        final String note = card.note.isNotEmpty ? card.note : '';
        final bool ok = await createCard(
          deckId: deckId,
          title: card.front.split('\n').first.trim(),
          content: CardDocumentCodec.compose(
            prompt: card.front,
            answer: card.back,
          ),
          note: note,
          tags: card.tags,
        );
        if (ok) {
          imported++;
        }
      }
      await refreshRemoteData();
      state = state.copyWith(syncInProgress: false);
      return imported;
    } catch (error) {
      state = state.copyWith(
        syncInProgress: false,
        errorMessage: '导入失败：$error',
      );
      return imported;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = state.copyWith(isBootstrapping: true, clearError: true);
    try {
      final Map<String, dynamic> response = await _apiClient.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      await _saveSessionFromResponse(response);
      await refreshRemoteData();
      return true;
    } catch (error) {
      state = state.copyWith(
        isBootstrapping: false,
        errorMessage: '注册失败：$error',
      );
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isBootstrapping: true, clearError: true);
    try {
      final Map<String, dynamic> response = await _apiClient.login(
        email: email,
        password: password,
      );
      await _saveSessionFromResponse(response);
      await refreshRemoteData();
      return true;
    } catch (error) {
      state = state.copyWith(
        isBootstrapping: false,
        errorMessage: '登录失败：$error',
      );
      return false;
    }
  }

  Future<void> logout() async {
    await _sessionStore.clear();
    await _localCache.clearAll();
    state = const AppState(
      decks: <DeckModel>[],
      cards: <CardModel>[],
      completedToday: 0,
      reviewedReviewTodayByDeck: <String, int>{},
      introducedNewTodayByDeck: <String, int>{},
      isBootstrapping: false,
      syncInProgress: false,
      pendingOperations: <SyncOperation>[],
      generatedCards: <AIGeneratedCard>[],
    );
  }

  Future<void> refreshRemoteData() async {
    _ensureDailyProgressFresh();
    final String? token = state.accessToken;
    if (token == null || token.isEmpty) {
      return;
    }

    state = state.copyWith(
      isBootstrapping: true,
      syncInProgress: true,
      clearError: true,
    );

    try {
      await syncPendingOperations(token: token);
      List<Map<String, dynamic>> deckMaps;
      List<Map<String, dynamic>> cardMaps;

      try {
        final Map<String, dynamic> response = await _apiClient.syncPull(
          token: token,
        );
        if (!response.containsKey('decks') && !response.containsKey('cards')) {
          throw const FormatException('服务端未返回 decks/cards 数据');
        }
        deckMaps = _coerceMapList(response['decks']);
        cardMaps = _coerceMapList(response['cards']);
      } on FormatException {
        final _RemoteSnapshot snapshot = await _fetchRemoteSnapshotFallback(
          token,
        );
        deckMaps = snapshot.decks;
        cardMaps = snapshot.cards;
      }

      await _localCache.replaceDecks(deckMaps);
      await _localCache.replaceCards(cardMaps);
      final List<SyncOperation> pendingOperations =
          await _loadPendingOperations();

      state = state.copyWith(
        decks: deckMaps.map(DeckModel.fromJson).toList(),
        cards: cardMaps.map(CardModel.fromJson).toList(),
        isBootstrapping: false,
        syncInProgress: false,
        pendingOperations: pendingOperations,
        lastSyncAt: DateTime.now(),
        clearError: true,
      );
    } on DioException catch (error) {
      if (_isUnauthorized(error)) {
        await _expireSession(message: '登录已过期，请重新登录后同步');
        return;
      }
      state = state.copyWith(
        isBootstrapping: false,
        syncInProgress: false,
        errorMessage: '拉取远端数据失败：$error',
      );
    } catch (error) {
      state = state.copyWith(
        isBootstrapping: false,
        syncInProgress: false,
        errorMessage: '拉取远端数据失败：$error',
      );
    }
  }

  Future<_RemoteSnapshot> _fetchRemoteSnapshotFallback(String token) async {
    final List<Map<String, dynamic>> deckMaps = await _apiClient.listDecks(
      token,
    );
    final List<Map<String, dynamic>> cardMaps = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> deck in deckMaps) {
      final String deckId = (deck['id'] ?? '').toString();
      if (deckId.isEmpty) {
        continue;
      }
      final List<Map<String, dynamic>> cards = await _apiClient.listCards(
        token: token,
        deckId: deckId,
      );
      cardMaps.addAll(cards);
    }
    return _RemoteSnapshot(decks: deckMaps, cards: cardMaps);
  }

  Future<DeckModel?> createDeck({
    required String name,
    required String description,
    required String icon,
    required String colorHex,
    int newCardsPerDay = 20,
    int maxReviewsPerDay = 200,
  }) async {
    final String? token = state.accessToken;
    if (token == null || token.isEmpty) {
      state = state.copyWith(errorMessage: '请先登录后再创建牌组');
      return null;
    }

    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      state = state.copyWith(errorMessage: '请输入牌组名称');
      return null;
    }

    final String normalizedName = trimmedName.toLowerCase();
    final bool exists = state.decks.any(
      (DeckModel deck) => deck.name.trim().toLowerCase() == normalizedName,
    );
    if (exists) {
      state = state.copyWith(errorMessage: '已存在同名牌组，请换一个名称');
      return null;
    }

    try {
      final Map<String, dynamic> response = await _apiClient.createDeck(
        token: token,
        payload: <String, dynamic>{
          'name': trimmedName,
          'description': description.trim(),
          'color': colorHex,
          'icon': icon,
          'new_cards_per_day': newCardsPerDay,
          'max_reviews_per_day': maxReviewsPerDay,
        },
      );
      await _localCache.upsertDeck(response);
      final DeckModel created = DeckModel.fromJson(response);
      state = state.copyWith(
        decks: <DeckModel>[...state.decks, created],
        clearError: true,
      );
      return created;
    } on DioException catch (error) {
      if (_isUnauthorized(error)) {
        await _expireSession(message: '登录已过期，请重新登录后再创建牌组');
        return null;
      }
      final bool offline = _shouldQueueOffline(error);
      state = state.copyWith(
        errorMessage: offline ? '当前网络不可用，创建牌组需要联网后重试' : '创建牌组失败：$error',
      );
      return null;
    } catch (error) {
      state = state.copyWith(errorMessage: '创建牌组失败：$error');
      return null;
    }
  }

  Future<DeckModel?> updateDeck({
    required String deckId,
    required String name,
    required String description,
    required String icon,
    required String colorHex,
    required int newCardsPerDay,
    required int maxReviewsPerDay,
  }) async {
    final String? token = state.accessToken;
    if (token == null || token.isEmpty) {
      state = state.copyWith(errorMessage: '请先登录后再编辑牌组');
      return null;
    }

    final DeckModel? existingDeck = state.decks.cast<DeckModel?>().firstWhere(
      (DeckModel? item) => item?.id == deckId,
      orElse: () => null,
    );
    if (existingDeck == null) {
      state = state.copyWith(errorMessage: '未找到要编辑的牌组');
      return null;
    }

    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      state = state.copyWith(errorMessage: '请输入牌组名称');
      return null;
    }

    final String normalizedName = trimmedName.toLowerCase();
    final bool exists = state.decks.any(
      (DeckModel deck) =>
          deck.id != deckId && deck.name.trim().toLowerCase() == normalizedName,
    );
    if (exists) {
      state = state.copyWith(errorMessage: '已存在同名牌组，请换一个名称');
      return null;
    }

    final int resolvedNewCardsPerDay = math.max(1, newCardsPerDay);
    final int resolvedMaxReviewsPerDay = math.max(1, maxReviewsPerDay);

    try {
      final Map<String, dynamic> response = await _apiClient.updateDeck(
        token: token,
        deckId: deckId,
        payload: <String, dynamic>{
          'name': trimmedName,
          'description': description.trim(),
          'color': colorHex,
          'icon': icon,
          'new_cards_per_day': resolvedNewCardsPerDay,
          'max_reviews_per_day': resolvedMaxReviewsPerDay,
        },
      );
      await _localCache.upsertDeck(response);
      final DeckModel updated = DeckModel.fromJson(response);
      state = state.copyWith(
        decks: state.decks
            .map((DeckModel item) => item.id == deckId ? updated : item)
            .toList(),
        clearError: true,
      );
      return updated;
    } on DioException catch (error) {
      if (_isUnauthorized(error)) {
        await _expireSession(message: '登录已过期，请重新登录后再编辑牌组');
        return null;
      }
      final bool offline = _shouldQueueOffline(error);
      state = state.copyWith(
        errorMessage: offline ? '当前网络不可用，编辑牌组需要联网后重试' : '编辑牌组失败：$error',
      );
      return null;
    } catch (error) {
      state = state.copyWith(errorMessage: '编辑牌组失败：$error');
      return null;
    }
  }

  Future<bool> deleteDeck(String deckId) async {
    final String? token = state.accessToken;
    if (token == null || token.isEmpty) {
      state = state.copyWith(errorMessage: '请先登录后再删除牌组');
      return false;
    }

    final DeckModel? existingDeck = state.decks.cast<DeckModel?>().firstWhere(
      (DeckModel? item) => item?.id == deckId,
      orElse: () => null,
    );
    if (existingDeck == null) {
      state = state.copyWith(errorMessage: '未找到要删除的牌组');
      return false;
    }

    final List<DeckModel> remainingDecks = state.decks
        .where((DeckModel item) => item.id != deckId)
        .toList();
    final List<CardModel> removedCards = state.cards
        .where((CardModel item) => item.deckId == deckId)
        .toList();
    final List<CardModel> remainingCards = state.cards
        .where((CardModel item) => item.deckId != deckId)
        .toList();
    final Set<String> removedCardIds = removedCards
        .map((CardModel item) => item.id)
        .toSet();
    final Set<String> removedClientIds = removedCards
        .map((CardModel item) => item.clientId)
        .where((String item) => item.isNotEmpty)
        .toSet();
    final List<SyncOperation> pendingOperations =
        await _loadPendingOperations();
    final List<SyncOperation> nextOperations = pendingOperations.where((
      SyncOperation operation,
    ) {
      return !_operationReferencesDeck(
        operation,
        deckId: deckId,
        cardIds: removedCardIds,
        clientIds: removedClientIds,
      );
    }).toList();

    try {
      await _apiClient.deleteDeck(token: token, deckId: deckId);
      await _localCache.deleteDeck(deckId);
      await _localCache.deleteCardsByDeck(deckId);
      await _replacePendingOperations(nextOperations);
      state = state.copyWith(
        decks: remainingDecks,
        cards: remainingCards,
        clearError: true,
      );
      return true;
    } on DioException catch (error) {
      if (_isUnauthorized(error)) {
        await _expireSession(message: '登录已过期，请重新登录后再删除牌组');
        return false;
      }
      final bool offline = _shouldQueueOffline(error);
      state = state.copyWith(
        errorMessage: offline ? '当前网络不可用，删除牌组需要联网后重试' : '删除牌组失败：$error',
      );
      return false;
    } catch (error) {
      state = state.copyWith(errorMessage: '删除牌组失败：$error');
      return false;
    }
  }

  Future<bool> createCard({
    required String deckId,
    required String title,
    required String content,
    required String note,
    required List<String> tags,
  }) async {
    final String? token = state.accessToken;
    if (token == null || token.isEmpty) {
      state = state.copyWith(errorMessage: '请先登录后再创建卡片');
      return false;
    }

    final String clientId = _uuid.v4();
    try {
      final Map<String, dynamic> payload = _buildCardPayload(
        clientId: clientId,
        title: title,
        content: content,
        note: note,
        tags: tags,
      );
      final Map<String, dynamic> response = await _apiClient.createCard(
        token: token,
        deckId: deckId,
        payload: payload,
      );
      await _localCache.upsertCard(response);

      final CardModel card = CardModel.fromJson(response);
      state = state.copyWith(
        cards: <CardModel>[...state.cards, card],
        clearError: true,
      );
      return true;
    } on DioException catch (error) {
      if (_isUnauthorized(error)) {
        await _expireSession(message: '登录已过期，请重新登录后再创建卡片');
        return false;
      }
      if (!_shouldQueueOffline(error)) {
        state = state.copyWith(errorMessage: '创建卡片失败：$error');
        return false;
      }

      final SyncOperation operation = SyncOperation(
        id: _uuid.v4(),
        type: 'create_card',
        payload: <String, dynamic>{
          'deck_id': deckId,
          ..._buildCardPayload(
            clientId: clientId,
            title: title,
            content: content,
            note: note,
            tags: tags,
          ),
        },
        occurredAt: DateTime.now(),
      );
      await _queueOperation(operation);

      final CardModel localCard = CardModel(
        id: 'local_${operation.id}',
        clientId: clientId,
        deckId: deckId,
        title: title,
        content: content,
        tags: tags,
        note: note,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        state: FsrsState(dueDate: DateTime.now()),
      );
      await _localCache.upsertCard(localCard.toJson());
      state = state.copyWith(
        cards: <CardModel>[...state.cards, localCard],
        errorMessage: '网络不可用，已加入待同步队列',
      );
      return true;
    } catch (error) {
      state = state.copyWith(errorMessage: '创建卡片失败：$error');
      return false;
    }
  }

  Future<void> saveGeneratedCardsToDeck(String deckId) async {
    if (state.generatedCards.isEmpty) {
      return;
    }
    for (final AIGeneratedCard item in state.generatedCards) {
      await createCard(
        deckId: deckId,
        title: item.title,
        content: item.content,
        note: item.note,
        tags: item.tags,
      );
    }
    clearGeneratedCards();
  }

  Future<bool> updateCard({
    required String cardId,
    required String title,
    required String content,
    required String note,
    required List<String> tags,
  }) async {
    final String? token = state.accessToken;
    if (token == null || token.isEmpty) {
      state = state.copyWith(errorMessage: '请先登录后再编辑卡片');
      return false;
    }

    final CardModel? existingCard = state.cards.cast<CardModel?>().firstWhere(
      (CardModel? item) => item?.id == cardId,
      orElse: () => null,
    );
    final String clientId = existingCard?.clientId ?? cardId;

    final Map<String, dynamic> payload = _buildCardPayload(
      clientId: clientId,
      title: title,
      content: content,
      note: note,
      tags: tags,
    );

    final List<SyncOperation> pendingOperations =
        await _loadPendingOperations();
    final SyncOperation? pendingCreate = clientId.isEmpty
        ? null
        : _findPendingCreateOperation(
            operations: pendingOperations,
            clientId: clientId,
          );

    if (existingCard != null && pendingCreate != null) {
      final CardModel updatedLocalCard = CardModel(
        id: existingCard.id,
        clientId: existingCard.clientId,
        deckId: existingCard.deckId,
        title: title,
        content: content,
        tags: tags,
        note: note,
        createdAt: existingCard.createdAt,
        updatedAt: DateTime.now(),
        state: existingCard.state,
      );

      final List<SyncOperation> nextOperations = pendingOperations.map((
        SyncOperation item,
      ) {
        if (item.id != pendingCreate.id) {
          return item;
        }
        return SyncOperation(
          id: item.id,
          type: item.type,
          occurredAt: item.occurredAt,
          payload: <String, dynamic>{
            ...item.payload,
            'deck_id': existingCard.deckId,
            ...payload,
          },
        );
      }).toList();

      await _localCache.upsertCard(updatedLocalCard.toJson());
      await _replacePendingOperations(nextOperations);
      state = state.copyWith(
        cards: state.cards.map((CardModel item) {
          return item.id == cardId ? updatedLocalCard : item;
        }).toList(),
        errorMessage: '本地草稿已更新，待网络恢复后同步',
      );
      return true;
    }

    try {
      final Map<String, dynamic> response = await _apiClient.updateCard(
        token: token,
        cardId: cardId,
        payload: payload,
      );
      await _localCache.upsertCard(response);
      final CardModel updated = CardModel.fromJson(response);
      state = state.copyWith(
        cards: state.cards
            .map((CardModel item) => item.id == cardId ? updated : item)
            .toList(),
        clearError: true,
      );
      return true;
    } on DioException catch (error) {
      if (_isUnauthorized(error)) {
        await _expireSession(message: '登录已过期，请重新登录后再编辑卡片');
        return false;
      }
      if (!_shouldQueueOffline(error)) {
        state = state.copyWith(errorMessage: '编辑卡片失败：$error');
        return false;
      }

      CardModel? updatedLocalCard;
      await _queueOperation(
        SyncOperation(
          id: _uuid.v4(),
          type: 'update_card',
          payload: <String, dynamic>{'card_id': cardId, ...payload},
          occurredAt: DateTime.now(),
        ),
      );
      final List<CardModel> updatedCards = state.cards.map((CardModel item) {
        if (item.id != cardId) {
          return item;
        }
        updatedLocalCard = CardModel(
          id: item.id,
          clientId: item.clientId,
          deckId: item.deckId,
          title: title,
          content: content,
          tags: tags,
          note: note,
          createdAt: item.createdAt,
          updatedAt: DateTime.now(),
          state: item.state,
        );
        return updatedLocalCard!;
      }).toList();
      if (updatedLocalCard != null) {
        await _localCache.upsertCard(updatedLocalCard!.toJson());
      }
      state = state.copyWith(
        cards: updatedCards,
        errorMessage: '网络不可用，编辑已加入待同步队列',
      );
      return true;
    } catch (error) {
      state = state.copyWith(errorMessage: '编辑卡片失败：$error');
      return false;
    }
  }

  Future<void> deleteCards(List<String> cardIds) async {
    if (cardIds.isEmpty) {
      return;
    }
    final String? token = state.accessToken;
    final Set<String> ids = cardIds.toSet();

    if (token == null || token.isEmpty) {
      state = state.copyWith(errorMessage: '请先登录后再删除卡片');
      return;
    }

    final List<CardModel> originalCards = state.cards;
    state = state.copyWith(
      cards: originalCards
          .where((CardModel item) => !ids.contains(item.id))
          .toList(),
      clearError: true,
    );
    await _localCache.deleteCards(ids.toList());

    List<SyncOperation> nextOperations = await _loadPendingOperations();
    bool touchedRemote = false;
    bool hadNonOfflineFailure = false;
    String? nonOfflineErrorMessage;

    for (final String cardId in ids) {
      final CardModel? existingCard = originalCards
          .cast<CardModel?>()
          .firstWhere(
            (CardModel? item) => item?.id == cardId,
            orElse: () => null,
          );
      final String clientId = existingCard?.clientId ?? '';
      final bool hadPendingCreate =
          clientId.isNotEmpty &&
          _findPendingCreateOperation(
                operations: nextOperations,
                clientId: clientId,
              ) !=
              null;

      nextOperations = nextOperations.where((SyncOperation operation) {
        return !_operationReferencesCard(
          operation,
          cardId: cardId,
          clientId: clientId,
        );
      }).toList();

      if (cardId.startsWith('local_') || hadPendingCreate) {
        continue;
      }
      touchedRemote = true;
      try {
        await _apiClient.deleteCard(token: token, cardId: cardId);
      } on DioException catch (error) {
        if (_isUnauthorized(error)) {
          await _localCache.replaceCards(
            originalCards.map((CardModel item) => item.toJson()).toList(),
          );
          state = state.copyWith(cards: originalCards);
          await _expireSession(message: '登录已过期，请重新登录后再删除卡片');
          return;
        }
        if (_shouldQueueOffline(error)) {
          nextOperations = <SyncOperation>[
            ...nextOperations,
            SyncOperation(
              id: _uuid.v4(),
              type: 'delete_card',
              payload: <String, dynamic>{'card_id': cardId},
              occurredAt: DateTime.now(),
            ),
          ];
          continue;
        }
        hadNonOfflineFailure = true;
        nonOfflineErrorMessage ??= '删除卡片失败：$error';
      } catch (error) {
        hadNonOfflineFailure = true;
        nonOfflineErrorMessage ??= '删除卡片失败：$error';
      }
    }

    await _replacePendingOperations(nextOperations);
    if (hadNonOfflineFailure) {
      await refreshRemoteData();
      state = state.copyWith(errorMessage: nonOfflineErrorMessage ?? '删除卡片失败');
      return;
    }
    if (touchedRemote) {
      await refreshRemoteData();
    }
  }

  Future<void> submitReview({
    required String cardId,
    required ReviewRating rating,
  }) async {
    _ensureDailyProgressFresh();
    final String? token = state.accessToken;
    if (token == null || token.isEmpty) {
      state = state.copyWith(errorMessage: '请先登录后再提交评分');
      return;
    }

    final CardModel? existingCard = state.cards.cast<CardModel?>().firstWhere(
      (CardModel? item) => item?.id == cardId,
      orElse: () => null,
    );
    if (existingCard == null) {
      state = state.copyWith(errorMessage: '未找到待复习卡片');
      return;
    }

    try {
      final Map<String, dynamic> response = await _apiClient.submitReview(
        token: token,
        cardId: cardId,
        rating: rating.score,
        durationMs: 0,
      );
      await _localCache.upsertCard(response);

      final CardModel updated = CardModel.fromJson(response);
      final List<CardModel> cards = state.cards.map((CardModel card) {
        return card.id == updated.id ? updated : card;
      }).toList();

      state = state.copyWith(cards: cards, clearError: true);
      _recordReviewProgress(existingCard);
    } on DioException catch (error) {
      if (_isUnauthorized(error)) {
        await _expireSession(message: '登录已过期，请重新登录后再提交评分');
        return;
      }
      if (!_shouldQueueOffline(error)) {
        state = state.copyWith(errorMessage: '提交评分失败：$error');
        return;
      }

      final DateTime now = DateTime.now();
      final FsrsState nextState = _fsrsScheduler.review(
        current: existingCard.state,
        rating: rating,
        now: now,
      );
      final CardModel updatedLocalCard = CardModel(
        id: existingCard.id,
        clientId: existingCard.clientId,
        deckId: existingCard.deckId,
        title: existingCard.title,
        content: existingCard.content,
        tags: existingCard.tags,
        note: existingCard.note,
        createdAt: existingCard.createdAt,
        updatedAt: now,
        state: nextState,
      );

      final List<SyncOperation> operations = await _loadPendingOperations();
      final SyncOperation? pendingCreate = _findPendingCreateOperation(
        operations: operations,
        clientId: existingCard.clientId,
      );

      if (pendingCreate != null) {
        final List<SyncOperation> nextOperations = operations.map((
          SyncOperation item,
        ) {
          if (item.id != pendingCreate.id) {
            return item;
          }
          return SyncOperation(
            id: item.id,
            type: item.type,
            occurredAt: item.occurredAt,
            payload: <String, dynamic>{
              ...item.payload,
              'state': _fsrsStateToJson(nextState),
            },
          );
        }).toList();
        await _replacePendingOperations(nextOperations);
        await _localCache.upsertCard(updatedLocalCard.toJson());
        state = state.copyWith(
          cards: state.cards.map((CardModel card) {
            return card.id == updatedLocalCard.id ? updatedLocalCard : card;
          }).toList(),
          errorMessage: '复习结果已离线保存，待建卡同步时会带上本地进度',
        );
        _recordReviewProgress(existingCard);
        return;
      }

      final SyncOperation operation = SyncOperation(
        id: _uuid.v4(),
        type: 'submit_review',
        payload: <String, dynamic>{'card_id': cardId, 'rating': rating.score},
        occurredAt: now,
      );
      await _queueOperation(operation);
      await _localCache.upsertCard(updatedLocalCard.toJson());
      state = state.copyWith(
        cards: state.cards.map((CardModel card) {
          return card.id == updatedLocalCard.id ? updatedLocalCard : card;
        }).toList(),
        errorMessage: '复习结果已离线保存，稍后将自动同步',
      );
      _recordReviewProgress(existingCard);
    } catch (error) {
      state = state.copyWith(errorMessage: '提交评分失败：$error');
    }
  }

  Future<void> syncPendingOperations({String? token}) async {
    final String? effectiveToken = token ?? state.accessToken;
    if (effectiveToken == null || effectiveToken.isEmpty) {
      return;
    }

    final List<SyncOperation> operations = await _loadPendingOperations();
    if (operations.isEmpty) {
      state = state.copyWith(pendingOperations: <SyncOperation>[]);
      return;
    }

    final Map<String, dynamic> response = await _apiClient.syncPush(
      token: effectiveToken,
      operations: operations
          .map((SyncOperation item) => item.toJson())
          .toList(),
    );
    final List<Map<String, dynamic>> resultMaps = _coerceMapList(
      response['results'],
    );

    if (resultMaps.isNotEmpty) {
      final Set<String> appliedIDs = resultMaps
          .where((Map<String, dynamic> item) => item['applied'] == true)
          .map(
            (Map<String, dynamic> item) =>
                (item['operation_id'] ?? '').toString(),
          )
          .where((String id) => id.isNotEmpty)
          .toSet();
      final bool hasFailures = resultMaps.any(
        (Map<String, dynamic> item) => item['applied'] != true,
      );
      final List<SyncOperation> remainingOperations = operations
          .where((SyncOperation item) => !appliedIDs.contains(item.id))
          .toList();
      await _replacePendingOperations(remainingOperations);
      state = state.copyWith(
        pendingOperations: remainingOperations,
        lastSyncAt: appliedIDs.isNotEmpty ? DateTime.now() : state.lastSyncAt,
        clearError: !hasFailures,
        errorMessage: hasFailures ? '有部分待同步操作未成功，请稍后重试' : state.errorMessage,
      );
      return;
    }

    final int failedCount = (response['failed_count'] as num?)?.toInt() ?? 0;
    if (failedCount == 0) {
      await _replacePendingOperations(<SyncOperation>[]);
      state = state.copyWith(
        pendingOperations: <SyncOperation>[],
        lastSyncAt: DateTime.now(),
      );
      return;
    }
    state = state.copyWith(
      pendingOperations: operations,
      errorMessage: '有部分待同步操作未成功，请稍后重试',
    );
  }

  Future<void> generateCards({
    required String topic,
    required String context,
    required int cardCount,
    required String difficulty,
  }) async {
    final String? token = state.accessToken;
    if (token == null || token.isEmpty) {
      state = state.copyWith(errorMessage: '请先登录后再使用 AI 生成功能');
      return;
    }

    state = state.copyWith(syncInProgress: true, clearError: true);
    try {
      final List<Map<String, dynamic>> items = await _apiClient.generateCards(
        token: token,
        topic: topic,
        context: context,
        cardCount: cardCount,
        difficulty: difficulty,
      );
      state = state.copyWith(
        syncInProgress: false,
        generatedCards: items.map(AIGeneratedCard.fromJson).toList(),
      );
    } catch (error) {
      state = state.copyWith(
        syncInProgress: false,
        errorMessage: 'AI 生成失败：$error',
      );
    }
  }

  void clearGeneratedCards() {
    state = state.copyWith(generatedCards: <AIGeneratedCard>[]);
  }

  Future<void> _saveSessionFromResponse(Map<String, dynamic> response) async {
    final Map<String, dynamic> user = _coerceMap(response['user']);
    final String token = response['access_token'] as String;
    final String email = (user['email'] ?? '') as String;
    final String displayName = (user['display_name'] ?? '') as String;

    await _sessionStore.saveSession(
      accessToken: token,
      email: email,
      displayName: displayName,
    );

    state = state.copyWith(
      accessToken: token,
      email: email,
      displayName: displayName,
    );
  }

  Future<void> _queueOperation(SyncOperation operation) async {
    await _localCache.enqueueSyncOperation(
      id: operation.id,
      operationType: operation.type,
      payload: operation.payload,
      createdAt: operation.occurredAt,
    );
    final List<SyncOperation> operations = await _loadPendingOperations();
    state = state.copyWith(pendingOperations: operations);
  }

  Future<void> _replacePendingOperations(List<SyncOperation> operations) async {
    await _localCache.replaceSyncOperations(
      operations.map((SyncOperation item) => item.toJson()).toList(),
    );
    state = state.copyWith(pendingOperations: operations);
  }

  Future<List<SyncOperation>> _loadPendingOperations() async {
    final List<Map<String, dynamic>> rows = await _localCache
        .loadSyncOperations();
    return rows.map(SyncOperation.fromJson).toList();
  }

  SyncOperation? _findPendingCreateOperation({
    required List<SyncOperation> operations,
    required String clientId,
  }) {
    for (final SyncOperation operation in operations) {
      if (operation.type != 'create_card') {
        continue;
      }
      if ((operation.payload['client_id'] ?? '').toString() == clientId) {
        return operation;
      }
    }
    return null;
  }

  bool _operationReferencesCard(
    SyncOperation operation, {
    required String cardId,
    required String clientId,
  }) {
    final String payloadCardId = (operation.payload['card_id'] ?? '')
        .toString();
    final String payloadClientId = (operation.payload['client_id'] ?? '')
        .toString();
    return payloadCardId == cardId ||
        (clientId.isNotEmpty && payloadClientId == clientId);
  }

  bool _operationReferencesDeck(
    SyncOperation operation, {
    required String deckId,
    required Set<String> cardIds,
    required Set<String> clientIds,
  }) {
    final String payloadDeckId = (operation.payload['deck_id'] ?? '')
        .toString();
    final String payloadCardId = (operation.payload['card_id'] ?? '')
        .toString();
    final String payloadClientId = (operation.payload['client_id'] ?? '')
        .toString();
    return payloadDeckId == deckId ||
        (payloadCardId.isNotEmpty && cardIds.contains(payloadCardId)) ||
        (payloadClientId.isNotEmpty && clientIds.contains(payloadClientId));
  }

  bool _isUnauthorized(DioException error) {
    return error.response?.statusCode == 401;
  }

  bool _shouldQueueOffline(DioException error) {
    if (_isUnauthorized(error)) {
      return false;
    }
    if (error.response == null) {
      return true;
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        return error.response == null;
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
        return false;
    }
  }

  Map<String, dynamic> _fsrsStateToJson(FsrsState state) {
    return <String, dynamic>{
      'state': state.state,
      'difficulty': state.difficulty,
      'stability': state.stability,
      'retrievability': state.retrievability,
      'due_date': state.dueDate.toIso8601String(),
      'last_review_at': state.lastReviewAt?.toIso8601String(),
      'reps': state.reps,
      'lapses': state.lapses,
      'elapsed_days': state.elapsedDays,
      'scheduled_days': state.scheduledDays,
    };
  }

  Future<void> _expireSession({required String message}) async {
    await _sessionStore.clear();
    state = state.copyWith(
      isBootstrapping: false,
      syncInProgress: false,
      clearSession: true,
      errorMessage: message,
    );
  }
}

Map<String, dynamic> _coerceMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _coerceMapList(dynamic value) {
  if (value is! List) {
    return <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((Map item) => Map<String, dynamic>.from(item))
      .toList();
}

class _RemoteSnapshot {
  const _RemoteSnapshot({required this.decks, required this.cards});

  final List<Map<String, dynamic>> decks;
  final List<Map<String, dynamic>> cards;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) {
    return null;
  }
  final String text = value.toString();
  if (text.isEmpty || text.startsWith('0001-01-01')) {
    return null;
  }
  return DateTime.tryParse(text)?.toLocal();
}

String? firstNonEmptyLine(String content) {
  for (final String line in content.replaceAll('\r\n', '\n').split('\n')) {
    final String trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

dynamic _nested(Map<String, dynamic> json, String path) {
  dynamic current = json;
  for (final String part in path.split('.')) {
    if (current is! Map<String, dynamic> || !current.containsKey(part)) {
      return null;
    }
    current = current[part];
  }
  return current;
}

int _intValue(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final dynamic value = _nested(json, key);
    if (value is num) {
      return value.toInt();
    }
  }
  return 0;
}

double _doubleValue(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final dynamic value = _nested(json, key);
    if (value is num) {
      return value.toDouble();
    }
  }
  return 0;
}
