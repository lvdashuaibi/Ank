package service

import (
	"errors"
	"fmt"
	"hash/fnv"
	"math"
	"mime/multipart"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"

	"github.com/ank/flashcard-server/internal/config"
	"github.com/ank/flashcard-server/internal/model"
	"github.com/ank/flashcard-server/internal/pkg/fsrs"
	appjwt "github.com/ank/flashcard-server/internal/pkg/jwt"
	"github.com/ank/flashcard-server/internal/repository"
)

var (
	ErrInvalidCredentials  = errors.New("invalid credentials")
	ErrInvalidReviewRating = errors.New("invalid review rating")
)

const (
	ReviewOrderSequential = "sequential"
	ReviewOrderRandom     = "random"
)

type AppService struct {
	config *config.Config
	store  repository.Store
	logger *zap.Logger
	jwt    *appjwt.Manager
	fsrs   *fsrs.Engine
}

func NewAppService(cfg config.Config, store repository.Store, logger *zap.Logger) *AppService {
	return &AppService{
		config: &cfg,
		store:  store,
		logger: logger,
		jwt:    appjwt.NewManager(cfg.JWTSecret),
		fsrs:   fsrs.NewEngine(),
	}
}

func (s *AppService) Register(email, password, displayName string) (model.User, string, error) {
	if _, exists := s.store.FindUserByEmail(email); exists {
		return model.User{}, "", errors.New("email already exists")
	}

	hash, hashErr := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if hashErr != nil {
		return model.User{}, "", hashErr
	}

	user := model.User{
		ID:           repository.NewID(),
		Email:        strings.TrimSpace(email),
		PasswordHash: string(hash),
		DisplayName:  strings.TrimSpace(displayName),
		CreatedAt:    time.Now(),
	}

	if createUserErr := s.store.CreateUser(user); createUserErr != nil {
		return model.User{}, "", createUserErr
	}
	if createDeckErr := s.store.CreateDeck(model.Deck{
		ID:               repository.NewID(),
		UserID:           user.ID,
		Name:             "默认牌组",
		Description:      "注册后自动创建的入门牌组，用于快速开始复习。",
		Color:            "#4ECDC4",
		Icon:             "📚",
		NewCardsPerDay:   20,
		MaxReviewsPerDay: 200,
		CreatedAt:        time.Now(),
		UpdatedAt:        time.Now(),
	}); createDeckErr != nil {
		return model.User{}, "", createDeckErr
	}
	token, tokenErr := s.jwt.Issue(user.ID)
	return user, token, tokenErr
}

func (s *AppService) Login(email, password string) (model.User, string, error) {
	user, exists := s.store.FindUserByEmail(strings.TrimSpace(email))
	if !exists {
		return model.User{}, "", ErrInvalidCredentials
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return model.User{}, "", ErrInvalidCredentials
	}
	token, err := s.jwt.Issue(user.ID)
	return user, token, err
}

func (s *AppService) ParseToken(token string) (*appjwt.Claims, error) {
	return s.jwt.Parse(token)
}

func (s *AppService) ListFolders(userID string) []model.Folder {
	return s.store.ListFolders(userID)
}

func (s *AppService) CreateFolder(userID string, folder model.Folder) (model.Folder, error) {
	name := strings.TrimSpace(folder.Name)
	if name == "" {
		return model.Folder{}, errors.New("folder name is required")
	}
	now := time.Now()
	folder.ID = repository.NewID()
	folder.UserID = userID
	folder.Name = name
	folder.CreatedAt = now
	folder.UpdatedAt = now
	if err := s.store.CreateFolder(folder); err != nil {
		return model.Folder{}, err
	}
	return folder, nil
}

func (s *AppService) GetFolder(userID, folderID string) (model.Folder, error) {
	return s.store.GetFolder(userID, folderID)
}

func (s *AppService) UpdateFolder(userID, folderID string, request model.Folder) (model.Folder, error) {
	folder, err := s.store.GetFolder(userID, folderID)
	if err != nil {
		return model.Folder{}, err
	}
	name := strings.TrimSpace(request.Name)
	if name == "" {
		return model.Folder{}, errors.New("folder name is required")
	}
	folder.Name = name
	folder.UpdatedAt = time.Now()
	if err := s.store.UpdateFolder(folder); err != nil {
		return model.Folder{}, err
	}
	return folder, nil
}

func (s *AppService) DeleteFolder(userID, folderID string) error {
	return s.store.DeleteFolder(userID, folderID)
}

func (s *AppService) ListDecks(userID string) []model.Deck {
	return s.store.ListDecks(userID)
}

func (s *AppService) CreateDeck(userID string, deck model.Deck) (model.Deck, error) {
	if deck.FolderID != "" {
		if _, err := s.store.GetFolder(userID, deck.FolderID); err != nil {
			return model.Deck{}, err
		}
	}
	now := time.Now()
	deck.ID = repository.NewID()
	deck.UserID = userID
	deck.FolderID = strings.TrimSpace(deck.FolderID)
	deck.CreatedAt = now
	deck.UpdatedAt = now
	deck.ReviewOrder = normalizeReviewOrder(deck.ReviewOrder)
	if deck.NewCardsPerDay == 0 {
		deck.NewCardsPerDay = 20
	}
	if deck.MaxReviewsPerDay == 0 {
		deck.MaxReviewsPerDay = 200
	}
	if err := s.store.CreateDeck(deck); err != nil {
		return model.Deck{}, err
	}
	return deck, nil
}

func (s *AppService) GetDeck(userID, deckID string) (model.Deck, error) {
	return s.store.GetDeck(userID, deckID)
}

func (s *AppService) UpdateDeck(userID, deckID string, request model.Deck) (model.Deck, error) {
	deck, err := s.store.GetDeck(userID, deckID)
	if err != nil {
		return model.Deck{}, err
	}
	deck.Name = request.Name
	deck.Description = request.Description
	deck.Color = request.Color
	deck.Icon = request.Icon
	deck.FolderID = strings.TrimSpace(request.FolderID)
	if deck.FolderID != "" {
		if _, err := s.store.GetFolder(userID, deck.FolderID); err != nil {
			return model.Deck{}, err
		}
	}
	deck.ReviewOrder = normalizeReviewOrder(request.ReviewOrder)
	if request.NewCardsPerDay > 0 {
		deck.NewCardsPerDay = request.NewCardsPerDay
	}
	if request.MaxReviewsPerDay > 0 {
		deck.MaxReviewsPerDay = request.MaxReviewsPerDay
	}
	deck.UpdatedAt = time.Now()
	if err := s.store.UpdateDeck(deck); err != nil {
		return model.Deck{}, err
	}
	return deck, nil
}

func (s *AppService) DeleteDeck(userID, deckID string) error {
	return s.store.DeleteDeck(userID, deckID)
}

func (s *AppService) ListCards(userID, deckID string) []model.Card {
	return sanitizeCards(s.store.ListCards(userID, deckID))
}

func (s *AppService) GetCard(userID, cardID string) (model.Card, error) {
	card, err := s.store.GetCard(userID, cardID)
	if err != nil {
		return model.Card{}, err
	}
	return sanitizeCard(card), nil
}

