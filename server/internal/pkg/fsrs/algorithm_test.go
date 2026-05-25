package fsrs

import (
	"math"
	"reflect"
	"testing"
	"time"

	"github.com/ank/flashcard-server/internal/model"
)

func TestReviewOnNewCardCreatesFutureDueDate(t *testing.T) {
	engine := NewEngine()
	now := time.Date(2026, 4, 23, 10, 0, 0, 0, time.UTC)

	next := engine.Review(model.FSRSState{DueDate: now}, Good, now)

	if !next.DueDate.After(now) {
		t.Fatalf("expected due date after now")
	}
	if next.Reps != 1 {
		t.Fatalf("expected reps to be 1, got %d", next.Reps)
	}
	if next.State != 1 {
		t.Fatalf("expected new good card to enter learning, got %d", next.State)
	}
	if next.DueDate.Sub(now) != 10*time.Minute {
		t.Fatalf("expected new good card to be scheduled after 10m, got %s", next.DueDate.Sub(now))
	}
}

func TestLearningGoodGraduatesToReview(t *testing.T) {
	engine := NewEngine()
	now := time.Date(2026, 4, 23, 10, 0, 0, 0, time.UTC)
	learning := model.FSRSState{
		State:        1,
		Difficulty:   engine.initDifficulty(Good),
		Stability:    engine.initStability(Good),
		DueDate:      now,
		LastReviewAt: now.Add(-10 * time.Minute),
	}

	next := engine.Review(learning, Good, now)

	if next.State != 2 {
		t.Fatalf("expected learning good card to graduate to review, got %d", next.State)
	}
	if next.ScheduledDays < 1 {
		t.Fatalf("expected graduated learning card to have >= 1 day interval, got %.2f", next.ScheduledDays)
	}
}

func TestReviewKeepsLongTermIntervalsAboveOneDay(t *testing.T) {
	engine := NewEngine()
	now := time.Date(2026, 4, 23, 10, 0, 0, 0, time.UTC)
	state := model.FSRSState{
		State:        2,
		Difficulty:   5,
		Stability:    10,
		DueDate:      now,
		LastReviewAt: now.Add(-10 * 24 * time.Hour),
	}

	next := engine.Review(state, Good, now)

	if next.State != 2 {
		t.Fatalf("expected review card to stay in review, got %d", next.State)
	}
	if next.ScheduledDays <= 1 {
		t.Fatalf("expected review interval to stay above one day, got %.2f", next.ScheduledDays)
	}
	if next.Stability <= 0.001 {
		t.Fatalf("expected stability to remain meaningfully positive, got %.4f", next.Stability)
	}
}

func TestEngineMatchesOfficialGoFsrsBasicSequence(t *testing.T) {
	engine := NewEngine()
	now := time.Date(2022, 11, 29, 12, 30, 0, 0, time.UTC)
	state := model.FSRSState{DueDate: now}
	ratings := []ReviewRating{Good, Good, Good, Good, Good, Good, Again, Again, Good, Good, Good, Good, Good}
	gotIntervals := make([]int, 0, len(ratings))
	gotStates := make([]int, 0, len(ratings))

	for _, rating := range ratings {
		state = engine.Review(state, rating, now)
		gotIntervals = append(gotIntervals, int(state.ScheduledDays))
		gotStates = append(gotStates, state.State)
		now = state.DueDate
	}

	wantIntervals := []int{0, 2, 11, 46, 163, 498, 0, 0, 2, 4, 7, 12, 21}
	wantStates := []int{1, 2, 2, 2, 2, 2, 3, 3, 2, 2, 2, 2, 2}
	if !reflect.DeepEqual(gotIntervals, wantIntervals) {
		t.Fatalf("unexpected scheduled day sequence: got=%v want=%v", gotIntervals, wantIntervals)
	}
	if !reflect.DeepEqual(gotStates, wantStates) {
		t.Fatalf("unexpected state sequence: got=%v want=%v", gotStates, wantStates)
	}
}

func TestDueRetrievabilityUsesDueTimeProbability(t *testing.T) {
	engine := NewEngine()
	now := time.Date(2022, 11, 29, 12, 30, 0, 0, time.UTC)
	state := model.FSRSState{DueDate: now}

	first := engine.Review(state, Good, now)
	second := engine.Review(first, Good, first.DueDate)
	third := engine.Review(second, Good, second.DueDate)

	if math.Abs(first.Retrievability-0.9995) > 0.0006 {
		t.Fatalf("expected first due retrievability close to 0.9995, got %.4f", first.Retrievability)
	}
	if math.Abs(second.Retrievability-0.9095) > 0.0010 {
		t.Fatalf("expected second due retrievability close to 0.9095, got %.4f", second.Retrievability)
	}
	if math.Abs(third.Retrievability-0.8998) > 0.0010 {
		t.Fatalf("expected third due retrievability close to 0.8998, got %.4f", third.Retrievability)
	}
}
