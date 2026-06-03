import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flashcard_app/app/app.dart';
import 'package:flashcard_app/app/router.dart';
import 'package:flashcard_app/core/app_store.dart';

class _RewriteSheetTestStore extends AppStore {
  _RewriteSheetTestStore() : super() {
    state = AppState(
      decks: const <DeckModel>[
        DeckModel(
          id: 'deck-1',
          name: 'Education Principles',
          description: 'Learning principles',
          icon: 'book',
          colorHex: '#4ECDC4',
        ),
      ],
      cards: const <CardModel>[],
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

  @override
  Future<void> generateCards({
    required String topic,
    required String context,
    required int cardCount,
    required String difficulty,
    GenerationPolicy? policy,
  }) async {
    state = state.copyWith(
      syncInProgress: false,
      generatedCards: const <AIGeneratedCard>[
        AIGeneratedCard(
          title: 'Education Principles中，Educational ai的含义是什么？',
          content:
              'Education Principles中，Educational ai的含义是什么？\n\n@answer\nEducational aims define learner development\n@end',
          cardType: 'basic',
          tags: <String>['AI生成'],
          note: '',
        ),
      ],
      clearError: true,
    );
  }

  @override
  Future<List<AIRewriteCandidate>> rewriteCardWithAI({
    required String title,
    required String content,
    required String rewriteType,
    required String instruction,
    String? cardId,
  }) async {
    state = state.copyWith(syncInProgress: true, clearError: true);
    await Future<void>.delayed(Duration.zero);
    const List<AIRewriteCandidate> candidates = <AIRewriteCandidate>[
      AIRewriteCandidate(
        title: '教育目的规定什么？',
        content: '教育目的规定什么？\n\n@answer\n人才培养方向。\n@end',
        changeSummary: '改为自然中文题干。',
        qualityNotes: <String>[],
      ),
    ];
    state = state.copyWith(
      syncInProgress: false,
      rewriteCandidates: candidates,
    );
    return candidates;
  }

  @override
  Future<AICardChatResponse?> chatWithGeneratedCards({
    required String topic,
    required String instruction,
    required int cardCount,
    required String difficulty,
    required List<Map<String, String>> messages,
    String? operation,
    List<int> selectedIndexes = const <int>[],
    Map<String, dynamic>? reference,
    GenerationPolicy? policy,
  }) async {
    final bool singleCardRefine =
        operation == 'refine' && selectedIndexes.isNotEmpty;
    final List<AIGeneratedCard> cards = <AIGeneratedCard>[
      AIGeneratedCard(
        title: singleCardRefine ? '微调后的形成性评估' : '形成性评估的作用是什么？',
        content: singleCardRefine
            ? '形成性评估的作用是什么？\n\n@answer\n可以这样记：它帮助学生及时修正学习。\n@end'
            : '形成性评估的作用是什么？\n\n@answer\n支持及时反馈。\n@end',
        cardType: 'basic',
        tags: const <String>['AI生成'],
        note: '',
      ),
    ];
    final AICardChatResponse response = AICardChatResponse(
      assistantMessage: singleCardRefine ? '已按单卡要求微调。' : '已生成 1 张草稿。',
      items: cards,
      updatedIndex: singleCardRefine ? selectedIndexes.first : null,
    );
    state = state.copyWith(generatedCards: cards, clearError: true);
    return response;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('generated draft can be refined through single-card chat', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appStoreProvider.overrideWith((Ref ref) => _RewriteSheetTestStore()),
        ],
        child: const FlashcardApp(),
      ),
    );

    appRouter.go('/deck/deck-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI 生成卡片'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('生成草稿'));
    await tester.tap(find.text('生成草稿'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('微调').first);
    await tester.tap(find.text('微调').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '告诉 AI 如何改这张卡'),
      '答案更口语',
    );
    await tester.tap(find.byTooltip('发送').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('已按单卡要求微调。'), findsOneWidget);
    expect(find.text('微调后的形成性评估'), findsAtLeastNWidgets(1));
  });

  testWidgets('AI file import mode renders picker on phone width', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appStoreProvider.overrideWith((Ref ref) => _RewriteSheetTestStore()),
        ],
        child: const FlashcardApp(),
      ),
    );

    appRouter.go('/deck/deck-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI 生成卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入文件'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('选择 PDF / Markdown / TXT 文件'), findsOneWidget);
    expect(find.text('选择'), findsOneWidget);
  });

  testWidgets(
    'AI chat designer sends requirements while preview stays separate',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appStoreProvider.overrideWith(
              (Ref ref) => _RewriteSheetTestStore(),
            ),
          ],
          child: const FlashcardApp(),
        ),
      );

      appRouter.go('/deck/deck-1');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('AI 生成卡片'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '告诉 AI 你的制卡/微调需求'),
        '帮我做一张形成性评估卡片',
      );
      await tester.ensureVisible(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(find.text('已生成 1 张草稿。'), findsOneWidget);
      expect(find.text('形成性评估的作用是什么？'), findsAtLeastNWidgets(1));
      expect(find.text('引用第 1 张'), findsNothing);
      expect(find.text('微调'), findsOneWidget);
    },
  );
}
