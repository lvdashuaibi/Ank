package fsrs

import (
	"math"
	"time"

	"github.com/ank/flashcard-server/internal/model"
)

type ReviewRating int

const (
	Again ReviewRating = 1
	Hard  ReviewRating = 2
	Good  ReviewRating = 3
	Easy  ReviewRating = 4
)

const (
	defaultDecay            = -0.5
	defaultRequestRetention = 0.9
)

var defaultWeights = []float64{
	0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316, 1.0651, 0.0046, 1.5418,
	0.1618, 1.0190, 29.6395, 0.0613, 0.3055, 0.3206, 0.2040, 3.2197, 0.2460, 0.5110,
}

type Engine struct {
	weights []float64
}

func NewEngine() *Engine {
	return &Engine{weights: defaultWeights}
}

func IsValidReviewRating(value int) bool {
	return value >= int(Again) && value <= int(Easy)
}

func (e *Engine) Review(state model.FSRSState, rating ReviewRating, now time.Time) model.FSRSState {
	state = sanitizeState(state)
	elapsedDays := 0.0
	if !state.LastReviewAt.IsZero() {
		elapsedDays = now.Sub(state.LastReviewAt).Hours() / 24.0
	}
	if !isFinite(elapsedDays) || elapsedDays < 0 {
		elapsedDays = 0
	}

	newDifficulty := state.Difficulty
	newStability := state.Stability
	newState := state.State
	dueDate := now

	switch state.State {
	case 0:
		newDifficulty = e.initDifficulty(rating)
		newStability = e.initStability(rating)
		if rating == Again {
			newState = 1
			dueDate = now.Add(time.Minute)
		} else if rating == Hard {
			newState = 1
			dueDate = now.Add(5 * time.Minute)
		} else if rating == Easy {
			newState = 2
			dueDate = now.Add(intervalDaysToDuration(e.nextInterval(newStability)))
		} else {
			newState = 1
			dueDate = now.Add(10 * time.Minute)
		}
	case 1:
		newDifficulty = e.nextDifficulty(state.Difficulty, rating)
		newStability = e.shortTermStability(state.Stability, rating)
		switch rating {
		case Again:
			newState = 1
			dueDate = now.Add(5 * time.Minute)
		case Hard:
			newState = 1
			dueDate = now.Add(10 * time.Minute)
		case Good:
			newState = 2
			dueDate = now.Add(intervalDaysToDuration(e.nextInterval(newStability)))
		case Easy:
			goodStability := e.shortTermStability(state.Stability, Good)
			goodInterval := e.nextInterval(goodStability)
			easyInterval := math.Max(e.nextInterval(newStability), goodInterval+1)
			newState = 2
			dueDate = now.Add(intervalDaysToDuration(easyInterval))
		}
	case 3:
		newDifficulty = e.nextDifficulty(state.Difficulty, rating)
		newStability = e.shortTermStability(state.Stability, rating)
		switch rating {
		case Again, Hard:
			newState = 3
			dueDate = now.Add(10 * time.Minute)
		case Good:
			newState = 2
			dueDate = now.Add(intervalDaysToDuration(e.nextInterval(newStability)))
		case Easy:
			goodStability := e.shortTermStability(state.Stability, Good)
			goodInterval := e.nextInterval(goodStability)
			easyInterval := math.Max(e.nextInterval(newStability), goodInterval+1)
			newState = 2
			dueDate = now.Add(intervalDaysToDuration(easyInterval))
		}
	default:
		r := e.retrievability(elapsedDays, state.Stability)
		newDifficulty = e.nextDifficulty(state.Difficulty, rating)
		if rating == Again {
			newStability = e.nextStabilityOnForget(state.Difficulty, state.Stability, r)
			newState = 3
			dueDate = now.Add(10 * time.Minute)
		} else {
			newStability = e.nextStabilityOnRecall(state.Difficulty, state.Stability, r, rating)
			newState = 2
			dueDate = now.Add(intervalDaysToDuration(e.nextInterval(newStability)))
		}
	}

	return sanitizeState(model.FSRSState{
		State:          newState,
		Difficulty:     newDifficulty,
		Stability:      newStability,
		Retrievability: e.retrievability(0, newStability),
		DueDate:        dueDate,
		LastReviewAt:   now,
		Reps:           state.Reps + 1,
		Lapses:         state.Lapses + btoi(rating == Again),
		ElapsedDays:    elapsedDays,
		ScheduledDays:  dueDate.Sub(now).Hours() / 24.0,
	})
}