func (s *AppService) CreateCard(userID, deckID string, card model.Card) (model.Card, error) {
	if _, err := s.store.GetDeck(userID, deckID); err != nil {
		return model.Card{}, err
	}

	card.ClientID = strings.TrimSpace(card.ClientID)
	if card.ClientID != "" {
		existing, err := s.store.GetCardByClientID(userID, card.ClientID)
		if err == nil {
			return existing, nil
		}
		if !errors.Is(err, repository.ErrNotFound) {
			return model.Card{}, err
		}
	}

	now := time.Now()
	card.ID = repository.NewID()
	card.UserID = userID
	card.DeckID = deckID
	card.Source = "manual"
	card.CreatedAt = now
	card.UpdatedAt = now
	if card.State.DueDate.IsZero() {
		card.State = model.FSRSState{DueDate: now}
	}
	card.State = sanitizeFSRSState(card.State, now)
	applyCardContentCompat(&card)
	if err := s.store.CreateCard(card); err != nil {
		return model.Card{}, err
	}
	return sanitizeCard(card), nil
}

func (s *AppService) UpdateCard(userID, cardID string, request model.Card) (model.Card, error) {
	card, err := s.store.GetCard(userID, cardID)
	if err != nil {
		return model.Card{}, err
	}
	card.ClientID = firstNonEmpty(request.ClientID, card.ClientID, card.ID)
	card.Title = strings.TrimSpace(request.Title)
	card.Content = strings.TrimSpace(request.Content)
	card.Front = request.Front
	card.Back = request.Back
	card.Tags = request.Tags
	card.Note = request.Note
	card.StudyEnabled = request.StudyEnabled
	card.UpdatedAt = time.Now()
	card.State = sanitizeFSRSState(card.State, card.UpdatedAt)
	applyCardContentCompat(&card)
	if err := s.store.UpdateCard(card); err != nil {
		return model.Card{}, err
	}
	return sanitizeCard(card), nil
}

func (s *AppService) DeleteCard(userID, cardID string) error {
	return s.store.DeleteCard(userID, cardID)
}

func (s *AppService) DueCards(userID, deckID string) []model.Card {
	now := time.Now()
	cards := sanitizeCards(s.store.ListDueCards(userID, deckID, now))
	if len(cards) == 0 {
		return cards
	}

	if deckID != "" {
		deck, err := s.store.GetDeck(userID, deckID)
		if err != nil {
			return selectDueCards(cards, nil, "", false)
		}
		return selectDueCards(cards, &deck, reviewDayKey(now), true)
	}

	decks := s.store.ListDecks(userID)
	deckByID := make(map[string]model.Deck, len(decks))
	for _, deck := range decks {
		deckByID[deck.ID] = deck
	}
	return selectDueCardsByDeck(cards, deckByID, "", false)
}

func (s *AppService) SubmitReview(userID, cardID string, rating int, durationMS int) (model.Card, error) {
	return s.SubmitReviewAt(userID, cardID, rating, durationMS, time.Now())
}

func (s *AppService) SubmitReviewAt(userID, cardID string, rating int, durationMS int, reviewedAt time.Time) (model.Card, error) {
	if !fsrs.IsValidReviewRating(rating) {
		return model.Card{}, ErrInvalidReviewRating
	}
	if reviewedAt.IsZero() {
		reviewedAt = time.Now()
	}

	card, err := s.store.GetCard(userID, cardID)
	if err != nil {
		return model.Card{}, err
	}

	nextState := s.fsrs.Review(card.State, fsrs.ReviewRating(rating), reviewedAt)
	nextState = sanitizeFSRSState(nextState, reviewedAt)
	beforeState := card.State.State
	card.State = nextState
	card.UpdatedAt = reviewedAt
	if err := s.store.UpdateCard(card); err != nil {
		return model.Card{}, err
	}

	if err := s.store.AppendReviewLog(model.ReviewLog{
		ID:          repository.NewID(),
		CardID:      card.ID,
		UserID:      userID,
		Rating:      rating,
		ReviewedAt:  reviewedAt,
		DurationMS:  durationMS,
		StateBefore: beforeState,
		StateAfter:  nextState.State,
	}); err != nil {
		return model.Card{}, err
	}

	return sanitizeCard(card), nil
}

func (s *AppService) SyncPush(userID string, request model.SyncPushRequest) model.SyncPushResponse {
	response := model.SyncPushResponse{
		Errors:  make([]string, 0),
		Results: make([]model.SyncOperationResult, 0, len(request.Operations)),
	}

	for _, operation := range request.Operations {
		if operation.OccurredAt.IsZero() {
			operation.OccurredAt = time.Now()
		}

		recordFailure := func(message string) {
			response.FailedCount++
			response.Errors = append(response.Errors, message)
			response.Results = append(response.Results, model.SyncOperationResult{
				OperationID: operation.ID,
				Applied:     false,
				Error:       message,
			})
		}

		recordSuccess := func() {
			response.AppliedCount++
			response.Results = append(response.Results, model.SyncOperationResult{
				OperationID: operation.ID,
				Applied:     true,
			})
		}

		switch operation.Type {
		case "create_card":
			deckID, _ := operation.Payload["deck_id"].(string)
			if deckID == "" {
				recordFailure("create_card missing deck_id")
				continue
			}

			card := model.Card{
				ClientID:     firstNonEmpty(stringValue(operation.Payload["client_id"]), operation.ID),
				Title:        stringValue(operation.Payload["title"]),
				Content:      stringValue(operation.Payload["content"]),
				Front:        stringValue(operation.Payload["front"]),
				Back:         stringValue(operation.Payload["back"]),
				Note:         stringValue(operation.Payload["note"]),
				Tags:         stringListValue(operation.Payload["tags"]),
				StudyEnabled: boolValue(operation.Payload["study_enabled"]),
				State:        fsrsStateValue(operation.Payload["state"]),
			}
			if _, err := s.CreateCard(userID, deckID, card); err != nil {
				recordFailure(fmt.Sprintf("create_card failed: %v", err))
				continue
			}
			recordSuccess()

		case "update_card":
			cardID, _ := operation.Payload["card_id"].(string)
			if cardID == "" {
				recordFailure("update_card missing card_id")
				continue
			}
			card := model.Card{
				ClientID:     firstNonEmpty(stringValue(operation.Payload["client_id"]), cardID),
				Title:        stringValue(operation.Payload["title"]),
				Content:      stringValue(operation.Payload["content"]),
				Front:        stringValue(operation.Payload["front"]),
				Back:         stringValue(operation.Payload["back"]),
				Note:         stringValue(operation.Payload["note"]),
				Tags:         stringListValue(operation.Payload["tags"]),
				StudyEnabled: boolValue(operation.Payload["study_enabled"]),
			}
			if _, err := s.UpdateCard(userID, cardID, card); err != nil {
				recordFailure(fmt.Sprintf("update_card failed: %v", err))
				continue
			}
			recordSuccess()

		case "delete_card":
			cardID, _ := operation.Payload["card_id"].(string)
			if cardID == "" {
				recordFailure("delete_card missing card_id")
				continue
			}
			if err := s.DeleteCard(userID, cardID); err != nil {
				recordFailure(fmt.Sprintf("delete_card failed: %v", err))
				continue
			}
			recordSuccess()

		case "submit_review":
			cardID, _ := operation.Payload["card_id"].(string)
			if cardID == "" {
				recordFailure("submit_review missing card_id")
				continue
			}

			rating := intValue(operation.Payload["rating"])
			if _, err := s.SubmitReviewAt(userID, cardID, rating, 0, operation.OccurredAt); err != nil {
				recordFailure(fmt.Sprintf("submit_review failed: %v", err))
				continue
			}
			recordSuccess()

		default:
			recordFailure("unsupported sync operation: " + operation.Type)
		}
	}

	if len(response.Errors) == 0 {
		response.Errors = nil
	}
	return response
}

