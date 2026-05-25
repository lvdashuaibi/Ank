package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/ank/flashcard-server/internal/model"
)

type PostgresStore struct {
	db *sql.DB
}

func NewPostgresStore(databaseURL string, autoMigrate bool) (*PostgresStore, error) {
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, err
	}

	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	store := &PostgresStore{db: db}
	if autoMigrate {
		if err := store.ensureSchema(context.Background()); err != nil {
			_ = db.Close()
			return nil, err
		}
	}
	return store, nil
}

func (s *PostgresStore) Close() error {
	return s.db.Close()
}

func (s *PostgresStore) CreateUser(user model.User) error {
	_, err := s.db.Exec(
		`INSERT INTO users (id, email, password_hash, display_name, created_at)
		 VALUES ($1, $2, $3, $4, $5)`,
		user.ID, user.Email, user.PasswordHash, user.DisplayName, user.CreatedAt,
	)
	return err
}

func (s *PostgresStore) FindUserByEmail(email string) (model.User, bool) {
	var user model.User
	err := s.db.QueryRow(
		`SELECT id, email, password_hash, display_name, created_at FROM users WHERE email = $1`,
		email,
	).Scan(&user.ID, &user.Email, &user.PasswordHash, &user.DisplayName, &user.CreatedAt)
	return user, err == nil
}

func (s *PostgresStore) GetUser(id string) (model.User, error) {
	var user model.User
	err := s.db.QueryRow(
		`SELECT id, email, password_hash, display_name, created_at FROM users WHERE id = $1`,
		id,
	).Scan(&user.ID, &user.Email, &user.PasswordHash, &user.DisplayName, &user.CreatedAt)
	if err == sql.ErrNoRows {
		return model.User{}, ErrNotFound
	}
	return user, err
}

func (s *PostgresStore) ListFolders(userID string) []model.Folder {
	rows, err := s.db.Query(
		`SELECT id, user_id, name, created_at, updated_at
		 FROM folders WHERE user_id = $1 ORDER BY created_at`,
		userID,
	)
	if err != nil {
		return []model.Folder{}
	}
	defer rows.Close()

	folders := make([]model.Folder, 0)
	for rows.Next() {
		var folder model.Folder
		if err := rows.Scan(
			&folder.ID, &folder.UserID, &folder.Name,
			&folder.CreatedAt, &folder.UpdatedAt,
		); err == nil {
			folders = append(folders, folder)
		}
	}
	return folders
}

func (s *PostgresStore) CreateFolder(folder model.Folder) error {
	_, err := s.db.Exec(
		`INSERT INTO folders (id, user_id, name, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5)`,
		folder.ID, folder.UserID, folder.Name, folder.CreatedAt, folder.UpdatedAt,
	)
	return err
}

func (s *PostgresStore) GetFolder(userID, folderID string) (model.Folder, error) {
	var folder model.Folder
	err := s.db.QueryRow(
		`SELECT id, user_id, name, created_at, updated_at
		 FROM folders WHERE id = $1 AND user_id = $2`,
		folderID, userID,
	).Scan(
		&folder.ID, &folder.UserID, &folder.Name, &folder.CreatedAt, &folder.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		return model.Folder{}, ErrNotFound
	}
	return folder, err
}

func (s *PostgresStore) UpdateFolder(folder model.Folder) error {
	_, err := s.db.Exec(
		`UPDATE folders SET name = $1, updated_at = $2 WHERE id = $3`,
		folder.Name, folder.UpdatedAt, folder.ID,
	)
	return err
}

func (s *PostgresStore) DeleteFolder(userID, folderID string) error {
	tx, err := s.db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}
	defer func() {
		_ = tx.Rollback()
	}()

	if _, err := tx.Exec(
		`UPDATE decks SET folder_id = NULL, updated_at = $3
		 WHERE folder_id = $1 AND user_id = $2`,
		folderID, userID, time.Now(),
	); err != nil {
		return err
	}
	result, err := tx.Exec(
		`DELETE FROM folders WHERE id = $1 AND user_id = $2`,
		folderID, userID,
	)
	if err != nil {
		return err
	}
	affected, _ := result.RowsAffected()
	if affected == 0 {
		return ErrNotFound
	}
	return tx.Commit()
}

func (s *PostgresStore) ListDecks(userID string) []model.Deck {
	rows, err := s.db.Query(
		`SELECT id, user_id, COALESCE(folder_id, ''), name, description, color, icon, COALESCE(review_order, 'sequential'), new_cards_per_day, max_reviews_per_day, created_at, updated_at
		 FROM decks WHERE user_id = $1 ORDER BY created_at`,
		userID,
	)
	if err != nil {
		return []model.Deck{}
	}
	defer rows.Close()

	var decks []model.Deck
	for rows.Next() {
		if deck, err := scanDeck(rows); err == nil {
			decks = append(decks, deck)
		}
	}
	return decks
}

