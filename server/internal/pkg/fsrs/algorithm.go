package fsrs

import (
	"math"
	"time"

	"github.com/ank/flashcard-server/internal/model"
	osrfsrs "github.com/open-spaced-repetition/go-fsrs/v4"
)

type ReviewRating int

const (
	Again ReviewRating = 1
	Hard  ReviewRating = 2
	Good  ReviewRating = 3
	Easy  ReviewRating = 4
)

const (
	defaultRequestRetention = 0.9
	defaultMaximumInterval  = 36500.0
	stabilityMin            = 0.001
	stabilityMax            = 36500.0
	difficultyMin           = 1.0
	difficultyMax           = 10.0
)

var defaultWeights = []float64{
	0.2120, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194,
	0.0010, 1.8722, 0.1666, 0.7960, 1.4835, 0.0614, 0.2629,
	1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
}

type Engine struct {
	core   *osrfsrs.FSRS
	params osrfsrs.Parameters
}

func NewEngine() *Engine {
	params := osrfsrs.DefaultParam()
	params.RequestRetention = defaultRequestRetention
	params.MaximumInterval = defaultMaximumInterval
	params.EnableShortTerm = true
	params.EnableFuzz = false
	return &Engine{
		core:   osrfsrs.NewFSRS(params),
		params: params,
	}
}

func IsValidReviewRating(value int) bool {
	return value >= int(Again) && value <= int(Easy)
}

func (e *Engine) Review(state model.FSRSState, rating ReviewRating, now time.Time) model.FSRSState {
	sanitized := sanitizeState(state)
	card := e.toOfficialCard(sanitized)
	next := e.core.Next(card, now, toOfficialRating(rating))
	return e.fromOfficialCard(next.Card, now)
}

func (e *Engine) initStability(rating ReviewRating) float64 {
	return constrainStability(defaultWeights[int(rating)-1])
}

func (e *Engine) initDifficulty(rating ReviewRating) float64 {
	value := defaultWeights[4] - math.Exp(defaultWeights[5]*float64(int(rating)-1)) + 1
	return constrainDifficulty(value)
}

func (e *Engine) nextDifficulty(difficulty float64, rating ReviewRating) float64 {
	delta := -defaultWeights[6] * float64(int(rating)-3)
	next := difficulty + linearDamping(delta, difficulty)
	return constrainDifficulty(meanReversion(initDifficultyRaw(Easy), next))
}

func (e *Engine) retrievability(elapsedDays, stability float64) float64 {
	stability = constrainStability(stability)
	factor := forgettingCurveFactor(defaultWeights[20], defaultRequestRetention)
	value := math.Pow(1+factor*elapsedDays/stability, -defaultWeights[20])
	if !isFinite(value) {
		return 0
	}
	return value
}

func (e *Engine) shortTermStability(stability float64, rating ReviewRating) float64 {
	stability = constrainStability(stability)
	sinc := math.Exp(defaultWeights[17]*(float64(int(rating)-3)+defaultWeights[18])) * math.Pow(stability, -defaultWeights[19])
	if rating >= Hard && sinc < 1 {
		sinc = 1
	}
	return constrainStability(stability * sinc)
}

func (e *Engine) nextStabilityOnForget(difficulty, stability, retrievability float64) float64 {
	difficulty = constrainDifficulty(difficulty)
	stability = constrainStability(stability)
	value := defaultWeights[11] *
		math.Pow(difficulty, -defaultWeights[12]) *
		(math.Pow(stability+1, defaultWeights[13]) - 1) *
		math.Exp((1-retrievability)*defaultWeights[14])
	sCeil := stability / math.Exp(defaultWeights[17]*defaultWeights[18])
	return constrainStability(math.Min(value, sCeil))
}

func (e *Engine) nextStabilityOnRecall(difficulty, stability, retrievability float64, rating ReviewRating) float64 {
	difficulty = constrainDifficulty(difficulty)
	stability = constrainStability(stability)
	hardPenalty := 1.0
	easyBonus := 1.0
	if rating == Hard {
		hardPenalty = defaultWeights[15]
	}
	if rating == Easy {
		easyBonus = defaultWeights[16]
	}
	value := stability * (1 + math.Exp(defaultWeights[8])*
		(11-difficulty)*
		math.Pow(stability, -defaultWeights[9])*
		(math.Exp((1-retrievability)*defaultWeights[10])-1)*
		hardPenalty*
		easyBonus)
	return constrainStability(value)
}