func (s *AppService) SyncPull(userID string) model.SyncPullResponse {
	folders := s.store.ListFolders(userID)
	sort.Slice(folders, func(i, j int) bool {
		return folders[i].CreatedAt.Before(folders[j].CreatedAt)
	})

	decks := s.store.ListDecks(userID)
	sort.Slice(decks, func(i, j int) bool {
		return decks[i].CreatedAt.Before(decks[j].CreatedAt)
	})

	cards := make([]model.Card, 0)
	for _, deck := range decks {
		cards = append(cards, s.store.ListCards(userID, deck.ID)...)
	}
	sort.Slice(cards, func(i, j int) bool {
		return cards[i].UpdatedAt.Before(cards[j].UpdatedAt)
	})

	now := time.Now()
	return model.SyncPullResponse{
		Folders:    folders,
		Decks:      decks,
		Cards:      sanitizeCards(cards),
		PulledAt:   now,
		ServerTime: now,
	}
}

func (s *AppService) ListGenerationPolicies(userID string) []model.GenerationPolicy {
	return s.store.ListGenerationPolicies(userID)
}

func (s *AppService) CreateGenerationPolicy(userID string, policy model.GenerationPolicy) (model.GenerationPolicy, error) {
	now := time.Now()
	policy = effectiveGenerationPolicy(model.AIGenerateRequest{Policy: &policy})
	policy.ID = repository.NewID()
	policy.UserID = userID
	policy.CreatedAt = now
	policy.UpdatedAt = now
	if strings.TrimSpace(policy.Name) == "" {
		policy.Name = "自定义拆卡规则"
	}
	if err := s.store.CreateGenerationPolicy(policy); err != nil {
		return model.GenerationPolicy{}, err
	}
	return policy, nil
}

func (s *AppService) GetGenerationPolicy(userID, policyID string) (model.GenerationPolicy, error) {
	return s.store.GetGenerationPolicy(userID, policyID)
}

func (s *AppService) UpdateGenerationPolicy(userID, policyID string, request model.GenerationPolicy) (model.GenerationPolicy, error) {
	current, err := s.store.GetGenerationPolicy(userID, policyID)
	if err != nil {
		return model.GenerationPolicy{}, err
	}
	request.ID = current.ID
	request.UserID = current.UserID
	request.CreatedAt = current.CreatedAt
	request.UpdatedAt = time.Now()
	policy := effectiveGenerationPolicy(model.AIGenerateRequest{Policy: &request})
	policy.ID = current.ID
	policy.UserID = current.UserID
	policy.CreatedAt = current.CreatedAt
	policy.UpdatedAt = request.UpdatedAt
	if err := s.store.UpdateGenerationPolicy(policy); err != nil {
		return model.GenerationPolicy{}, err
	}
	return policy, nil
}

func (s *AppService) DeleteGenerationPolicy(userID, policyID string) error {
	return s.store.DeleteGenerationPolicy(userID, policyID)
}

func (s *AppService) CreateAIGenerationJob(userID string, request model.AIGenerateRequest) (model.AIGenerationJob, error) {
	now := time.Now()
	job := model.AIGenerationJob{
		ID:         repository.NewID(),
		UserID:     userID,
		SourceName: request.SourceName,
		SourceType: "text",
		Status:     "running",
		Progress:   0,
		Request:    request,
		CreatedAt:  now,
		UpdatedAt:  now,
	}
	if err := s.store.CreateAIGenerationJob(job); err != nil {
		return model.AIGenerationJob{}, err
	}
	result := s.GenerateCards(request)
	job.Status = "succeeded"
	job.Progress = 1
	job.Result = &result
	job.UpdatedAt = time.Now()
	if err := s.store.UpdateAIGenerationJob(job); err != nil {
		return model.AIGenerationJob{}, err
	}
	return job, nil
}

func (s *AppService) GetAIGenerationJob(userID, jobID string) (model.AIGenerationJob, error) {
	return s.store.GetAIGenerationJob(userID, jobID)
}

func sanitizeCards(cards []model.Card) []model.Card {
	out := make([]model.Card, 0, len(cards))
	for _, card := range cards {
		out = append(out, sanitizeCard(card))
	}
	return out
}

func sanitizeCard(card model.Card) model.Card {
	now := card.UpdatedAt
	if now.IsZero() {
		now = time.Now()
	}
	card.State = sanitizeFSRSState(card.State, now)
	return card
}

func sanitizeFSRSState(state model.FSRSState, now time.Time) model.FSRSState {
	state.Difficulty = clampFinite(state.Difficulty, 1, 10, 1)
	state.Stability = positiveFinite(state.Stability, 0.1)
	state.Retrievability = clampFinite(state.Retrievability, 0, 1, 0)
	state.ElapsedDays = nonNegativeFiniteFloat(state.ElapsedDays)
	state.ScheduledDays = nonNegativeFiniteFloat(state.ScheduledDays)
	if state.DueDate.IsZero() {
		state.DueDate = now
	}
	return state
}

func clampFinite(value, minValue, maxValue, fallback float64) float64 {
	if math.IsNaN(value) || math.IsInf(value, 0) {
		return fallback
	}
	if value < minValue {
		return minValue
	}
	if value > maxValue {
		return maxValue
	}
	return value
}

func positiveFinite(value, fallback float64) float64 {
	if math.IsNaN(value) || math.IsInf(value, 0) || value <= 0 {
		return fallback
	}
	return value
}

func nonNegativeFiniteFloat(value float64) float64 {
	if math.IsNaN(value) || math.IsInf(value, 0) || value < 0 {
		return 0
	}
	return value
}

func selectDueCards(cards []model.Card, deck *model.Deck, dayKey string, respectDeckOrder bool) []model.Card {
	deckByID := map[string]model.Deck{}
	if deck != nil {
		deckByID[deck.ID] = *deck
	}
	return selectDueCardsByDeck(cards, deckByID, dayKey, respectDeckOrder)
}

func selectDueCardsByDeck(cards []model.Card, deckByID map[string]model.Deck, dayKey string, respectDeckOrder bool) []model.Card {
	grouped := make(map[string][]model.Card)
	for _, card := range cards {
		grouped[card.DeckID] = append(grouped[card.DeckID], card)
	}

	learningCards := make([]model.Card, 0)
	reviewCards := make([]model.Card, 0)
	newCards := make([]model.Card, 0)

	for deckID, deckCards := range grouped {
		deck, ok := deckByID[deckID]
		if !ok {
			deck = model.Deck{
				ID:               deckID,
				ReviewOrder:      ReviewOrderSequential,
				NewCardsPerDay:   20,
				MaxReviewsPerDay: 200,
			}
		}
		selectedLearning, selectedReview, selectedNew := selectDeckQueue(deckCards, deck, dayKey, respectDeckOrder)
		learningCards = append(learningCards, selectedLearning...)
		reviewCards = append(reviewCards, selectedReview...)
		newCards = append(newCards, selectedNew...)
	}

	if !respectDeckOrder {
		sort.Slice(learningCards, func(i, j int) bool {
			return compareReviewCards(learningCards[i], learningCards[j]) < 0
		})
		sort.Slice(reviewCards, func(i, j int) bool {
			return compareReviewCards(reviewCards[i], reviewCards[j]) < 0
		})
		sort.Slice(newCards, func(i, j int) bool {
			return compareNewCards(newCards[i], newCards[j]) < 0
		})
	}

	return append(append(learningCards, reviewCards...), newCards...)
}

