CREATE TABLE users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE decks (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    color TEXT NOT NULL,
    icon TEXT NOT NULL,
    new_cards_per_day INT NOT NULL,
    max_reviews_per_day INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE cards (
    id TEXT PRIMARY KEY,
    client_id TEXT,
    deck_id TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL DEFAULT '',
    content TEXT NOT NULL DEFAULT '',
    front TEXT NOT NULL,
    back TEXT NOT NULL,
    tags JSONB NOT NULL DEFAULT '[]'::jsonb,
    note TEXT NOT NULL,
    source TEXT NOT NULL,
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

CREATE TABLE review_logs (
    id TEXT PRIMARY KEY,
    card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating INT NOT NULL,
    reviewed_at TIMESTAMPTZ NOT NULL,
    duration_ms INT NOT NULL,
    state_before INT NOT NULL,
    state_after INT NOT NULL
);

CREATE UNIQUE INDEX uq_cards_user_client_id
    ON cards(user_id, client_id)
    WHERE client_id IS NOT NULL AND client_id <> '';

CREATE INDEX idx_decks_user_id ON decks(user_id);
CREATE INDEX idx_cards_user_deck_id ON cards(user_id, deck_id);
CREATE INDEX idx_cards_user_due_date ON cards(user_id, due_date);
CREATE INDEX idx_review_logs_user_card_id ON review_logs(user_id, card_id);