func (e *Engine) nextInterval(stability float64) float64 {
	stability = constrainStability(stability)
	decay := -defaultWeights[20]
	factor := forgettingCurveFactor(defaultWeights[20], defaultRequestRetention)
	value := stability / factor * (math.Pow(defaultRequestRetention, 1/decay) - 1)
	if !isFinite(value) {
		return 1
	}
	return math.Max(math.Min(math.Round(value), defaultMaximumInterval), 1)
}

func (e *Engine) toOfficialCard(state model.FSRSState) osrfsrs.Card {
	return osrfsrs.Card{
		Due:           state.DueDate,
		Stability:     constrainStability(state.Stability),
		Difficulty:    constrainDifficulty(state.Difficulty),
		ElapsedDays:   uint64(nonNegativeFinite(state.ElapsedDays)),
		ScheduledDays: uint64(nonNegativeFinite(state.ScheduledDays)),
		Reps:          uint64(max(0, state.Reps)),
		Lapses:        uint64(max(0, state.Lapses)),
		State:         toOfficialState(state.State),
		LastReview:    state.LastReviewAt,
	}
}

func (e *Engine) fromOfficialCard(card osrfsrs.Card, now time.Time) model.FSRSState {
	retrievability := 0.0
	if card.State != osrfsrs.New {
		dueElapsedDays := card.Due.Sub(card.LastReview).Hours() / 24
		retrievability = e.retrievability(dueElapsedDays, card.Stability)
	}
	return sanitizeState(model.FSRSState{
		State:          int(card.State),
		Difficulty:     card.Difficulty,
		Stability:      card.Stability,
		Retrievability: retrievability,
		DueDate:        card.Due,
		LastReviewAt:   card.LastReview,
		Reps:           int(card.Reps),
		Lapses:         int(card.Lapses),
		ElapsedDays:    float64(card.ElapsedDays),
		ScheduledDays:  float64(card.ScheduledDays),
	})
}

func toOfficialState(value int) osrfsrs.State {
	switch value {
	case 1:
		return osrfsrs.Learning
	case 2:
		return osrfsrs.Review
	case 3:
		return osrfsrs.Relearning
	default:
		return osrfsrs.New
	}
}

func toOfficialRating(value ReviewRating) osrfsrs.Rating {
	switch value {
	case Again:
		return osrfsrs.Again
	case Hard:
		return osrfsrs.Hard
	case Good:
		return osrfsrs.Good
	case Easy:
		return osrfsrs.Easy
	default:
		return osrfsrs.Again
	}
}

func initDifficultyRaw(rating ReviewRating) float64 {
	return defaultWeights[4] - math.Exp(defaultWeights[5]*float64(int(rating)-1)) + 1
}

func forgettingCurveFactor(decayWeight, requestRetention float64) float64 {
	decay := -decayWeight
	factor := math.Pow(requestRetention, 1/decay) - 1
	if !isFinite(factor) || factor == 0 {
		return math.Pow(0.9, 1/-0.1542) - 1
	}
	return factor
}

func meanReversion(initial, current float64) float64 {
	return defaultWeights[7]*initial + (1-defaultWeights[7])*current
}

func linearDamping(deltaDifficulty, difficulty float64) float64 {
	return (10 - difficulty) * deltaDifficulty / 9
}

func constrainDifficulty(value float64) float64 {
	if !isFinite(value) {
		return difficultyMin
	}
	return math.Max(difficultyMin, math.Min(difficultyMax, value))
}

func constrainStability(value float64) float64 {
	if !isFinite(value) {
		return stabilityMin
	}
	return math.Max(stabilityMin, math.Min(stabilityMax, value))
}

func sanitizeState(state model.FSRSState) model.FSRSState {
	state.Difficulty = constrainDifficulty(state.Difficulty)
	state.Stability = constrainStability(state.Stability)
	state.Retrievability = clamp(state.Retrievability, 0, 1)
	state.ElapsedDays = nonNegativeFinite(state.ElapsedDays)
	state.ScheduledDays = nonNegativeFinite(state.ScheduledDays)
	return state
}

func clamp(value, minValue, maxValue float64) float64 {
	if !isFinite(value) {
		return minValue
	}
	return math.Max(minValue, math.Min(maxValue, value))
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

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
