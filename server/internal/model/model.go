package model

import "time"

type User struct {
	ID           string    `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	DisplayName  string    `json:"display_name"`
	CreatedAt    time.Time `json:"created_at"`
}

type Folder struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Deck struct {
	ID               string    `json:"id"`
	UserID           string    `json:"user_id"`
	FolderID         string    `json:"folder_id,omitempty"`
	Name             string    `json:"name"`
	Description      string    `json:"description"`
	Color            string    `json:"color"`
	Icon             string    `json:"icon"`
	ReviewOrder      string    `json:"review_order"`
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
	ID           string    `json:"id"`
	ClientID     string    `json:"client_id"`
	DeckID       string    `json:"deck_id"`
	UserID       string    `json:"user_id"`
	Title        string    `json:"title"`
	Content      string    `json:"content"`
	Front        string    `json:"front"`
	Back         string    `json:"back"`
	Tags         []string  `json:"tags"`
	Note         string    `json:"note"`
	Source       string    `json:"source"`
	StudyEnabled bool      `json:"study_enabled"`
	State        FSRSState `json:"state"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
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
	Folders    []Folder  `json:"folders"`
	Decks      []Deck    `json:"decks"`
	Cards      []Card    `json:"cards"`
	PulledAt   time.Time `json:"pulled_at"`
	ServerTime time.Time `json:"server_time"`
}

type AIGenerateRequest struct {
	Topic      string            `json:"topic"`
	Context    string            `json:"context"`
	CardCount  int               `json:"card_count"`
	Difficulty string            `json:"difficulty"`
	CardTypes  []string          `json:"card_types,omitempty"`
	Strategy   string            `json:"strategy,omitempty"`
	SourceName string            `json:"source_name,omitempty"`
	PolicyID   string            `json:"policy_id,omitempty"`
	Policy     *GenerationPolicy `json:"policy,omitempty"`
	BatchMode  bool              `json:"batch_mode,omitempty"`
}

type AIGeneratedCard struct {
	Title          string               `json:"title"`
	Content        string               `json:"content"`
	Front          string               `json:"front"`
	Back           string               `json:"back"`
	CardType       string               `json:"card_type,omitempty"`
	KnowledgePoint string               `json:"knowledge_point,omitempty"`
	SourceExcerpt  string               `json:"source_excerpt,omitempty"`
	SourceLocation string               `json:"source_location,omitempty"`
	Difficulty     string               `json:"difficulty,omitempty"`
	Tags           []string             `json:"tags"`
	Note           string               `json:"note"`
	QualityReport  *AICardQualityReport `json:"quality_report,omitempty"`
}

type AIDocumentSummary struct {
	Title       string            `json:"title"`
	MimeType    string            `json:"mime_type"`
	TextPreview string            `json:"text_preview"`
	TextLength  int               `json:"text_length"`
	PageCount   int               `json:"page_count,omitempty"`
	ChunkCount  int               `json:"chunk_count,omitempty"`
	ImageCount  int               `json:"image_count,omitempty"`
	Images      []AIImportedImage `json:"images,omitempty"`
}

type AIImportedImage struct {
	Alt      string `json:"alt,omitempty"`
	Source   string `json:"source"`
	IsRemote bool   `json:"is_remote"`
}

type AIGenerateResponse struct {
	Document *AIDocumentSummary `json:"document,omitempty"`
	Items    []AIGeneratedCard  `json:"items"`
	Policy   *GenerationPolicy  `json:"policy,omitempty"`
	Warnings []string           `json:"warnings,omitempty"`
	JobID    string             `json:"job_id,omitempty"`
}

type AIRewriteCardRequest struct {
	CardID      string `json:"card_id,omitempty"`
	Title       string `json:"title"`
	Content     string `json:"content"`
	Instruction string `json:"instruction"`
	RewriteType string `json:"rewrite_type"`
}

type AIRewriteCandidate struct {
	Title         string   `json:"title"`
	Content       string   `json:"content"`
	ChangeSummary string   `json:"change_summary"`
	QualityNotes  []string `json:"quality_notes"`
}

type AIRewriteCardResponse struct {
	Candidates []AIRewriteCandidate `json:"candidates"`
}