func selectDeckQueue(cards []model.Card, deck model.Deck, dayKey string, respectDeckOrder bool) ([]model.Card, []model.Card, []model.Card) {
	learningCards := make([]model.Card, 0)
	reviewCards := make([]model.Card, 0)
	newCards := make([]model.Card, 0)

	for _, card := range cards {
		switch card.State.State {
		case 1, 3:
			learningCards = append(learningCards, card)
		case 2:
			reviewCards = append(reviewCards, card)
		default:
			newCards = append(newCards, card)
		}
	}

	if respectDeckOrder && normalizeReviewOrder(deck.ReviewOrder) == ReviewOrderRandom {
		sortCardsByStableRandom(learningCards, deck.ID, dayKey, "learning")
		sortCardsByStableRandom(reviewCards, deck.ID, dayKey, "review")
		sortCardsByStableRandom(newCards, deck.ID, dayKey, "new")
	} else {
		sort.Slice(learningCards, func(i, j int) bool {
			return compareReviewCards(learningCards[i], learningCards[j]) < 0
		})
		sort.Slice(reviewCards, func(i, j int) bool {
			return compareReviewCards(reviewCards[i], reviewCards[j]) < 0
		})
		sort.Slice(newCards, func(i, j int) bool {
			return compareNewCards(newCards[i], newCards[j]) < 0
		})
	}

	maxReviewsPerDay := deck.MaxReviewsPerDay
	if maxReviewsPerDay < 0 {
		maxReviewsPerDay = 0
	}
	newCardsPerDay := deck.NewCardsPerDay
	if newCardsPerDay < 0 {
		newCardsPerDay = 0
	}

	if len(reviewCards) > maxReviewsPerDay {
		reviewCards = reviewCards[:maxReviewsPerDay]
	}
	if len(newCards) > newCardsPerDay {
		newCards = newCards[:newCardsPerDay]
	}

	return learningCards, reviewCards, newCards
}

func compareReviewCards(left, right model.Card) int {
	if left.State.DueDate.Before(right.State.DueDate) {
		return -1
	}
	if right.State.DueDate.Before(left.State.DueDate) {
		return 1
	}
	leftReference := left.State.LastReviewAt
	if leftReference.IsZero() {
		leftReference = left.CreatedAt
	}
	rightReference := right.State.LastReviewAt
	if rightReference.IsZero() {
		rightReference = right.CreatedAt
	}
	if leftReference.Before(rightReference) {
		return -1
	}
	if rightReference.Before(leftReference) {
		return 1
	}
	if left.CreatedAt.Before(right.CreatedAt) {
		return -1
	}
	if right.CreatedAt.Before(left.CreatedAt) {
		return 1
	}
	return strings.Compare(left.ID, right.ID)
}

func compareNewCards(left, right model.Card) int {
	if left.CreatedAt.Before(right.CreatedAt) {
		return -1
	}
	if right.CreatedAt.Before(left.CreatedAt) {
		return 1
	}
	return strings.Compare(left.ID, right.ID)
}

func reviewDayKey(value time.Time) string {
	local := value.Local()
	return local.Format("2006-01-02")
}

func normalizeReviewOrder(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case ReviewOrderRandom:
		return ReviewOrderRandom
	default:
		return ReviewOrderSequential
	}
}

func sortCardsByStableRandom(cards []model.Card, deckID, dayKey, group string) {
	sort.Slice(cards, func(i, j int) bool {
		return stableReviewOrderValue(deckID, dayKey, group, cards[i].ID) <
			stableReviewOrderValue(deckID, dayKey, group, cards[j].ID)
	})
}

func stableReviewOrderValue(deckID, dayKey, group, cardID string) uint64 {
	hash := fnv.New64a()
	_, _ = hash.Write([]byte(deckID))
	_, _ = hash.Write([]byte{0})
	_, _ = hash.Write([]byte(dayKey))
	_, _ = hash.Write([]byte{0})
	_, _ = hash.Write([]byte(group))
	_, _ = hash.Write([]byte{0})
	_, _ = hash.Write([]byte(cardID))
	return hash.Sum64()
}

func (s *AppService) GenerateCards(request model.AIGenerateRequest) model.AIGenerateResponse {
	policy := effectiveGenerationPolicy(request)
	if hasExternalAIConfig(s.config) {
		if items, err := s.tryGenerateCardsWithExternalAI(request); err == nil && len(items) > 0 {
			items = repairGeneratedCardsForPolicy(items, policy)
			items = attachQualityReports(items, policy)
			return model.AIGenerateResponse{Items: items, Policy: &policy}
		}
	}

	topic := strings.TrimSpace(request.Topic)
	context := strings.TrimSpace(request.Context)
	difficulty := strings.TrimSpace(request.Difficulty)
	if topic == "" {
		topic = "未命名主题"
	}
	if difficulty == "" {
		difficulty = "normal"
	}

	cardCount := request.CardCount
	if cardCount <= 0 {
		cardCount = 3
	}
	if cardCount > policy.MaxCardsTotal {
		cardCount = policy.MaxCardsTotal
	}
	if cardCount > 8 && !request.BatchMode {
		cardCount = 8
	}

	facts := extractAtomicFacts(context, topic)
	templates := []struct {
		front string
		back  string
		note  string
	}{
		{
			front: "%s 的核心定义是什么？",
			back:  "%s 的核心定义可以概括为：%s",
			note:  "建议先用自己的话复述定义，再和答案比对。",
		},
		{
			front: "%s 的一个典型应用场景是什么？",
			back:  "%s 的典型应用场景包括：%s",
			note:  "可继续补充你在项目中的真实案例。",
		},
		{
			front: "%s 最容易混淆的点是什么？",
			back:  "%s 最容易混淆的点通常在于：%s",
			note:  "适合配合错误案例一起记忆。",
		},
		{
			front: "如果你要向新人解释 %s，你会先强调什么？",
			back:  "解释 %s 时，优先强调：%s",
			note:  "可以把这张卡片改成更口语化的表述。",
		},
	}

	items := make([]model.AIGeneratedCard, 0, cardCount)
	for i := 0; i < cardCount; i++ {
		template := templates[i%len(templates)]
		cardType := "basic"
		if len(policy.PreferredCardTypes) > 0 {
			cardType = policy.PreferredCardTypes[i%len(policy.PreferredCardTypes)]
		}
		answerContext := context
		if len(facts) > 0 {
			answerContext = facts[i%len(facts)]
		}
		if answerContext == "" {
			answerContext = fmt.Sprintf("结合当前项目语境，以 %s 难度总结关键概念、例子与常见误区", difficulty)
		}
		prompt := fmt.Sprintf(template.front, topic)
		answer := fmt.Sprintf(template.back, topic, answerContext)
		if len(facts) > 0 {
			prompt = fallbackPromptForFact(topic, answerContext, i)
			answer = answerContext
		}
		content := composeCardContent(prompt, answer)
		if cardType == "single_choice" {
			content = composeSingleChoiceCardContent(
				prompt,
				shortChoiceOption(answerContext),
				fallbackChoiceDistractors(topic, answerContext, facts, i),
				answer,
			)
		} else if cardType == "multi_choice" {
			correct := fallbackMultiChoiceCorrectOptions(answerContext, facts, i)
			content = composeMultiChoiceCardContent(
				prompt,
				correct,
				fallbackChoiceDistractors(topic, strings.Join(correct, "；"), facts, i),
				answer,
			)
		}
		items = append(items, model.AIGeneratedCard{
			Title:          prompt,
			Content:        content,
			Front:          prompt,
			Back:           answer,
			CardType:       cardType,
			KnowledgePoint: topic,
			SourceExcerpt:  previewText(answerContext, 160),
			SourceLocation: strings.TrimSpace(request.SourceName),
			Difficulty:     difficulty,
			Tags:           []string{"AI生成", topic, difficulty},
			Note:           template.note,
		})
	}

	items = repairGeneratedCardsForPolicy(items, policy)
	items = attachQualityReports(items, policy)
	return model.AIGenerateResponse{Items: items, Policy: &policy}
}

