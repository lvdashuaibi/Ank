package model

import "time"

type User struct {
	ID           string    `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	DisplayName  string    `json:"display_name"`
	CreatedAt    time.Time `json:"created_at"`
}

type Deck struct {
	ID               string    `json:"id"`
	UserID           string    `json:"user_id"`
	Name             string    `json:"name"`
	Description      string    `json:"description"`
	Color            string    `json:"color"`
	Icon             string    `json:"icon"`
	NewCardsPerDay   int       `json:"new_cards_per_day"`
	MaxReviewsPerDay int       `json:"max_reviews_per_day"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type FSRSState struct {
	State          int       `json:"state"`
	Difficulty     float64   `json:"difficulty"`
	Stability      float64   `json:"stability"`
	Retrievability float64   `json:"retrievability"`
	DueDate        time.Time `json:"due_date"`
	LastReviewAt   time.Time `json:"last_review_at"`
	Reps           int       `json:"reps"`
	Lapses         int       `json:"lapses"`
	ElapsedDays    float64   `json:"elapsed_days"`
	ScheduledDays  float64   `json:"scheduled_days"`
}

type Card struct {
	ID        string    `json:"id"`
	ClientID  string    `json:"client_id"`
	DeckID    string    `json:"deck_id"`
	UserID    string    `json:"user_id"`
	Title     string    `json:"title"`
	Content   string    `json:"content"`
	Front     string    `json:"front"`
	Back      string    `json:"back"`
	Tags      []string  `json:"tags"`
	Note      string    `json:"note"`
	Source    string    `json:"source"`
	State     FSRSState `json:"state"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type ReviewLog struct {
	ID          string    `json:"id"`
	CardID      string    `json:"card_id"`
	UserID      string    `json:"user_id"`
	Rating      int       `json:"rating"`
	ReviewedAt  time.Time `json:"reviewed_at"`
	DurationMS  int       `json:"duration_ms"`
	StateBefore int       `json:"state_before"`
	StateAfter  int       `json:"state_after"`
}

type SyncOperation struct {
	ID         string                 `json:"id"`
	Type       string                 `json:"type"`
	ClientID   string                 `json:"client_id,omitempty"`
	OccurredAt time.Time              `json:"occurred_at"`
	Payload    map[string]interface{} `json:"payload"`
}

type SyncPushRequest struct {
	Operations []SyncOperation `json:"operations"`
}

type SyncOperationResult struct {
	OperationID string `json:"operation_id"`
	Applied     bool   `json:"applied"`
	Error       string `json:"error,omitempty"`
}

type SyncPushResponse struct {
	AppliedCount int                   `json:"applied_count"`
	FailedCount  int                   `json:"failed_count"`
	Errors       []string              `json:"errors,omitempty"`
	Results      []SyncOperationResult `json:"results,omitempty"`
}

type SyncPullResponse struct {
	Decks      []Deck    `json:"decks"`
	Cards      []Card    `json:"cards"`
	PulledAt   time.Time `json:"pulled_at"`
	ServerTime time.Time `json:"server_time"`
}

type AIGenerateRequest struct {
	Topic      string `json:"topic"`
	Context    string `json:"context"`
	CardCount  int    `json:"card_count"`
	Difficulty string `json:"difficulty"`
}

type AIGeneratedCard struct {
	Title   string   `json:"title"`
	Content string   `json:"content"`
	Front   string   `json:"front"`
	Back    string   `json:"back"`
	Tags    []string `json:"tags"`
	Note    string   `json:"note"`
}

type AIGenerateResponse struct {
	Items []AIGeneratedCard `json:"items"`
}
