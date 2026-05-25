import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flashcard_app/core/database/local_cache.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('local cache persists daily review progress', () async {
    final LocalCache cache = LocalCache(
      databaseName: 'flashcard_app_daily_progress_test.db',
    );
    addTearDown(() async {
      await cache.deleteDatabaseFile();
    });

    await cache.saveDailyProgress(<String, dynamic>{
      'day_key': '2026-04-29',
      'completed_today': 3,
      'reviewed_review_today_by_deck': <String, int>{'deck-1': 2},
      'introduced_new_today_by_deck': <String, int>{'deck-1': 1},
    });

    final Map<String, dynamic>? loaded = await cache.loadDailyProgress();
    expect(loaded, isNotNull);
    expect(loaded!['day_key'], '2026-04-29');
    expect(loaded['completed_today'], 3);
    expect(
      Map<String, dynamic>.from(loaded['reviewed_review_today_by_deck'] as Map),
      <String, dynamic>{'deck-1': 2},
    );
    expect(
      Map<String, dynamic>.from(loaded['introduced_new_today_by_deck'] as Map),
      <String, dynamic>{'deck-1': 1},
    );
  });

  test('clearAll removes persisted daily review progress', () async {
    final LocalCache cache = LocalCache(
      databaseName: 'flashcard_app_daily_progress_clear_test.db',
    );
    addTearDown(() async {
      await cache.deleteDatabaseFile();
    });

    await cache.saveDailyProgress(<String, dynamic>{
      'day_key': '2026-04-29',
      'completed_today': 1,
      'reviewed_review_today_by_deck': <String, int>{'deck-1': 1},
      'introduced_new_today_by_deck': <String, int>{},
    });

    await cache.clearAll();

    expect(await cache.loadDailyProgress(), isNull);
  });
}
