import 'dart:math' as math;

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

class FsrsScheduler {
  const FsrsScheduler({
    this.weights = _defaultWeights,
    this.decay = -0.5,
    this.requestRetention = 0.9,
  });

  static const List<double> _defaultWeights = <double>[
    0.4072,
    1.1829,
    3.1262,
    15.4722,
    7.2102,
    0.5316,
    1.0651,
    0.0046,
    1.5418,
    0.1618,
    1.0190,
    29.6395,
    0.0613,
    0.3055,
    0.3206,
    0.2040,
    3.2197,
    0.2460,
    0.5110,
  ];

  final List<double> weights;
  final double decay;
  final double requestRetention;

  FsrsState review({
    required FsrsState current,
    required ReviewRating rating,
    required DateTime now,
  }) {
    final FsrsState state = _sanitizeState(current);
    double elapsedDays = 0;
    if (state.lastReviewAt != null) {
      elapsedDays = now.difference(state.lastReviewAt!).inHours / 24.0;
    }
    if (!elapsedDays.isFinite || elapsedDays < 0) {
      elapsedDays = 0;
    }

    double newDifficulty = state.difficulty;
    double newStability = state.stability;
    int newState = state.state;
    DateTime dueDate = now;

    switch (state.state) {
      case 0:
        newDifficulty = initDifficulty(rating);
        newStability = initStability(rating);
        switch (rating) {
          case ReviewRating.again:
            newState = 1;
            dueDate = now.add(const Duration(minutes: 1));
            break;
          case ReviewRating.hard:
            newState = 1;
            dueDate = now.add(const Duration(minutes: 5));
            break;
          case ReviewRating.good:
            newState = 1;
            dueDate = now.add(const Duration(minutes: 10));
            break;
          case ReviewRating.easy:
            newState = 2;
            dueDate = now.add(
              _intervalDaysToDuration(nextInterval(newStability)),
            );
            break;
        }
        break;
      case 1:
        newDifficulty = nextDifficulty(state.difficulty, rating);
        newStability = shortTermStability(state.stability, rating);
        switch (rating) {
          case ReviewRating.again:
            newState = 1;
            dueDate = now.add(const Duration(minutes: 5));
            break;
          case ReviewRating.hard:
            newState = 1;
            dueDate = now.add(const Duration(minutes: 10));
            break;
          case ReviewRating.good:
            newState = 2;
            dueDate = now.add(
              _intervalDaysToDuration(nextInterval(newStability)),
            );
            break;
          case ReviewRating.easy:
            final double goodStability = shortTermStability(
              state.stability,
              ReviewRating.good,
            );
            final double goodInterval = nextInterval(goodStability);
            final double easyInterval = math.max(
              nextInterval(newStability),
              goodInterval + 1,
            );
            newState = 2;
            dueDate = now.add(_intervalDaysToDuration(easyInterval));
            break;
        }
        break;
      case 3:
        newDifficulty = nextDifficulty(state.difficulty, rating);
        newStability = shortTermStability(state.stability, rating);
        switch (rating) {
          case ReviewRating.again:
          case ReviewRating.hard:
            newState = 3;
            dueDate = now.add(const Duration(minutes: 10));
            break;
          case ReviewRating.good:
            newState = 2;
            dueDate = now.add(
              _intervalDaysToDuration(nextInterval(newStability)),
            );
            break;
          case ReviewRating.easy:
            final double goodStability = shortTermStability(
              state.stability,
              ReviewRating.good,
            );
            final double goodInterval = nextInterval(goodStability);
            final double easyInterval = math.max(
              nextInterval(newStability),
              goodInterval + 1,
            );
            newState = 2;
            dueDate = now.add(_intervalDaysToDuration(easyInterval));
            break;
        }
        break;
      default:
        final double retrievability = calculateRetrievability(
          elapsedDays,
          state.stability,
        );
        newDifficulty = nextDifficulty(state.difficulty, rating);
        if (rating == ReviewRating.again) {
          newStability = nextStabilityOnForget(
            state.difficulty,
            state.stability,
            retrievability,
          );
          newState = 3;
          dueDate = now.add(const Duration(minutes: 10));
        } else {
          newStability = nextStabilityOnRecall(
            state.difficulty,
            state.stability,
            retrievability,
            rating,
          );
          newState = 2;
          dueDate = now.add(
            _intervalDaysToDuration(nextInterval(newStability)),
          );
        }
        break;
    }

    return _sanitizeState(
      FsrsState(
        state: newState,
        difficulty: newDifficulty,
        stability: newStability,
        retrievability: calculateRetrievability(0, newStability),
        dueDate: dueDate,
        lastReviewAt: now,
        reps: state.reps + 1,
        lapses: state.lapses + (rating == ReviewRating.again ? 1 : 0),
        elapsedDays: elapsedDays,
        scheduledDays: dueDate.difference(now).inHours / 24.0,
      ),
    );
  }