func (s *PostgresStore) CreateDeck(deck model.Deck) error {
	_, err := s.db.Exec(
		`INSERT INTO decks (id, user_id, folder_id, name, description, color, icon, review_order, new_cards_per_day, max_reviews_per_day, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
		deck.ID, deck.UserID, nullableString(deck.FolderID), deck.Name, deck.Description, deck.Color, deck.Icon,
		deck.ReviewOrder, deck.NewCardsPerDay, deck.MaxReviewsPerDay, deck.CreatedAt, deck.UpdatedAt,
	)
	return err
}

func (s *PostgresStore) GetDeck(userID, deckID string) (model.Deck, error) {
	row := s.db.QueryRow(
		`SELECT id, user_id, COALESCE(folder_id, ''), name, description, color, icon, COALESCE(review_order, 'sequential'), new_cards_per_day, max_reviews_per_day, created_at, updated_at
		 FROM decks WHERE id = $1 AND user_id = $2`,
		deckID, userID,
	)
	deck, err := scanDeck(row)
	if err == sql.ErrNoRows {
		return model.Deck{}, ErrNotFound
	}
	return deck, err
}

func (s *PostgresStore) UpdateDeck(deck model.Deck) error {
	_, err := s.db.Exec(
		`UPDATE decks
		 SET name = $1, description = $2, color = $3, icon = $4, new_cards_per_day = $5, max_reviews_per_day = $6, folder_id = $7, review_order = $8, updated_at = $9
		 WHERE id = $10`,
		deck.Name, deck.Description, deck.Color, deck.Icon, deck.NewCardsPerDay, deck.MaxReviewsPerDay, nullableString(deck.FolderID), deck.ReviewOrder, deck.UpdatedAt, deck.ID,
	)
	return err
}

func (s *PostgresStore) DeleteDeck(userID, deckID string) error {
	tx, err := s.db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}
	defer func() {
		_ = tx.Rollback()
	}()

	if _, err := tx.Exec(
		`DELETE FROM review_logs
		 WHERE user_id = $1
		   AND card_id IN (SELECT id FROM cards WHERE deck_id = $2 AND user_id = $1)`,
		userID, deckID,
	); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM cards WHERE deck_id = $1 AND user_id = $2`, deckID, userID); err != nil {
		return err
	}
	result, err := tx.Exec(`DELETE FROM decks WHERE id = $1 AND user_id = $2`, deckID, userID)
	if err != nil {
		return err
	}
	affected, _ := result.RowsAffected()
	if affected == 0 {
		return ErrNotFound
	}
	return tx.Commit()
}

func (s *PostgresStore) ListCards(userID, deckID string) []model.Card {
	rows, err := s.db.Query(
		`SELECT id, COALESCE(client_id, id), deck_id, user_id, COALESCE(title, ''), COALESCE(content, ''), front, back, tags, note, source, COALESCE(study_enabled, FALSE), created_at, updated_at,
		        state, difficulty, stability, retrievability, due_date, last_review_at, reps, lapses, elapsed_days, scheduled_days
		 FROM cards WHERE user_id = $1 AND deck_id = $2 ORDER BY created_at`,
		userID, deckID,
	)
	if err != nil {
		return []model.Card{}
	}
	defer rows.Close()

	cards := make([]model.Card, 0)
	for rows.Next() {
		if card, err := scanCard(rows); err == nil {
			cards = append(cards, card)
		}
	}
	return cards
}

func (s *PostgresStore) GetCard(userID, cardID string) (model.Card, error) {
	row := s.db.QueryRow(
		`SELECT id, COALESCE(client_id, id), deck_id, user_id, COALESCE(title, ''), COALESCE(content, ''), front, back, tags, note, source, COALESCE(study_enabled, FALSE), created_at, updated_at,
		        state, difficulty, stability, retrievability, due_date, last_review_at, reps, lapses, elapsed_days, scheduled_days
		 FROM cards WHERE id = $1 AND user_id = $2`,
		cardID, userID,
	)
	card, err := scanCard(row)
	if err == sql.ErrNoRows {
		return model.Card{}, ErrNotFound
	}
	return card, err
}

func (s *PostgresStore) GetCardByClientID(userID, clientID string) (model.Card, error) {
	row := s.db.QueryRow(
		`SELECT id, COALESCE(client_id, id), deck_id, user_id, COALESCE(title, ''), COALESCE(content, ''), front, back, tags, note, source, COALESCE(study_enabled, FALSE), created_at, updated_at,
		        state, difficulty, stability, retrievability, due_date, last_review_at, reps, lapses, elapsed_days, scheduled_days
		 FROM cards WHERE user_id = $1 AND client_id = $2
		 ORDER BY created_at
		 LIMIT 1`,
		userID, clientID,
	)
	card, err := scanCard(row)
	if err == sql.ErrNoRows {
		return model.Card{}, ErrNotFound
	}
	return card, err
}

