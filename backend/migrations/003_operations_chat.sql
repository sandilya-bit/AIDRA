BEGIN;
CREATE TABLE IF NOT EXISTS volunteer_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL, skills TEXT[] NOT NULL DEFAULT '{}', availability TEXT NOT NULL DEFAULT 'unavailable'
    CHECK (availability IN ('available','busy','unavailable')),
  latitude DOUBLE PRECISION, longitude DOUBLE PRECISION, organization_name TEXT,
  rating REAL NOT NULL DEFAULT 0 CHECK (rating BETWEEN 0 AND 5), is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS volunteer_profiles_availability ON volunteer_profiles (availability);
CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), incident_id UUID REFERENCES emergency_reports(id) ON DELETE CASCADE,
  title TEXT NOT NULL, created_by TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS conversation_members (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE, user_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('victim','volunteer','ngo','authority')),
  PRIMARY KEY(conversation_id,user_id)
);
CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id TEXT NOT NULL, text TEXT, attachment_url TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (text IS NOT NULL OR attachment_url IS NOT NULL)
);
CREATE TABLE IF NOT EXISTS chat_receipts (
  message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE, user_id TEXT NOT NULL,
  read_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(message_id,user_id)
);
CREATE TABLE IF NOT EXISTS user_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id TEXT NOT NULL, fcm_token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL CHECK(platform IN ('android','ios','web')), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS user_devices_user_id ON user_devices(user_id);
COMMIT;
