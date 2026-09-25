-- AIDRA STEP 5 — Emergency Reporting Module
-- Migration 001: emergency_reports table
-- Run: psql $DATABASE_URL -f migrations/001_emergency_reports.sql

BEGIN;

-- Create custom enum types (idempotent via DO block)
DO $$ BEGIN
  CREATE TYPE report_input_type AS ENUM ('text', 'voice', 'image', 'video');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE urgency_level AS ENUM ('low', 'medium', 'high', 'critical');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE report_status AS ENUM (
    'queued', 'submitting', 'submitted', 'triaged',
    'verified', 'assigned', 'resolved', 'failed'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Main table
CREATE TABLE IF NOT EXISTS emergency_reports (
  -- Identity
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  report_code         VARCHAR(32)   NOT NULL UNIQUE,

  -- Reporter
  reporter_id         TEXT          NOT NULL,
  reporter_name       TEXT,

  -- Content
  input_type          report_input_type NOT NULL DEFAULT 'text',
  description         TEXT          NOT NULL CHECK (char_length(description) BETWEEN 1 AND 2000),
  description_lang    CHAR(5)       NOT NULL DEFAULT 'en',
  transcript          TEXT,

  -- Location (PostGIS-compatible; plain columns for broad compatibility)
  latitude            DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude           DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  location_accuracy_m REAL,
  address_text        TEXT,

  -- Hazard
  hazard_type         TEXT,
  people_at_risk      INTEGER       CHECK (people_at_risk >= 0),

  -- Severity
  urgency_user        urgency_level NOT NULL DEFAULT 'medium',
  urgency_ai          urgency_level,
  ai_severity_score   REAL          CHECK (ai_severity_score BETWEEN 0 AND 1),
  ai_confidence       REAL          CHECK (ai_confidence BETWEEN 0 AND 1),
  ai_model_version    TEXT,
  ai_entities         JSONB         NOT NULL DEFAULT '{}',
  ai_needs            JSONB         NOT NULL DEFAULT '{}',

  -- Lifecycle
  status              report_status NOT NULL DEFAULT 'submitted',
  incident_id         UUID,
  is_offline_created  BOOLEAN       NOT NULL DEFAULT FALSE,
  error_message       TEXT,

  -- Timestamps
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  synced_at           TIMESTAMPTZ,
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_emergency_reports_reporter
  ON emergency_reports (reporter_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_emergency_reports_status
  ON emergency_reports (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_emergency_reports_urgency
  ON emergency_reports (urgency_user, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_emergency_reports_location
  ON emergency_reports (latitude, longitude);

CREATE INDEX IF NOT EXISTS idx_emergency_reports_incident
  ON emergency_reports (incident_id)
  WHERE incident_id IS NOT NULL;

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_emergency_reports_updated_at ON emergency_reports;
CREATE TRIGGER trg_emergency_reports_updated_at
  BEFORE UPDATE ON emergency_reports
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMIT;
