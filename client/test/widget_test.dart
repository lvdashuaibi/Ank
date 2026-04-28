import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flashcard_app/app/app.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('app boots smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: FlashcardApp()));

    expect(find.byType(FlashcardApp), findsOneWidget);
  });
}