func extractAtomicFacts(context string, topic string) []string {
	context = strings.TrimSpace(context)
	if context == "" {
		return nil
	}
	parts := strings.FieldsFunc(context, func(r rune) bool {
		switch r {
		case '\n', '。', '；', ';', '.', '!', '！', '?', '？':
			return true
		default:
			return false
		}
	})
	facts := make([]string, 0, len(parts))
	seen := map[string]struct{}{}
	for _, part := range parts {
		fact := strings.TrimSpace(part)
		fact = strings.Trim(fact, "，, ")
		if fact == "" {
			continue
		}
		key := strings.ToLower(strings.Join(strings.Fields(fact), " "))
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}
		facts = append(facts, fact)
	}
	return facts
}

func fallbackPromptForFact(topic string, fact string, index int) string {
	keyword := factKeyword(fact)
	if keyword == "" {
		keyword = fmt.Sprintf("第%d个要点", index+1)
	}
	aspects := []string{"含义", "作用", "复习要点", "考试提示", "辨析点", "应用"}
	aspect := aspects[index%len(aspects)]
	return fmt.Sprintf("%s中，%s的%s是什么？", strings.TrimSpace(topic), keyword, aspect)
}

func factKeyword(fact string) string {
	fact = strings.TrimSpace(fact)
	if fact == "" {
		return ""
	}
	cutMarkers := []string{"规定", "指导", "帮助", "强调", "定义", "是", "包括", "连接", "connect", "define", "guide", "help"}
	end := len([]rune(fact))
	for _, marker := range cutMarkers {
		if idx := strings.Index(fact, marker); idx > 0 {
			end = len([]rune(fact[:idx]))
			break
		}
	}
	runes := []rune(fact)
	if end > len(runes) {
		end = len(runes)
	}
	if end > 24 {
		end = 24
	}
	return strings.TrimSpace(string(runes[:end]))
}

func repairGeneratedCardsForPolicy(items []model.AIGeneratedCard, policy model.GenerationPolicy) []model.AIGeneratedCard {
	seenPrompts := map[string]int{}
	repaired := make([]model.AIGeneratedCard, 0, len(items))
	for _, item := range items {
		prompt, answer := splitCardContent(item.Content)
		if strings.TrimSpace(prompt) == "" {
			prompt = item.Front
		}
		if strings.TrimSpace(prompt) == "" {
			prompt = item.Title
		}
		if strings.TrimSpace(answer) == "" {
			answer = item.Back
		}
		answer = limitRunes(strings.TrimSpace(answer), policy.MaxAnswerChars)
		if isChoiceCardType(item.CardType) && !containsImplementedChoiceDSL(prompt) {
			if dsl, ok := plainChoicePromptToImplementedDSL(prompt, answer, item.CardType == "multi_choice"); ok {
				prompt = dsl
			} else if item.CardType == "single_choice" {
				prompt = composeSingleChoicePrompt(prompt, answer, fallbackChoiceDistractors(item.KnowledgePoint, answer, nil, 0))
			} else {
				correct := []string{answer}
				prompt = composeMultiChoicePrompt(prompt, correct, fallbackChoiceDistractors(item.KnowledgePoint, answer, nil, 0))
			}
		}
		key := strings.ToLower(strings.Join(strings.Fields(prompt), " "))
		if key != "" {
			seenPrompts[key]++
			if seenPrompts[key] > 1 {
				prompt = appendAngleToPrompt(prompt, seenPrompts[key])
			}
		}
		item.Title = titleFromPromptForCard(prompt)
		item.Front = prompt
		item.Back = answer
		item.Content = composeCardContent(prompt, answer)
		repaired = append(repaired, item)
	}
	return repaired
}

func limitRunes(value string, max int) string {
	value = strings.TrimSpace(value)
	if max <= 0 {
		return value
	}
	runes := []rune(value)
	if len(runes) <= max {
		return value
	}
	if max == 1 {
		return string(runes[:1])
	}
	return string(runes[:max-1]) + "…"
}

func (s *AppService) GenerateCardsFromDocument(request model.AIGenerateRequest, doc extractedDocument) model.AIGenerateResponse {
	policy := effectiveGenerationPolicy(request)
	if strings.TrimSpace(request.Topic) == "" {
		request.Topic = strings.TrimSuffix(doc.Title, filepath.Ext(doc.Title))
	}
	request.SourceName = doc.Title
	if strings.TrimSpace(request.Strategy) == "" {
		request.Strategy = "fsrs_friendly"
	}
	chunks := chunkDocument(doc, policy)
	if len(chunks) == 0 {
		request.Context = doc.Text
		chunks = []documentChunk{{
			Index:          0,
			HeadingPath:    request.Topic,
			Text:           doc.Text,
			SourceLocation: doc.Title,
		}}
	}

	remaining := policy.MaxCardsTotal
	if request.CardCount > 0 && request.CardCount < remaining {
		remaining = request.CardCount
	}
	items := make([]model.AIGeneratedCard, 0, remaining)
	for _, chunk := range chunks {
		if remaining <= 0 {
			break
		}
		chunkRequest := request
		chunkRequest.Context = chunk.Text
		chunkRequest.SourceName = firstNonEmpty(chunk.SourceLocation, chunk.HeadingPath, doc.Title)
		chunkRequest.CardCount = policy.MaxCardsPerChunk
		if chunkRequest.CardCount > remaining {
			chunkRequest.CardCount = remaining
		}
		chunkRequest.BatchMode = true
		chunkResponse := s.GenerateCards(chunkRequest)
		for _, item := range chunkResponse.Items {
			if strings.TrimSpace(item.SourceLocation) == "" {
				item.SourceLocation = chunkRequest.SourceName
			}
			if strings.TrimSpace(item.SourceExcerpt) == "" {
				item.SourceExcerpt = previewText(chunk.Text, 160)
			}
			items = append(items, item)
			remaining--
			if remaining <= 0 {
				break
			}
		}
	}
	items = attachQualityReports(items, policy)
	response := model.AIGenerateResponse{Items: items, Policy: &policy}
	response.Document = &model.AIDocumentSummary{
		Title:       doc.Title,
		MimeType:    doc.MimeType,
		TextPreview: doc.TextPreview,
		TextLength:  doc.TextLength,
		PageCount:   doc.PageCount,
		ChunkCount:  len(chunks),
		ImageCount:  doc.ImageCount,
		Images:      importedImagesFromExtracted(doc.Images),
	}
	return response
}

func importedImagesFromExtracted(images []extractedImage) []model.AIImportedImage {
	if len(images) == 0 {
		return nil
	}
	out := make([]model.AIImportedImage, 0, len(images))
	for _, image := range images {
		out = append(out, model.AIImportedImage{
			Alt:      image.Alt,
			Source:   image.Source,
			IsRemote: image.IsRemote,
		})
	}
	return out
}

