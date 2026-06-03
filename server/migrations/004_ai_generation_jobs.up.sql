CREATE TABLE ai_generation_jobs (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_name TEXT NOT NULL DEFAULT '',
    source_type TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL,
    progress DOUBLE PRECISION NOT NULL,
    error_message TEXT NOT NULL DEFAULT '',
    request_json JSONB NOT NULL,
    result_json JSONB,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_ai_generation_jobs_user_id ON ai_generation_jobs(user_id);
