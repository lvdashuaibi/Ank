CREATE TABLE folders (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE decks
    ADD COLUMN folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
    ADD COLUMN review_order TEXT NOT NULL DEFAULT 'sequential';

ALTER TABLE cards
    ADD COLUMN study_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX idx_folders_user_id ON folders(user_id);
CREATE INDEX idx_decks_user_folder_id ON decks(user_id, folder_id);