func (s *AppService) GenerateCardsFromUpload(request model.AIGenerateRequest, header *multipart.FileHeader) (model.AIGenerateResponse, error) {
	doc, err := extractDocumentFromUpload(header)
	if err != nil {
		return model.AIGenerateResponse{}, err
	}
	return s.GenerateCardsFromDocument(request, doc), nil
}

func (s *AppService) RewriteCardWithAI(request model.AIRewriteCardRequest) model.AIRewriteCardResponse {
	if hasExternalAIConfig(s.config) {
		if candidates, err := s.tryRewriteCardWithExternalAI(request); err == nil && len(candidates) > 0 {
			return model.AIRewriteCardResponse{Candidates: candidates}
		}
	}

	title := strings.TrimSpace(request.Title)
	content := strings.TrimSpace(request.Content)
	prompt, answer := splitCardContent(content)
	if title == "" {
		title = firstLine(prompt)
	}
	if title == "" {
		title = "AI 优化卡片"
	}
	rewriteType := strings.TrimSpace(request.RewriteType)
	instruction := strings.TrimSpace(request.Instruction)
	if instruction == "" {
		instruction = "让卡片更适合背诵"
	}

	nextPrompt := prompt
	nextAnswer := answer
	changeSummary := "优化题干和答案，使其更聚焦、可判定。"
	switch rewriteType {
	case "simplify_answer":
		nextAnswer = firstLine(answer)
		if nextAnswer == "" {
			nextAnswer = answer
		}
		changeSummary = "压缩答案长度，减少一次复习中的记忆负担。"
	case "make_cloze":
		keyword := firstLine(answer)
		if keyword == "" {
			keyword = firstLine(prompt)
		}
		nextPrompt = strings.TrimSpace(prompt)
		if keyword != "" && !strings.Contains(nextPrompt, "{{") {
			nextPrompt = fmt.Sprintf("%s\n\n填空：{{%s}}", nextPrompt, keyword)
		}
		changeSummary = "改写为填空题，适合检查关键术语是否能主动回忆。"
	case "make_choice":
		nextPrompt = strings.TrimSpace(prompt) + "\n\n{single-choice}\n? " + firstLine(prompt) + "\n* 正确： " + firstLine(answer) + "\n- 干扰项： 相近但不准确的说法\n{/single-choice}"
		changeSummary = "改写为单选题草稿，保留正确答案并提示后续补充干扰项。"
	case "split":
		parts := splitAnswerIntoAtomicParts(answer)
		if len(parts) > 1 {
			candidates := make([]model.AIRewriteCandidate, 0, len(parts))
			for _, part := range parts {
				partTitle := firstNonEmpty(firstLine(part), title)
				partPrompt := fmt.Sprintf("%s：%s", strings.TrimSuffix(title, "？"), partTitle)
				candidates = append(candidates, model.AIRewriteCandidate{
					Title:         partTitle,
					Content:       composeCardContent(partPrompt, part),
					ChangeSummary: "拆成原子卡，每张只保留一个可自评知识点。",
					QualityNotes: []string{
						"一卡一知识点",
						"答案尽量短且可自评",
						"保存后仍由服务端 FSRS 按真实复习表现排期",
					},
				})
			}
			return model.AIRewriteCardResponse{Candidates: candidates}
		}
		changeSummary = "建议拆分为多张原子卡；当前候选保留原卡并压缩表达。"
	case "chat_refine":
		if strings.Contains(instruction, "不要改题干") {
			nextPrompt = prompt
		}
		nextAnswer = conversationalAnswerFallback(answer, instruction)
		changeSummary = "根据对话需求微调被引用的卡片内容。"
	default:
		nextPrompt = strings.TrimSuffix(strings.TrimSpace(prompt), "？") + "？"
	}
	nextContent := composeCardContent(nextPrompt, nextAnswer)
	return model.AIRewriteCardResponse{
		Candidates: []model.AIRewriteCandidate{
			{
				Title:         firstNonEmpty(firstLine(nextPrompt), title),
				Content:       nextContent,
				ChangeSummary: changeSummary,
				QualityNotes: []string{
					"一卡一知识点",
					"答案尽量短且可自评",
					"保存后仍由服务端 FSRS 按真实复习表现排期",
				},
			},
		},
	}
}

func (s *AppService) RewriteCardsWithAI(request model.AIRewriteBatchRequest) model.AIRewriteBatchResponse {
	results := make([]model.AIRewriteBatchResult, 0, len(request.Cards))
	for _, card := range request.Cards {
		if strings.TrimSpace(card.RewriteType) == "" {
			card.RewriteType = request.RewriteType
		}
		if strings.TrimSpace(card.Instruction) == "" {
			card.Instruction = request.Instruction
		}
		response := s.RewriteCardWithAI(card)
		results = append(results, model.AIRewriteBatchResult{
			CardID:     card.CardID,
			Candidates: response.Candidates,
		})
	}
	return model.AIRewriteBatchResponse{Results: results}
}

func (s *AppService) ChatCardsWithAI(request model.AICardChatRequest) model.AICardChatResponse {
	instruction := strings.TrimSpace(request.Instruction)
	if instruction == "" {
		instruction = "请根据我的需求继续设计或微调卡片。"
	}
	items := append([]model.AIGeneratedCard(nil), request.Items...)
	if request.Reference != nil && request.Reference.CardIndex >= 0 && request.Reference.CardIndex < len(items) {
		index := request.Reference.CardIndex
		item := items[index]
		quoted := referencedCardText(item, *request.Reference)
		rewrite := s.RewriteCardWithAI(model.AIRewriteCardRequest{
			Title:       item.Title,
			Content:     item.Content,
			RewriteType: "chat_refine",
			Instruction: fmt.Sprintf("%s\n\n用户引用了%s：\n%s", instruction, referencePartLabel(request.Reference.Part), quoted),
		})
		if len(rewrite.Candidates) > 0 {
			candidate := rewrite.Candidates[0]
			items[index] = model.AIGeneratedCard{
				Title:          firstNonEmpty(candidate.Title, item.Title),
				Content:        firstNonEmpty(candidate.Content, item.Content),
				Tags:           item.Tags,
				Note:           item.Note,
				CardType:       item.CardType,
				KnowledgePoint: item.KnowledgePoint,
				SourceExcerpt:  item.SourceExcerpt,
				SourceLocation: item.SourceLocation,
				Difficulty:     item.Difficulty,
			}
		}
		policy := effectiveGenerationPolicy(model.AIGenerateRequest{Policy: request.Policy})
		return model.AICardChatResponse{
			AssistantMessage: fmt.Sprintf("已根据你的要求微调第 %d 张卡片，并保留在右侧预览区。", index+1),
			Items:            attachQualityReports(items, policy),
			UpdatedIndex:     &index,
		}
	}

	cardCount := request.CardCount
	if cardCount <= 0 {
		cardCount = 4
	}
	generated := s.GenerateCards(model.AIGenerateRequest{
		Topic:      firstNonEmpty(request.Topic, "AI 对话制卡"),
		Context:    buildCardChatContext(request.Messages, items, instruction),
		CardCount:  cardCount,
		Difficulty: firstNonEmpty(request.Difficulty, "medium"),
		Policy:     request.Policy,
	})
	return model.AICardChatResponse{
		AssistantMessage: fmt.Sprintf("我根据这轮需求生成了 %d 张草稿，已放到右侧预览区。你可以继续引用其中任意一张让我微调。", len(generated.Items)),
		Items:            generated.Items,
	}
}

