package repository

import (
	"errors"
	"sort"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/ank/flashcard-server/internal/model"
)

var ErrNotFound = errors.New("not found")

type MemoryStore struct {
	mu         sync.RWMutex
	users      map[string]model.User
	folders    map[string]model.Folder
	decks      map[string]model.Deck
	cards      map[string]model.Card
	policies   map[string]model.GenerationPolicy
	aiJobs     map[string]model.AIGenerationJob
	reviewLogs []model.ReviewLog
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		users:      make(map[string]model.User),
		folders:    make(map[string]model.Folder),
		decks:      make(map[string]model.Deck),
		cards:      make(map[string]model.Card),
		policies:   make(map[string]model.GenerationPolicy),
		aiJobs:     make(map[string]model.AIGenerationJob),
		reviewLogs: make([]model.ReviewLog, 0),
	}
}

func (s *MemoryStore) CreateUser(user model.User) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.users[user.ID] = user
	return nil
}

func (s *MemoryStore) FindUserByEmail(email string) (model.User, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, user := range s.users {
		if user.Email == email {
			return user, true
		}
	}
	return model.User{}, false
}

func (s *MemoryStore) GetUser(id string) (model.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	user, ok := s.users[id]
	if !ok {
		return model.User{}, ErrNotFound
	}
	return user, nil
}

func (s *MemoryStore) ListFolders(userID string) []model.Folder {
	s.mu.RLock()
	defer s.mu.RUnlock()
	folders := make([]model.Folder, 0)
	for _, folder := range s.folders {
		if folder.UserID == userID {
			folders = append(folders, folder)
		}
	}
	sort.Slice(folders, func(i, j int) bool {
		return folders[i].CreatedAt.Before(folders[j].CreatedAt)
	})
	return folders
}

func (s *MemoryStore) CreateFolder(folder model.Folder) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.folders[folder.ID] = folder
	return nil
}

func (s *MemoryStore) GetFolder(userID, folderID string) (model.Folder, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	folder, ok := s.folders[folderID]
	if !ok || folder.UserID != userID {
		return model.Folder{}, ErrNotFound
	}
	return folder, nil
}

func (s *MemoryStore) UpdateFolder(folder model.Folder) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.folders[folder.ID] = folder
	return nil
}

func (s *MemoryStore) DeleteFolder(userID, folderID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	folder, ok := s.folders[folderID]
	if !ok || folder.UserID != userID {
		return ErrNotFound
	}
	delete(s.folders, folderID)
	now := time.Now()
	for id, deck := range s.decks {
		if deck.UserID != userID || deck.FolderID != folderID {
			continue
		}
		deck.FolderID = ""
		deck.UpdatedAt = now
		s.decks[id] = deck
	}
	return nil
}

func (s *MemoryStore) ListDecks(userID string) []model.Deck {
	s.mu.RLock()
	defer s.mu.RUnlock()
	decks := make([]model.Deck, 0)
	for _, deck := range s.decks {
		if deck.UserID == userID {
			decks = append(decks, deck)
		}
	}
	sort.Slice(decks, func(i, j int) bool {
		return decks[i].CreatedAt.Before(decks[j].CreatedAt)
	})
	return decks
}

func (s *MemoryStore) CreateDeck(deck model.Deck) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.decks[deck.ID] = deck
	return nil
}

func (s *MemoryStore) GetDeck(userID, deckID string) (model.Deck, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	deck, ok := s.decks[deckID]
	if !ok || deck.UserID != userID {
		return model.Deck{}, ErrNotFound
	}
	return deck, nil
}

func (s *MemoryStore) UpdateDeck(deck model.Deck) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.decks[deck.ID] = deck
	return nil
}

func (s *MemoryStore) DeleteDeck(userID, deckID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	deck, ok := s.decks[deckID]
	if !ok || deck.UserID != userID {
		return ErrNotFound
	}
	deletedCardIDs := make(map[string]struct{})
	delete(s.decks, deckID)
	for id, card := range s.cards {
		if card.DeckID == deckID {
			delete(s.cards, id)
			deletedCardIDs[id] = struct{}{}
		}
	}
	s.reviewLogs = filterReviewLogs(s.reviewLogs, func(log model.ReviewLog) bool {
		_, exists := deletedCardIDs[log.CardID]
		return !exists
	})
	return nil
}

func (s *MemoryStore) ListCards(userID, deckID string) []model.Card {
	s.mu.RLock()
	defer s.mu.RUnlock()
	cards := make([]model.Card, 0)
	for _, card := range s.cards {
		if card.UserID == userID && card.DeckID == deckID {
			cards = append(cards, card)
		}
	}
	sort.Slice(cards, func(i, j int) bool {
		return cards[i].CreatedAt.Before(cards[j].CreatedAt)
	})
	return cards
}

func (s *MemoryStore) GetCard(userID, cardID string) (model.Card, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	card, ok := s.cards[cardID]
	if !ok || card.UserID != userID {
		return model.Card{}, ErrNotFound
	}
	return card, nil
}