type AIRewriteBatchRequest struct {
	RewriteType string                 `json:"rewrite_type"`
	Instruction string                 `json:"instruction"`
	PolicyID    string                 `json:"policy_id,omitempty"`
	Policy      *GenerationPolicy      `json:"policy,omitempty"`
	Cards       []AIRewriteCardRequest `json:"cards"`
}

type AIRewriteBatchResult struct {
	CardID     string               `json:"card_id,omitempty"`
	Candidates []AIRewriteCandidate `json:"candidates"`
	Error      string               `json:"error,omitempty"`
}

type AIRewriteBatchResponse struct {
	Results []AIRewriteBatchResult `json:"results"`
}

type AICardChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type AICardReference struct {
	CardIndex int    `json:"card_index"`
	Part      string `json:"part"`
	Text      string `json:"text,omitempty"`
}

type AICardChatRequest struct {
	Topic           string              `json:"topic"`
	Instruction     string              `json:"instruction"`
	Operation       string              `json:"operation,omitempty"`
	CardCount       int                 `json:"card_count,omitempty"`
	Difficulty      string              `json:"difficulty,omitempty"`
	Messages        []AICardChatMessage `json:"messages,omitempty"`
	Items           []AIGeneratedCard   `json:"items,omitempty"`
	SelectedIndexes []int               `json:"selected_indexes,omitempty"`
	Reference       *AICardReference    `json:"reference,omitempty"`
	Policy          *GenerationPolicy   `json:"policy,omitempty"`
}

type AICardChatResponse struct {
	AssistantMessage string            `json:"assistant_message"`
	Items            []AIGeneratedCard `json:"items"`
	UpdatedIndex     *int              `json:"updated_index,omitempty"`
}

type AIGenerationJob struct {
	ID           string              `json:"id"`
	UserID       string              `json:"user_id"`
	SourceName   string              `json:"source_name,omitempty"`
	SourceType   string              `json:"source_type,omitempty"`
	Status       string              `json:"status"`
	Progress     float64             `json:"progress"`
	ErrorMessage string              `json:"error_message,omitempty"`
	Request      AIGenerateRequest   `json:"request"`
	Result       *AIGenerateResponse `json:"result,omitempty"`
	CreatedAt    time.Time           `json:"created_at"`
	UpdatedAt    time.Time           `json:"updated_at"`
}

type GenerationPolicy struct {
	ID                      string    `json:"id,omitempty"`
	UserID                  string    `json:"user_id,omitempty"`
	Name                    string    `json:"name"`
	Description             string    `json:"description,omitempty"`
	Subject                 string    `json:"subject,omitempty"`
	Audience                string    `json:"audience,omitempty"`
	AtomicityLevel          string    `json:"atomicity_level"`
	AnswerStyle             string    `json:"answer_style"`
	MaxAnswerChars          int       `json:"max_answer_chars"`
	PreferredCardTypes      []string  `json:"preferred_card_types"`
	AllowDefinitionCards    bool      `json:"allow_definition_cards"`
	AllowComparisonCards    bool      `json:"allow_comparison_cards"`
	AllowExampleCards       bool      `json:"allow_example_cards"`
	AllowMisconceptionCards bool      `json:"allow_misconception_cards"`
	SplitStrategy           string    `json:"split_strategy"`
	CoverageMode            string    `json:"coverage_mode"`
	MaxCardsPerChunk        int       `json:"max_cards_per_chunk"`
	MaxCardsTotal           int       `json:"max_cards_total"`
	RequireSourceExcerpt    bool      `json:"require_source_excerpt"`
	RequireSourceLocation   bool      `json:"require_source_location"`
	DedupeLevel             string    `json:"dedupe_level"`
	RepairMode              string    `json:"repair_mode"`
	CustomRules             string    `json:"custom_rules,omitempty"`
	CreatedAt               time.Time `json:"created_at,omitempty"`
	UpdatedAt               time.Time `json:"updated_at,omitempty"`
}

type AICardQualityReport struct {
	Score      float64              `json:"score"`
	Badges     []string             `json:"badges"`
	Violations []AIQualityViolation `json:"violations"`
	Repairable bool                 `json:"repairable"`
}

type AIQualityViolation struct {
	Code     string `json:"code"`
	Message  string `json:"message"`
	Severity string `json:"severity"`
}
