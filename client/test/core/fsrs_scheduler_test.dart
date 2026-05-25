import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/core/fsrs_scheduler.dart';

void main() {
  test('ReviewRating.fromScore parses valid scores', () {
    expect(ReviewRating.fromScore(1), ReviewRating.again);
    expect(ReviewRating.fromScore(2), ReviewRating.hard);
    expect(ReviewRating.fromScore(3), ReviewRating.good);
    expect(ReviewRating.fromScore(4), ReviewRating.easy);
    expect(ReviewRating.fromScore(0), isNull);
    expect(ReviewRating.fromScore(5), isNull);
  });

  test('FsrsState.isDue reflects due date', () {
    expect(
      FsrsState(
        dueDate: DateTime.now().subtract(const Duration(minutes: 1)),
      ).isDue,
      isTrue,
    );
    expect(
      FsrsState(dueDate: DateTime.now().add(const Duration(days: 1))).isDue,
      isFalse,
    );
  });
}
