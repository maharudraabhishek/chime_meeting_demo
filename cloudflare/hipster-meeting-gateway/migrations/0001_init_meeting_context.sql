CREATE TABLE IF NOT EXISTS meeting_context (
    meeting_id TEXT PRIMARY KEY NOT NULL,
    media_placement_json TEXT NOT NULL,
    media_region TEXT,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_meeting_context_expires_at
ON meeting_context(expires_at);
