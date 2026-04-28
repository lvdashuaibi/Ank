import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flashcard_app/app/app.dart';
import 'package:flashcard_app/app/router.dart';
import 'package:flashcard_app/core/app_store.dart';

class _TestAppStore extends AppStore {
  _TestAppStore() : super() {
    state = AppState(
      decks: const <DeckModel>[
        DeckModel(
          id: 'deck-1',
          name: '测试牌组',
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
          title: '已有卡片',
          content: '题目内容\n\n@answer\n答案内容\n@end',
          tags: const <String>[],
          note: '',
          createdAt: DateTime(2026, 4, 23, 10),
          updatedAt: DateTime(2026, 4, 23, 10),
          state: FsrsState(dueDate: DateTime(2026, 4, 23, 10)),
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

  @override
  Future<void> bootstrap() async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('router can open add card editor screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appStoreProvider.overrideWith((Ref ref) => _TestAppStore()),
        ],
        child: const FlashcardApp(),
      ),
    );

    appRouter.go('/deck/deck-1/add-card');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('创建卡片'), findsAtLeastNWidgets(1));
    expect(find.text('测试牌组'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('填空'), findsOneWidget);
  });

  testWidgets('router can open edit existing card screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appStoreProvider.overrideWith((Ref ref) => _TestAppStore()),
        ],
        child: const FlashcardApp(),
      ),
    );

    appRouter.go('/deck/deck-1/card/card-1/edit');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('编辑卡片'), findsAtLeastNWidgets(1));
    expect(find.text('已有卡片'), findsOneWidget);
    expect(find.text('测试牌组'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('填空'), findsOneWidget);
  });
}