  double initStability(ReviewRating rating) {
    return math.max(weights[rating.score - 1], 0.1);
  }

  double initDifficulty(ReviewRating rating) {
    final double value =
        weights[4] - math.exp(weights[5] * (rating.score - 1)) + 1;
    return _clamp(value, 1, 10);
  }

  double nextDifficulty(double difficulty, ReviewRating rating) {
    final double neutral = initDifficulty(ReviewRating.easy);
    final double value =
        weights[7] * neutral +
        (1 - weights[7]) * (difficulty - weights[6] * (rating.score - 3));
    return _clamp(value, 1, 10);
  }

  double calculateRetrievability(double elapsedDays, double stability) {
    if (stability <= 0) {
      return 0;
    }
    final double factor = _forgettingCurveFactor();
    final double base = 1 + factor * elapsedDays / stability;
    if (!base.isFinite || base <= 0) {
      return 0;
    }
    final double value = math.pow(base, decay).toDouble();
    if (!value.isFinite) {
      return 0;
    }
    return value;
  }

  double nextStabilityOnRecall(
    double difficulty,
    double stability,
    double retrievability,
    ReviewRating rating,
  ) {
    double hardPenalty = 1;
    double easyBonus = 1;
    if (rating == ReviewRating.hard) {
      hardPenalty = weights[15];
    }
    if (rating == ReviewRating.easy) {
      easyBonus = weights[16];
    }
    final double value =
        stability *
        (math.exp(weights[8]) *
                (11 - difficulty) *
                math.pow(stability, -weights[9]) *
                (math.exp(weights[10] * (1 - retrievability)) - 1) *
                hardPenalty *
                easyBonus +
            1);
    if (!value.isFinite) {
      return 0.1;
    }
    return math.max(value, 0.1);
  }

  double shortTermStability(double stability, ReviewRating rating) {
    final double value =
        stability * math.exp(weights[17] * ((rating.score - 3) + weights[18]));
    if (!value.isFinite) {
      return 0.1;
    }
    return math.max(value, 0.1);
  }

  double nextStabilityOnForget(
    double difficulty,
    double stability,
    double retrievability,
  ) {
    final double value =
        weights[11] *
        math.pow(difficulty, -weights[12]) *
        (math.pow(stability + 1, weights[13]) - 1) *
        math.exp(weights[14] * (1 - retrievability));
    if (!value.isFinite) {
      return 0.1;
    }
    return math.max(math.min(value.toDouble(), stability), 0.1);
  }

  double nextInterval(double stability) {
    final double factor = _forgettingCurveFactor();
    final double value =
        (stability / factor) *
        (math.pow(requestRetention, 1 / decay).toDouble() - 1);
    if (!value.isFinite) {
      return 1;
    }
    return math.max(value.roundToDouble(), 1);
  }

  FsrsState _sanitizeState(FsrsState state) {
    return FsrsState(
      state: state.state,
      difficulty: _clamp(state.difficulty, 1, 10, fallback: 1),
      stability: _positive(state.stability, fallback: 0.1),
      retrievability: _clamp(state.retrievability, 0, 1, fallback: 0),
      dueDate: state.dueDate,
      lastReviewAt: state.lastReviewAt,
      reps: state.reps,
      lapses: state.lapses,
      elapsedDays: _nonNegative(state.elapsedDays),
      scheduledDays: _nonNegative(state.scheduledDays),
    );
  }

  double _forgettingCurveFactor() {
    final double value = math.pow(requestRetention, 1 / decay).toDouble() - 1;
    if (!value.isFinite || value <= 0) {
      return 0.23456790123456783;
    }
    return value;
  }

  Duration _intervalDaysToDuration(double days) {
    if (!days.isFinite || days <= 0) {
      return const Duration(days: 1);
    }
    return Duration(hours: (days * 24).round());
  }

  double _clamp(
    double value,
    double minValue,
    double maxValue, {
    double? fallback,
  }) {
    final double safeFallback = fallback ?? minValue;
    if (!value.isFinite) {
      return safeFallback;
    }
    return math.max(minValue, math.min(maxValue, value));
  }

  double _positive(double value, {required double fallback}) {
    if (!value.isFinite || value <= 0) {
      return fallback;
    }
    return value;
  }

  double _nonNegative(double value) {
    if (!value.isFinite || value < 0) {
      return 0;
    }
    return value;
  }
}