func (s *PostgresStore) CreateCard(card model.Card) error {
	_, err := s.db.Exec(
		`INSERT INTO cards (
		   id, client_id, deck_id, user_id, title, content, front, back, tags, note, source, study_enabled, created_at, updated_at,
		   state, difficulty, stability, retrievability, due_date, last_review_at, reps, lapses, elapsed_days, scheduled_days
		 ) VALUES (
		   $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
		   $15, $16, $17, $18, $19, $20, $21, $22, $23, $24
		 )`,
		card.ID, card.ClientID, card.DeckID, card.UserID, card.Title, card.Content, card.Front, card.Back, mustJSON(card.Tags), card.Note, card.Source,
		card.StudyEnabled, card.CreatedAt, card.UpdatedAt, card.State.State, card.State.Difficulty, card.State.Stability,
		card.State.Retrievability, card.State.DueDate, nullableTime(card.State.LastReviewAt),
		card.State.Reps, card.State.Lapses, card.State.ElapsedDays, card.State.ScheduledDays,
	)
	return err
}

func (s *PostgresStore) UpdateCard(card model.Card) error {
	_, err := s.db.Exec(
		`UPDATE cards SET
		   client_id = $1, title = $2, content = $3, front = $4, back = $5, tags = $6, note = $7, source = $8, updated_at = $9, study_enabled = $10,
		   state = $11, difficulty = $12, stability = $13, retrievability = $14, due_date = $15, last_review_at = $16,
		   reps = $17, lapses = $18, elapsed_days = $19, scheduled_days = $20
		 WHERE id = $21`,
		card.ClientID, card.Title, card.Content, card.Front, card.Back, mustJSON(card.Tags), card.Note, card.Source, card.UpdatedAt, card.StudyEnabled,
		card.State.State, card.State.Difficulty, card.State.Stability, card.State.Retrievability,
		card.State.DueDate, nullableTime(card.State.LastReviewAt), card.State.Reps, card.State.Lapses,
		card.State.ElapsedDays, card.State.ScheduledDays, card.ID,
	)
	return err
}

func (s *PostgresStore) DeleteCard(userID, cardID string) error {
	tx, err := s.db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}
	defer func() {
		_ = tx.Rollback()
	}()

	if _, err := tx.Exec(`DELETE FROM review_logs WHERE card_id = $1 AND user_id = $2`, cardID, userID); err != nil {
		return err
	}
	result, err := tx.Exec(`DELETE FROM cards WHERE id = $1 AND user_id = $2`, cardID, userID)
	if err != nil {
		return err
	}
	affected, _ := result.RowsAffected()
	if affected == 0 {
		return ErrNotFound
	}
	return tx.Commit()
}

func (s *PostgresStore) ListDueCards(userID, deckID string, now time.Time) []model.Card {
	query := `SELECT id, COALESCE(client_id, id), deck_id, user_id, COALESCE(title, ''), COALESCE(content, ''), front, back, tags, note, source, COALESCE(study_enabled, FALSE), created_at, updated_at,
	                 state, difficulty, stability, retrievability, due_date, last_review_at, reps, lapses, elapsed_days, scheduled_days
	          FROM cards WHERE user_id = $1 AND due_date <= $2 AND study_enabled = TRUE`
	args := []any{userID, now}
	if deckID != "" {
		query += ` AND deck_id = $3`
		args = append(args, deckID)
	}
	query += ` ORDER BY due_date`

	rows, err := s.db.Query(query, args...)
	if err != nil {
		return []model.Card{}
	}
	defer rows.Close()

	cards := make([]model.Card, 0)
	for rows.Next() {
		if card, err := scanCard(rows); err == nil {
			cards = append(cards, card)
		}
	}
	return cards
}

