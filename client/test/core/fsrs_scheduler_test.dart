import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/core/fsrs_scheduler.dart';

void main() {
  const FsrsScheduler scheduler = FsrsScheduler();
  final DateTime now = DateTime.utc(2026, 4, 23, 10);

  test('new good card enters learning with 10 minute step', () {
    final FsrsState next = scheduler.review(
      current: FsrsState(dueDate: now),
      rating: ReviewRating.good,
      now: now,
    );

    expect(next.state, 1);
    expect(next.dueDate.difference(now), const Duration(minutes: 10));
    expect(next.reps, 1);
  });

  test('learning good graduates to review with day interval', () {
    final FsrsState next = scheduler.review(
      current: FsrsState(
        state: 1,
        difficulty: scheduler.initDifficulty(ReviewRating.good),
        stability: scheduler.initStability(ReviewRating.good),
        dueDate: now,
        lastReviewAt: now.subtract(const Duration(minutes: 10)),
      ),
      rating: ReviewRating.good,
      now: now,
    );

    expect(next.state, 2);
    expect(next.scheduledDays, greaterThanOrEqualTo(1));
  });

  test('review good keeps long-term interval above one day', () {
    final FsrsState next = scheduler.review(
      current: FsrsState(
        state: 2,
        difficulty: 5,
        stability: 10,
        dueDate: now,
        lastReviewAt: now.subtract(const Duration(days: 10)),
      ),
      rating: ReviewRating.good,
      now: now,
    );

    expect(next.state, 2);
    expect(next.scheduledDays, greaterThan(1));
    expect(next.stability, greaterThan(0.1));
  });

  test('relearning good returns card to review', () {
    final FsrsState next = scheduler.review(
      current: FsrsState(
        state: 3,
        difficulty: 6,
        stability: 3,
        dueDate: now,
        lastReviewAt: now.subtract(const Duration(minutes: 10)),
      ),
      rating: ReviewRating.good,
      now: now,
    );

    expect(next.state, 2);
    expect(next.scheduledDays, greaterThanOrEqualTo(1));
  });
}
