BEGIN;
CREATE TABLE IF NOT EXISTS api_rate_limit_buckets (
  bucket_key CHAR(64) PRIMARY KEY,
  request_count INTEGER NOT NULL CHECK (request_count > 0),
  reset_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS api_rate_limit_reset_at ON api_rate_limit_buckets(reset_at);
COMMIT;