func referencedCardText(item model.AIGeneratedCard, ref model.AICardReference) string {
	if strings.TrimSpace(ref.Text) != "" {
		return strings.TrimSpace(ref.Text)
	}
	prompt, answer := splitCardContent(item.Content)
	switch strings.TrimSpace(ref.Part) {
	case "prompt":
		return prompt
	case "answer":
		return answer
	case "note":
		return item.Note
	default:
		return strings.TrimSpace(item.Title + "\n\n" + item.Content)
	}
}

func referencePartLabel(part string) string {
	switch strings.TrimSpace(part) {
	case "prompt":
		return "题干"
	case "answer":
		return "答案"
	case "note":
		return "备注"
	default:
		return "整张卡片"
	}
}

func buildCardChatContext(messages []model.AICardChatMessage, items []model.AIGeneratedCard, instruction string) string {
	var builder strings.Builder
	builder.WriteString("用户最新需求：")
	builder.WriteString(instruction)
	builder.WriteString("\n\n聊天上下文：\n")
	for _, message := range messages {
		if strings.TrimSpace(message.Content) == "" {
			continue
		}
		builder.WriteString(strings.TrimSpace(message.Role))
		builder.WriteString(": ")
		builder.WriteString(strings.TrimSpace(message.Content))
		builder.WriteString("\n")
	}
	if len(items) > 0 {
		builder.WriteString("\n当前草稿摘要：\n")
		for i, item := range items {
			builder.WriteString(fmt.Sprintf("%d. %s\n", i+1, firstNonEmpty(item.Title, firstLine(item.Content))))
		}
	}
	return builder.String()
}

func stringValue(value any) string {
	text, _ := value.(string)
	return strings.TrimSpace(text)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed != "" {
			return trimmed
		}
	}
	return ""
}

func splitAnswerIntoAtomicParts(answer string) []string {
	answer = strings.TrimSpace(answer)
	if answer == "" {
		return nil
	}
	replacer := strings.NewReplacer("；", "\n", ";", "\n", "。", "\n")
	lines := strings.Split(replacer.Replace(answer), "\n")
	parts := make([]string, 0, len(lines))
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts = append(parts, line)
	}
	return parts
}

func conversationalAnswerFallback(answer, instruction string) string {
	answer = strings.TrimSpace(answer)
	if answer == "" {
		answer = "需要根据题干进行自我检查。"
	}
	if strings.Contains(instruction, "口语") {
		return "可以这样记：" + strings.TrimSuffix(answer, "。") + "。"
	}
	if strings.Contains(instruction, "更短") || strings.Contains(instruction, "简短") {
		return firstNonEmpty(firstLine(answer), answer)
	}
	return strings.TrimSuffix(answer, "。") + "（已按对话要求微调）。"
}

func applyCardContentCompat(card *model.Card) {
	if card == nil {
		return
	}
	card.ClientID = firstNonEmpty(card.ClientID, card.ID)
	card.Title = strings.TrimSpace(card.Title)
	card.Content = strings.TrimSpace(card.Content)
	card.Front = strings.TrimSpace(card.Front)
	card.Back = strings.TrimSpace(card.Back)
	if card.Content == "" {
		card.Content = composeCardContent(card.Front, card.Back)
	}
	if card.Front == "" && card.Back == "" {
		prompt, answer := splitCardContent(card.Content)
		card.Front = prompt
		card.Back = answer
	}
	if card.Title == "" {
		card.Title = firstLine(card.Front)
		if card.Title == "" {
			card.Title = firstLine(card.Content)
		}
	}
}

func composeCardContent(prompt, answer string) string {
	trimmedPrompt := strings.TrimSpace(prompt)
	trimmedAnswer := strings.TrimSpace(answer)
	if trimmedAnswer == "" {
		return trimmedPrompt
	}
	if trimmedPrompt == "" {
		return "@answer\n" + trimmedAnswer + "\n@end"
	}
	return trimmedPrompt + "\n\n@answer\n" + trimmedAnswer + "\n@end"
}

func composeSingleChoiceCardContent(question, correct string, distractors []string, answer string) string {
	return composeCardContent(composeSingleChoicePrompt(question, correct, distractors), answer)
}

func composeMultiChoiceCardContent(question string, correctOptions, distractors []string, answer string) string {
	return composeCardContent(composeMultiChoicePrompt(question, correctOptions, distractors), answer)
}

func composeSingleChoicePrompt(question, correct string, distractors []string) string {
	correct = firstNonEmpty(shortChoiceOption(correct), "正确表述")
	options := compactStrings(append([]string{correct}, normalizeChoiceOptions(distractors)...))
	for len(options) < 4 {
		options = append(options, fallbackDistractorByIndex(len(options)))
	}
	var builder strings.Builder
	builder.WriteString("{single-choice}\n")
	builder.WriteString("Q: " + strings.TrimSpace(question) + "\n")
	builder.WriteString("* " + options[0] + "\n")
	for _, option := range options[1:] {
		builder.WriteString("- " + option + "\n")
	}
	builder.WriteString("{/single-choice}")
	return builder.String()
}

func composeMultiChoicePrompt(question string, correctOptions, distractors []string) string {
	correct := compactStrings(normalizeChoiceOptions(correctOptions))
	if len(correct) == 0 {
		correct = []string{"正确表述"}
	}
	options := compactStrings(append(correct, normalizeChoiceOptions(distractors)...))
	for len(options) < len(correct)+2 {
		options = append(options, fallbackDistractorByIndex(len(options)))
	}
	var builder strings.Builder
	builder.WriteString("{multi-choice}\n")
	builder.WriteString("Q: " + strings.TrimSpace(question) + "\n")
	for _, option := range correct {
		builder.WriteString("* " + option + "\n")
	}
	for _, option := range options[len(correct):] {
		builder.WriteString("- " + option + "\n")
	}
	builder.WriteString("{/multi-choice}")
	return builder.String()
}

func normalizeChoiceOptions(values []string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		option := shortChoiceOption(value)
		if option != "" {
			out = append(out, option)
		}
	}
	return out
}

func shortChoiceOption(value string) string {
	value = strings.TrimSpace(value)
	value = strings.Trim(value, "。；;，,")
	if value == "" {
		return ""
	}
	return limitRunes(value, 36)
}

func fallbackChoiceDistractors(topic, correct string, facts []string, index int) []string {
	out := make([]string, 0, 3)
	correct = strings.TrimSpace(correct)
	for offset := 1; offset <= len(facts) && len(out) < 3; offset++ {
		candidate := strings.TrimSpace(facts[(index+offset)%len(facts)])
		if candidate != "" && candidate != correct {
			out = append(out, candidate)
		}
	}
	out = append(out,
		fmt.Sprintf("只表示%s的材料名称", firstNonEmpty(strings.TrimSpace(topic), "该知识点")),
		"与学习反馈和概念理解无关",
		"只用于最终排名，不支持学习改进",
	)
	return compactStrings(out)
}

func fallbackMultiChoiceCorrectOptions(answerContext string, facts []string, index int) []string {
	correct := []string{answerContext}
	for offset := 1; offset <= len(facts) && len(correct) < 2; offset++ {
		candidate := strings.TrimSpace(facts[(index+offset)%len(facts)])
		if candidate != "" && candidate != answerContext {
			correct = append(correct, candidate)
		}
	}
	return correct
}

func fallbackDistractorByIndex(index int) string {
	options := []string{
		"与题干核心概念无关",
		"只描述表面现象",
		"把原因和结果倒置",
		"把局部条件当成完整定义",
	}
	return options[index%len(options)]
}