func (s *PostgresStore) AppendReviewLog(log model.ReviewLog) error {
	_, err := s.db.Exec(
		`INSERT INTO review_logs (id, card_id, user_id, rating, reviewed_at, duration_ms, state_before, state_after)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		log.ID, log.CardID, log.UserID, log.Rating, log.ReviewedAt, log.DurationMS, log.StateBefore, log.StateAfter,
	)
	return err
}

func (s *PostgresStore) ensureSchema(ctx context.Context) error {
	schema := `
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  display_name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS folders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS decks (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  folder_id TEXT,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  color TEXT NOT NULL,
  icon TEXT NOT NULL,
  review_order TEXT NOT NULL DEFAULT 'sequential',
  new_cards_per_day INT NOT NULL,
  max_reviews_per_day INT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS cards (
  id TEXT PRIMARY KEY,
  client_id TEXT,
  deck_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  front TEXT NOT NULL,
  back TEXT NOT NULL,
  tags JSONB NOT NULL DEFAULT '[]'::jsonb,
  note TEXT NOT NULL,
  source TEXT NOT NULL,
  study_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  state INT NOT NULL,
  difficulty DOUBLE PRECISION NOT NULL,
  stability DOUBLE PRECISION NOT NULL,
  retrievability DOUBLE PRECISION NOT NULL,
  due_date TIMESTAMPTZ NOT NULL,
  last_review_at TIMESTAMPTZ,
  reps INT NOT NULL,
  lapses INT NOT NULL,
  elapsed_days DOUBLE PRECISION NOT NULL,
  scheduled_days DOUBLE PRECISION NOT NULL
);
CREATE TABLE IF NOT EXISTS review_logs (
  id TEXT PRIMARY KEY,
  card_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  rating INT NOT NULL,
  reviewed_at TIMESTAMPTZ NOT NULL,
  duration_ms INT NOT NULL,
  state_before INT NOT NULL,
  state_after INT NOT NULL
);`
	_, err := s.db.ExecContext(ctx, schema)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `ALTER TABLE cards ADD COLUMN IF NOT EXISTS client_id TEXT`)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `ALTER TABLE decks ADD COLUMN IF NOT EXISTS folder_id TEXT`)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `ALTER TABLE decks ADD COLUMN IF NOT EXISTS review_order TEXT NOT NULL DEFAULT 'sequential'`)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `ALTER TABLE cards ADD COLUMN IF NOT EXISTS title TEXT NOT NULL DEFAULT ''`)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `ALTER TABLE cards ADD COLUMN IF NOT EXISTS content TEXT NOT NULL DEFAULT ''`)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `ALTER TABLE cards ADD COLUMN IF NOT EXISTS study_enabled BOOLEAN NOT NULL DEFAULT FALSE`)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `UPDATE cards SET client_id = id WHERE COALESCE(TRIM(client_id), '') = ''`)
	if err != nil {
		return err
	}
	indexes := []string{
		`CREATE INDEX IF NOT EXISTS idx_folders_user_id ON folders(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_decks_user_id ON decks(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_decks_user_folder_id ON decks(user_id, folder_id)`,
		`CREATE INDEX IF NOT EXISTS idx_cards_user_deck_id ON cards(user_id, deck_id)`,
		`CREATE INDEX IF NOT EXISTS idx_cards_user_due_date ON cards(user_id, due_date)`,
		`CREATE INDEX IF NOT EXISTS idx_cards_user_client_id ON cards(user_id, client_id)`,
		`CREATE INDEX IF NOT EXISTS idx_review_logs_user_card_id ON review_logs(user_id, card_id)`,
	}
	for _, stmt := range indexes {
		if _, err := s.db.ExecContext(ctx, stmt); err != nil {
			return err
		}
	}
	return nil
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanCard(scanner rowScanner) (model.Card, error) {
	var card model.Card
	var tagsRaw []byte
	var lastReview sql.NullTime
	err := scanner.Scan(
		&card.ID, &card.ClientID, &card.DeckID, &card.UserID, &card.Title, &card.Content, &card.Front, &card.Back, &tagsRaw, &card.Note,
		&card.Source, &card.StudyEnabled, &card.CreatedAt, &card.UpdatedAt, &card.State.State, &card.State.Difficulty,
		&card.State.Stability, &card.State.Retrievability, &card.State.DueDate, &lastReview,
		&card.State.Reps, &card.State.Lapses, &card.State.ElapsedDays, &card.State.ScheduledDays,
	)
	if err != nil {
		return model.Card{}, err
	}
	if lastReview.Valid {
		card.State.LastReviewAt = lastReview.Time
	}
	if len(tagsRaw) > 0 {
		_ = json.Unmarshal(tagsRaw, &card.Tags)
	}
	return card, nil
}

func scanDeck(scanner rowScanner) (model.Deck, error) {
	var deck model.Deck
	err := scanner.Scan(
		&deck.ID, &deck.UserID, &deck.FolderID, &deck.Name, &deck.Description,
		&deck.Color, &deck.Icon, &deck.ReviewOrder, &deck.NewCardsPerDay,
		&deck.MaxReviewsPerDay, &deck.CreatedAt, &deck.UpdatedAt,
	)
	if err != nil {
		return model.Deck{}, err
	}
	return deck, nil
}

func mustJSON(value any) []byte {
	data, _ := json.Marshal(value)
	return data
}

func nullableTime(value time.Time) any {
	if value.IsZero() {
		return nil
	}
	return value
}

func nullableString(value string) any {
	if value == "" {
		return nil
	}
	return value
}