func (e *Engine) initStability(rating ReviewRating) float64 {
	return math.Max(e.weights[int(rating)-1], 0.1)
}

func (e *Engine) initDifficulty(rating ReviewRating) float64 {
	value := e.weights[4] - math.Exp(e.weights[5]*float64(int(rating)-1)) + 1
	return clamp(value, 1, 10)
}

func (e *Engine) nextDifficulty(difficulty float64, rating ReviewRating) float64 {
	neutral := e.initDifficulty(Easy)
	value := e.weights[7]*neutral + (1-e.weights[7])*(difficulty-e.weights[6]*float64(int(rating)-3))
	return clamp(value, 1, 10)
}

func (e *Engine) retrievability(elapsedDays, stability float64) float64 {
	if stability <= 0 {
		return 0
	}
	decay := defaultDecay
	factor := forgettingCurveFactor()
	base := 1 + factor*elapsedDays/stability
	if !isFinite(base) || base <= 0 {
		return 0
	}
	value := math.Pow(base, decay)
	if !isFinite(value) {
		return 0
	}
	return value
}

func (e *Engine) nextStabilityOnRecall(d, s, r float64, rating ReviewRating) float64 {
	hardPenalty := 1.0
	easyBonus := 1.0
	if rating == Hard {
		hardPenalty = e.weights[15]
	}
	if rating == Easy {
		easyBonus = e.weights[16]
	}
	value := s * (math.Exp(e.weights[8])*(11-d)*math.Pow(s, -e.weights[9])*(math.Exp(e.weights[10]*(1-r))-1)*hardPenalty*easyBonus + 1)
	if !isFinite(value) {
		return 0.1
	}
	return math.Max(value, 0.1)
}

func (e *Engine) shortTermStability(stability float64, rating ReviewRating) float64 {
	value := stability * math.Exp(e.weights[17]*(float64(int(rating)-3)+e.weights[18]))
	if !isFinite(value) {
		return 0.1
	}
	return math.Max(value, 0.1)
}

func (e *Engine) nextStabilityOnForget(d, s, r float64) float64 {
	value := e.weights[11] * math.Pow(d, -e.weights[12]) * (math.Pow(s+1, e.weights[13]) - 1) * math.Exp(e.weights[14]*(1-r))
	if !isFinite(value) {
		return 0.1
	}
	return math.Max(math.Min(value, s), 0.1)
}

func (e *Engine) nextInterval(stability float64) float64 {
	factor := forgettingCurveFactor()
	value := (stability / factor) * (math.Pow(defaultRequestRetention, 1/defaultDecay) - 1)
	if !isFinite(value) {
		return 1
	}
	return math.Max(math.Round(value), 1)
}

func forgettingCurveFactor() float64 {
	factor := math.Pow(defaultRequestRetention, 1/defaultDecay) - 1
	if !isFinite(factor) || factor <= 0 {
		return 0.23456790123456783
	}
	return factor
}

func intervalDaysToDuration(days float64) time.Duration {
	if !isFinite(days) || days <= 0 {
		return 24 * time.Hour
	}
	return time.Duration(math.Round(days*24)) * time.Hour
}

func clamp(value, minValue, maxValue float64) float64 {
	if !isFinite(value) {
		return minValue
	}
	return math.Max(minValue, math.Min(maxValue, value))
}

func sanitizeState(state model.FSRSState) model.FSRSState {
	state.Difficulty = clamp(state.Difficulty, 1, 10)
	state.Stability = maxFinite(state.Stability, 0.1)
	state.Retrievability = clamp(state.Retrievability, 0, 1)
	state.ElapsedDays = nonNegativeFinite(state.ElapsedDays)
	state.ScheduledDays = nonNegativeFinite(state.ScheduledDays)
	return state
}

func maxFinite(value, fallback float64) float64 {
	if !isFinite(value) || value <= 0 {
		return fallback
	}
	return value
}

func nonNegativeFinite(value float64) float64 {
	if !isFinite(value) || value < 0 {
		return 0
	}
	return value
}

func isFinite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

func btoi(value bool) int {
	if value {
		return 1
	}
	return 0
}
