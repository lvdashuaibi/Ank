import 'dart:ui';

import 'package:flashcard_app/app/app.dart';
import 'package:flashcard_app/app/router.dart';
import 'package:flashcard_app/core/app_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ReviewChoiceTestStore extends AppStore {
  _ReviewChoiceTestStore() : super() {
    final DateTime now = DateTime(2026, 6, 3, 10);
    state = AppState(
      decks: const <DeckModel>[
        DeckModel(
          id: 'deck-1',
          name: '教育学原理',
          description: '',
          icon: '📚',
          colorHex: '#4ECDC4',
        ),
      ],
      cards: <CardModel>[
        CardModel(
          id: 'card-1',
          clientId: 'card-1',
          deckId: 'deck-1',
          title: '形成性评估',
          content: '''
根据文本，形成性评估的主要作用是什么？
A. 定义学习者发展
B. 支持及时反馈
C. 确定课程目标
D. 提供最终等级

@answer
B. 支持及时反馈
@end
''',
          tags: const <String>['AI生成'],
          note: '',
          studyEnabled: true,
          createdAt: now,
          updatedAt: now,
          state: FsrsState(dueDate: now.subtract(const Duration(minutes: 1))),
        ),
      ],
      completedToday: 0,
      reviewedReviewTodayByDeck: const <String, int>{},
      introducedNewTodayByDeck: const <String, int>{},
      isBootstrapping: false,
      syncInProgress: false,
      pendingOperations: const <SyncOperation>[],
      generatedCards: const <AIGeneratedCard>[],
      accessToken: 'test-token',
      email: 'test@example.com',
      displayName: 'tester',
    );
  }

  ReviewRating? lastRating;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<CardModel?> submitReview({
    required String cardId,
    required ReviewRating rating,
  }) async {
    lastRating = rating;
    final CardModel updated = CardModel(
      id: 'card-1',
      clientId: 'card-1',
      deckId: 'deck-1',
      title: '形成性评估',
      content: state.cards.first.content,
      tags: const <String>['AI生成'],
      note: '',
      studyEnabled: true,
      createdAt: DateTime(2026, 6, 3, 10),
      updatedAt: DateTime(2026, 6, 3, 10),
      state: FsrsState(dueDate: DateTime(2026, 6, 4, 10), reps: 1),
    );
    state = state.copyWith(cards: <CardModel>[updated], clearError: true);
    return updated;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('plain AI choice card reviews as interactive single choice', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _ReviewChoiceTestStore store = _ReviewChoiceTestStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appStoreProvider.overrideWith((Ref ref) => store),
        ],
        child: const FlashcardApp(),
      ),
    );

    appRouter.go('/review?deck_id=deck-1');
    await tester.pumpAndSettle();

    expect(find.text('查看答案'), findsNothing);
    expect(find.text('单选题'), findsOneWidget);
    expect(find.text('B. 支持及时反馈'), findsOneWidget);
    expect(find.text('提交答案'), findsOneWidget);

    await tester.tap(find.text('B. 支持及时反馈'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交答案'));
    await tester.pumpAndSettle();

    expect(find.text('答案/解析'), findsOneWidget);
    expect(find.text('正常想起'), findsOneWidget);

    await tester.tap(find.text('正常想起'));
    await tester.pumpAndSettle();

    expect(store.lastRating, ReviewRating.good);
    expect(find.text('本轮已完成'), findsOneWidget);
  });
}
