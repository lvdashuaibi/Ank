package repository

import (
	"time"

	"github.com/ank/flashcard-server/internal/model"
)

type Store interface {
	CreateUser(user model.User) error
	FindUserByEmail(email string) (model.User, bool)
	GetUser(id string) (model.User, error)
	ListDecks(userID string) []model.Deck
	CreateDeck(deck model.Deck) error
	GetDeck(userID, deckID string) (model.Deck, error)
	UpdateDeck(deck model.Deck) error
	DeleteDeck(userID, deckID string) error
	ListCards(userID, deckID string) []model.Card
	GetCard(userID, cardID string) (model.Card, error)
	GetCardByClientID(userID, clientID string) (model.Card, error)
	CreateCard(card model.Card) error
	UpdateCard(card model.Card) error
	DeleteCard(userID, cardID string) error
	ListDueCards(userID, deckID string, now time.Time) []model.Card
	AppendReviewLog(log model.ReviewLog) error
	Close() error
}
