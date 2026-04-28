import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/core/app_store.dart';

void main() {
  final DateTime now = DateTime.now();

  DeckModel deck({
    required String id,
    int newCardsPerDay = 20,
    int maxReviewsPerDay = 200,
  }) {
    return DeckModel(
      id: id,
      name: id,
      description: '',
      icon: '📚',
      colorHex: '#4ECDC4',
      newCardsPerDay: newCardsPerDay,
      maxReviewsPerDay: maxReviewsPerDay,
    );
  }

  CardModel card({
    required String id,
    required String deckId,
    required int state,
    required DateTime dueDate,
    DateTime? createdAt,
  }) {
    final DateTime created = createdAt ?? now;
    return CardModel(
      id: id,
      clientId: id,
      deckId: deckId,
      title: id,
      content: id,
      tags: const <String>[],
      note: '',
      createdAt: created,
      updatedAt: created,
      state: FsrsState(
        state: state,
        dueDate: dueDate,
        lastReviewAt: state == 0
            ? null
            : dueDate.subtract(const Duration(days: 1)),
      ),
    );
  }

  String dayKey(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  test(
    'dueCards prioritizes learning, then limited reviews, then limited new',
    () {
      final AppState state = AppState(
        decks: <DeckModel>[
          deck(id: 'deck-1', newCardsPerDay: 1, maxReviewsPerDay: 2),
        ],
        cards: <CardModel>[
          card(
            id: 'learning',
            deckId: 'deck-1',
            state: 1,
            dueDate: now.subtract(const Duration(minutes: 2)),
          ),
          card(
            id: 'review-2',
            deckId: 'deck-1',
            state: 2,
            dueDate: now.subtract(const Duration(hours: 1)),
          ),
          card(
            id: 'review-1',
            deckId: 'deck-1',
            state: 2,
            dueDate: now.subtract(const Duration(hours: 2)),
          ),
          card(
            id: 'review-3',
            deckId: 'deck-1',
            state: 2,
            dueDate: now.subtract(const Duration(minutes: 20)),
          ),
          card(
            id: 'new-1',
            deckId: 'deck-1',
            state: 0,
            dueDate: now.subtract(const Duration(minutes: 1)),
            createdAt: now.subtract(const Duration(days: 2)),
          ),
          card(
            id: 'new-2',
            deckId: 'deck-1',
            state: 0,
            dueDate: now.subtract(const Duration(minutes: 1)),
            createdAt: now.subtract(const Duration(days: 1)),
          ),
        ],
        completedToday: 0,
        reviewedReviewTodayByDeck: const <String, int>{},
        introducedNewTodayByDeck: const <String, int>{},
        isBootstrapping: false,
        syncInProgress: false,
        pendingOperations: const <SyncOperation>[],
        generatedCards: const <AIGeneratedCard>[],
        dailyProgressDayKey: dayKey(now),
      );

      expect(
        state
            .dueCards(deckId: 'deck-1')
            .map((CardModel item) => item.id)
            .toList(),
        <String>['learning', 'review-1', 'review-2', 'new-1'],
      );
    },
  );

  test('dueCards subtracts today progress from review and new quotas', () {
    final AppState state = AppState(
      decks: <DeckModel>[
        deck(id: 'deck-1', newCardsPerDay: 2, maxReviewsPerDay: 2),
      ],
      cards: <CardModel>[
        card(
          id: 'learning',
          deckId: 'deck-1',
          state: 3,
          dueDate: now.subtract(const Duration(minutes: 5)),
        ),
        card(
          id: 'review-1',
          deckId: 'deck-1',
          state: 2,
          dueDate: now.subtract(const Duration(hours: 3)),
        ),
        card(
          id: 'review-2',
          deckId: 'deck-1',
          state: 2,
          dueDate: now.subtract(const Duration(hours: 2)),
        ),
        card(
          id: 'new-1',
          deckId: 'deck-1',
          state: 0,
          dueDate: now.subtract(const Duration(minutes: 1)),
          createdAt: now.subtract(const Duration(days: 2)),
        ),
        card(
          id: 'new-2',
          deckId: 'deck-1',
          state: 0,
          dueDate: now.subtract(const Duration(minutes: 1)),
          createdAt: now.subtract(const Duration(days: 1)),
        ),
      ],
      completedToday: 2,
      reviewedReviewTodayByDeck: const <String, int>{'deck-1': 1},
      introducedNewTodayByDeck: const <String, int>{'deck-1': 1},
      isBootstrapping: false,
      syncInProgress: false,
      pendingOperations: const <SyncOperation>[],
      generatedCards: const <AIGeneratedCard>[],
      dailyProgressDayKey: dayKey(now),
    );

    expect(
      state
          .dueCards(deckId: 'deck-1')
          .map((CardModel item) => item.id)
          .toList(),
      <String>['learning', 'review-1', 'new-1'],
    );
  });
}
