DROP INDEX IF EXISTS idx_decks_user_folder_id;
DROP INDEX IF EXISTS idx_folders_user_id;

ALTER TABLE cards
    DROP COLUMN IF EXISTS study_enabled;

ALTER TABLE decks
    DROP COLUMN IF EXISTS review_order,
    DROP COLUMN IF EXISTS folder_id;

DROP TABLE IF EXISTS folders;
