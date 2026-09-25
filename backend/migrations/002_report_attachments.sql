-- AIDRA STEP 5 — Emergency Reporting Module
-- Migration 002: report_attachments table

BEGIN;

CREATE TABLE IF NOT EXISTS report_attachments (
  id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id       UUID    NOT NULL REFERENCES emergency_reports (id) ON DELETE CASCADE,
  kind            report_input_type NOT NULL,
  mime_type       TEXT    NOT NULL DEFAULT 'application/octet-stream',
  storage_key     TEXT,           -- Firebase Storage download URL or gs:// path
  local_path      TEXT,           -- Original device path (debug / dev only)
  size_bytes      BIGINT  NOT NULL DEFAULT 0,
  duration_sec    INTEGER,        -- For audio/video attachments
  uploaded        BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_report_attachments_report
  ON report_attachments (report_id);

COMMIT;
