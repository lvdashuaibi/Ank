enum ReviewRating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const ReviewRating(this.score);
  final int score;

  static ReviewRating? fromScore(int score) {
    for (final ReviewRating value in ReviewRating.values) {
      if (value.score == score) {
        return value;
      }
    }
    return null;
  }
}

class FsrsState {
  const FsrsState({
    this.state = 0,
    this.difficulty = 0,
    this.stability = 0,
    this.retrievability = 0,
    required this.dueDate,
    this.lastReviewAt,
    this.reps = 0,
    this.lapses = 0,
    this.elapsedDays = 0,
    this.scheduledDays = 0,
  });

  final int state;
  final double difficulty;
  final double stability;
  final double retrievability;
  final DateTime dueDate;
  final DateTime? lastReviewAt;
  final int reps;
  final int lapses;
  final double elapsedDays;
  final double scheduledDays;

  bool get isDue => !dueDate.isAfter(DateTime.now());
}