func isChoiceCardType(cardType string) bool {
	cardType = strings.TrimSpace(strings.ToLower(cardType))
	return cardType == "single_choice" || cardType == "multi_choice"
}

func containsImplementedChoiceDSL(content string) bool {
	return strings.Contains(content, "{single-choice}") || strings.Contains(content, "{multi-choice}")
}

func titleFromPromptForCard(prompt string) string {
	if !containsImplementedChoiceDSL(prompt) {
		return prompt
	}
	for _, line := range strings.Split(prompt, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "Q:") {
			return strings.TrimSpace(strings.TrimPrefix(trimmed, "Q:"))
		}
	}
	return firstLine(prompt)
}

func appendAngleToPrompt(prompt string, angle int) string {
	suffix := fmt.Sprintf("（角度%d）", angle)
	if !containsImplementedChoiceDSL(prompt) {
		return fmt.Sprintf("%s%s", strings.TrimSpace(prompt), suffix)
	}
	lines := strings.Split(prompt, "\n")
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "Q:") {
			lines[i] = strings.TrimRight(line, " \t") + suffix
			return strings.Join(lines, "\n")
		}
	}
	return fmt.Sprintf("%s%s", strings.TrimSpace(prompt), suffix)
}

func plainChoicePromptToImplementedDSL(prompt, answer string, forceMulti bool) (string, bool) {
	lines := strings.Split(strings.ReplaceAll(prompt, "\r\n", "\n"), "\n")
	stemLines := make([]string, 0, len(lines))
	type option struct {
		id   string
		text string
	}
	options := make([]option, 0)
	for _, line := range lines {
		id, text, ok := parseLetteredChoiceLine(line)
		if !ok {
			trimmed := strings.TrimSpace(line)
			if trimmed != "" && !strings.HasPrefix(trimmed, "正确答案") {
				stemLines = append(stemLines, trimmed)
			}
			continue
		}
		options = append(options, option{id: id, text: text})
	}
	if len(options) < 2 {
		return "", false
	}
	correctIDs := map[string]struct{}{}
	for _, opt := range options {
		if answerReferencesOption(answer, opt.id, opt.text) {
			correctIDs[opt.id] = struct{}{}
		}
	}
	if len(correctIDs) == 0 {
		return "", false
	}
	var builder strings.Builder
	if forceMulti || len(correctIDs) > 1 || strings.Contains(strings.Join(stemLines, "\n"), "多选") {
		builder.WriteString("{multi-choice}\n")
	} else {
		builder.WriteString("{single-choice}\n")
	}
	builder.WriteString("Q: " + strings.TrimSpace(strings.Join(stemLines, "\n")) + "\n")
	for _, opt := range options {
		if _, ok := correctIDs[opt.id]; ok {
			builder.WriteString("* " + opt.id + ". " + opt.text + "\n")
		} else {
			builder.WriteString("- " + opt.id + ". " + opt.text + "\n")
		}
	}
	if strings.HasPrefix(builder.String(), "{multi-choice}") {
		builder.WriteString("{/multi-choice}")
	} else {
		builder.WriteString("{/single-choice}")
	}
	return builder.String(), true
}

func parseLetteredChoiceLine(line string) (string, string, bool) {
	trimmed := strings.TrimSpace(line)
	runes := []rune(trimmed)
	if len(runes) < 3 {
		return "", "", false
	}
	letter := strings.ToUpper(string(runes[0]))
	if letter < "A" || letter > "H" {
		return "", "", false
	}
	switch runes[1] {
	case '.', '、', ')', '）':
	default:
		return "", "", false
	}
	text := strings.TrimSpace(string(runes[2:]))
	if text == "" {
		return "", "", false
	}
	return letter, text, true
}

func answerReferencesOption(answer, id, optionText string) bool {
	answer = strings.TrimSpace(answer)
	if answer == "" {
		return false
	}
	upper := strings.ToUpper(answer)
	id = strings.ToUpper(id)
	return upper == id ||
		strings.Contains(upper, id+".") ||
		strings.Contains(upper, id+"、") ||
		strings.Contains(upper, id+")") ||
		strings.Contains(upper, id+"）") ||
		strings.Contains(answer, optionText)
}

func splitCardContent(content string) (string, string) {
	lines := strings.Split(strings.ReplaceAll(content, "\r\n", "\n"), "\n")
	promptLines := make([]string, 0, len(lines))
	answerLines := make([]string, 0)
	inAnswer := false
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if !inAnswer && trimmed == "@answer" {
			inAnswer = true
			continue
		}
		if inAnswer && trimmed == "@end" {
			inAnswer = false
			continue
		}
		if inAnswer {
			answerLines = append(answerLines, line)
		} else {
			promptLines = append(promptLines, line)
		}
	}
	return strings.TrimSpace(strings.Join(promptLines, "\n")), strings.TrimSpace(strings.Join(answerLines, "\n"))
}

func firstLine(content string) string {
	for _, line := range strings.Split(strings.ReplaceAll(content, "\r\n", "\n"), "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" {
			return trimmed
		}
	}
	return ""
}

func stringListValue(value any) []string {
	raw, ok := value.([]any)
	if ok {
		tags := make([]string, 0, len(raw))
		for _, item := range raw {
			text := strings.TrimSpace(fmt.Sprintf("%v", item))
			if text != "" {
				tags = append(tags, text)
			}
		}
		return tags
	}

	stringRaw, ok := value.([]string)
	if ok {
		return stringRaw
	}
	return []string{}
}

func intValue(value any) int {
	switch typed := value.(type) {
	case int:
		return typed
	case int32:
		return int(typed)
	case int64:
		return int(typed)
	case float64:
		return int(typed)
	default:
		return 0
	}
}

func boolValue(value any) bool {
	switch typed := value.(type) {
	case bool:
		return typed
	case string:
		return strings.EqualFold(strings.TrimSpace(typed), "true")
	case int:
		return typed != 0
	case int32:
		return typed != 0
	case int64:
		return typed != 0
	case float64:
		return typed != 0
	default:
		return false
	}
}

func floatValue(value any) float64 {
	switch typed := value.(type) {
	case float32:
		return float64(typed)
	case float64:
		return typed
	case int:
		return float64(typed)
	case int32:
		return float64(typed)
	case int64:
		return float64(typed)
	default:
		return 0
	}
}

func timeValue(value any) time.Time {
	switch typed := value.(type) {
	case time.Time:
		return typed
	case string:
		if parsed, err := time.Parse(time.RFC3339, strings.TrimSpace(typed)); err == nil {
			return parsed
		}
		return time.Time{}
	default:
		return time.Time{}
	}
}

func fsrsStateValue(value any) model.FSRSState {
	raw, ok := value.(map[string]any)
	if !ok {
		return model.FSRSState{}
	}
	return model.FSRSState{
		State:          intValue(raw["state"]),
		Difficulty:     floatValue(raw["difficulty"]),
		Stability:      floatValue(raw["stability"]),
		Retrievability: floatValue(raw["retrievability"]),
		DueDate:        timeValue(raw["due_date"]),
		LastReviewAt:   timeValue(raw["last_review_at"]),
		Reps:           intValue(raw["reps"]),
		Lapses:         intValue(raw["lapses"]),
		ElapsedDays:    floatValue(raw["elapsed_days"]),
		ScheduledDays:  floatValue(raw["scheduled_days"]),
	}
}
