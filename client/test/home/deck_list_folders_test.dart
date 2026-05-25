import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flashcard_app/app/app.dart';
import 'package:flashcard_app/app/router.dart';
import 'package:flashcard_app/core/app_store.dart';

class _DeckListTestStore extends AppStore {
  _DeckListTestStore() : super() {
    state = AppState(
      folders: <FolderModel>[
        FolderModel(
          id: 'folder-1',
          name: '语言学习',
          createdAt: DateTime(2026, 4, 20, 9),
          updatedAt: DateTime(2026, 4, 20, 9),
        ),
      ],
      decks: const <DeckModel>[
        DeckModel(
          id: 'deck-in-folder',
          folderId: 'folder-1',
          name: '英语核心词汇',
          description: '放在文件夹里的牌组',
          icon: '📚',
          colorHex: '#4ECDC4',
        ),
        DeckModel(
          id: 'deck-ungrouped',
          name: '算法题',
          description: '未分类牌组',
          icon: '🧠',
          colorHex: '#FF6B6B',
        ),
      ],
      cards: <CardModel>[
        CardModel(
          id: 'card-1',
          clientId: 'card-1',
          deckId: 'deck-in-folder',
          title: 'apple',
          content: 'apple\n\n@answer\n苹果\n@end',
          tags: const <String>[],
          note: '',
          studyEnabled: true,
          createdAt: DateTime(2026, 4, 20, 9),
          updatedAt: DateTime(2026, 4, 20, 9),
          state: FsrsState(dueDate: DateTime(2026, 4, 20, 9)),
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

  testWidgets('deck list groups decks by folder and ungrouped sections', (
    WidgetTester tester,
  ) async {
    appRouter.go('/');

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appStoreProvider.overrideWith((Ref ref) => _DeckListTestStore()),
        ],
        child: const FlashcardApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你的学习空间'), findsOneWidget);
    expect(find.text('语言学习'), findsOneWidget);
    expect(find.text('英语核心词汇'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('算法题'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('算法题'), findsOneWidget);
  });
}
