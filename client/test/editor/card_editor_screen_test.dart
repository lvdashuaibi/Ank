import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flashcard_app/app/editor/card_editor_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('card editor screen renders base editor fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: BlockCardEditorScreen(deckId: 'deck-1')),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('创建卡片'), findsAtLeastNWidgets(1));
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('预览'), findsOneWidget);
  });

  testWidgets('card editor screen renders toolbar on iPhone-sized viewport', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: BlockCardEditorScreen(deckId: 'deck-1')),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('填空'), findsOneWidget);
    expect(find.text('高亮'), findsOneWidget);
    expect(find.text('单选'), findsOneWidget);
    expect(find.text('多选'), findsOneWidget);
  });
}