func (s *MemoryStore) GetCardByClientID(userID, clientID string) (model.Card, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, card := range s.cards {
		if card.UserID == userID && card.ClientID == clientID {
			return card, nil
		}
	}
	return model.Card{}, ErrNotFound
}

func (s *MemoryStore) CreateCard(card model.Card) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cards[card.ID] = card
	return nil
}

func (s *MemoryStore) UpdateCard(card model.Card) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cards[card.ID] = card
	return nil
}

func (s *MemoryStore) DeleteCard(userID, cardID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	card, ok := s.cards[cardID]
	if !ok || card.UserID != userID {
		return ErrNotFound
	}
	delete(s.cards, cardID)
	s.reviewLogs = filterReviewLogs(s.reviewLogs, func(log model.ReviewLog) bool {
		return log.CardID != cardID
	})
	return nil
}

func (s *MemoryStore) ListDueCards(userID string, deckID string, now time.Time) []model.Card {
	s.mu.RLock()
	defer s.mu.RUnlock()
	cards := make([]model.Card, 0)
	for _, card := range s.cards {
		if card.UserID != userID {
			continue
		}
		if deckID != "" && card.DeckID != deckID {
			continue
		}
		if !card.StudyEnabled {
			continue
		}
		if !card.State.DueDate.After(now) {
			cards = append(cards, card)
		}
	}
	sort.Slice(cards, func(i, j int) bool {
		return cards[i].State.DueDate.Before(cards[j].State.DueDate)
	})
	return cards
}

func (s *MemoryStore) AppendReviewLog(log model.ReviewLog) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.reviewLogs = append(s.reviewLogs, log)
	return nil
}

func (s *MemoryStore) ListGenerationPolicies(userID string) []model.GenerationPolicy {
	s.mu.RLock()
	defer s.mu.RUnlock()
	policies := make([]model.GenerationPolicy, 0)
	for _, policy := range s.policies {
		if policy.UserID == userID {
			policies = append(policies, policy)
		}
	}
	sort.Slice(policies, func(i, j int) bool {
		return policies[i].CreatedAt.Before(policies[j].CreatedAt)
	})
	return policies
}

func (s *MemoryStore) CreateGenerationPolicy(policy model.GenerationPolicy) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.policies[policy.ID] = policy
	return nil
}

func (s *MemoryStore) GetGenerationPolicy(userID, policyID string) (model.GenerationPolicy, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	policy, ok := s.policies[policyID]
	if !ok || policy.UserID != userID {
		return model.GenerationPolicy{}, ErrNotFound
	}
	return policy, nil
}

func (s *MemoryStore) UpdateGenerationPolicy(policy model.GenerationPolicy) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	current, ok := s.policies[policy.ID]
	if !ok || current.UserID != policy.UserID {
		return ErrNotFound
	}
	s.policies[policy.ID] = policy
	return nil
}

func (s *MemoryStore) DeleteGenerationPolicy(userID, policyID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	policy, ok := s.policies[policyID]
	if !ok || policy.UserID != userID {
		return ErrNotFound
	}
	delete(s.policies, policyID)
	return nil
}

func (s *MemoryStore) CreateAIGenerationJob(job model.AIGenerationJob) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.aiJobs[job.ID] = job
	return nil
}

func (s *MemoryStore) ListAIGenerationJobs(userID string) []model.AIGenerationJob {
	s.mu.RLock()
	defer s.mu.RUnlock()
	jobs := make([]model.AIGenerationJob, 0)
	for _, job := range s.aiJobs {
		if job.UserID == userID {
			jobs = append(jobs, job)
		}
	}
	sort.Slice(jobs, func(i, j int) bool {
		return jobs[i].CreatedAt.After(jobs[j].CreatedAt)
	})
	return jobs
}

func (s *MemoryStore) GetAIGenerationJob(userID, jobID string) (model.AIGenerationJob, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	job, ok := s.aiJobs[jobID]
	if !ok || job.UserID != userID {
		return model.AIGenerationJob{}, ErrNotFound
	}
	return job, nil
}

func (s *MemoryStore) UpdateAIGenerationJob(job model.AIGenerationJob) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	current, ok := s.aiJobs[job.ID]
	if !ok || current.UserID != job.UserID {
		return ErrNotFound
	}
	s.aiJobs[job.ID] = job
	return nil
}

func (s *MemoryStore) Close() error {
	return nil
}

func NewID() string {
	return uuid.NewString()
}

func filterReviewLogs(
	items []model.ReviewLog,
	keep func(model.ReviewLog) bool,
) []model.ReviewLog {
	if len(items) == 0 {
		return items
	}
	filtered := make([]model.ReviewLog, 0, len(items))
	for _, item := range items {
		if keep(item) {
			filtered = append(filtered, item)
		}
	}
	return filtered
}
