package fsrs

import (
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
	if next.Stability <= 0.1 {
		t.Fatalf("expected stability to remain meaningfully positive, got %.4f", next.Stability)
	}
}
