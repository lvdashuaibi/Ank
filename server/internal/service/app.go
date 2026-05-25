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
	if hasExternalAIConfig(s.config) {
		if items, err := s.tryGenerateCardsWithExternalAI(request); err == nil && len(items) > 0 {
			return model.AIGenerateResponse{Items: items}
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
	if cardCount > 8 {
		cardCount = 8
	}

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
		answerContext := context
		if answerContext == "" {
			answerContext = fmt.Sprintf("结合当前项目语境，以 %s 难度总结关键概念、例子与常见误区", difficulty)
		}
		prompt := fmt.Sprintf(template.front, topic)
		answer := fmt.Sprintf(template.back, topic, answerContext)
		items = append(items, model.AIGeneratedCard{
			Title:          prompt,
			Content:        composeCardContent(prompt, answer),
			Front:          prompt,
			Back:           answer,
			CardType:       "basic",
			KnowledgePoint: topic,
			SourceExcerpt:  previewText(answerContext, 160),
			Difficulty:     difficulty,
			Tags:           []string{"AI生成", topic, difficulty},
			Note:           template.note,
		})
	}

	return model.AIGenerateResponse{Items: items}
}

func (s *AppService) GenerateCardsFromDocument(request model.AIGenerateRequest, doc extractedDocument) model.AIGenerateResponse {
	request.Context = doc.Text
	if strings.TrimSpace(request.Topic) == "" {
		request.Topic = strings.TrimSuffix(doc.Title, filepath.Ext(doc.Title))
	}
	request.SourceName = doc.Title
	if strings.TrimSpace(request.Strategy) == "" {
		request.Strategy = "fsrs_friendly"
	}
	response := s.GenerateCards(request)
	response.Document = &model.AIDocumentSummary{
		Title:       doc.Title,
		MimeType:    doc.MimeType,
		TextPreview: doc.TextPreview,
		TextLength:  doc.TextLength,
		PageCount:   doc.PageCount,
	}
	return response
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
		changeSummary = "建议拆分为多张原子卡；当前候选保留原卡并压缩表达。"
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
