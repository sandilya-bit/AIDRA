# AIDRA Backend — Emergency Reporting API

Node.js · Express · TypeScript · PostgreSQL · Firebase Admin

## Quick Start

### Prerequisites
- Node.js 20+
- PostgreSQL 14+
- Firebase project with service account key

### Setup

```bash
# 1. Install dependencies
npm install

# 2. Configure environment
cp .env.example .env
# Edit .env with your PostgreSQL connection and Firebase credentials

# 3. Run database migrations
npm run migrate

# 4. Start development server
npm run dev
```

### Environment Variables

See `.env.example` for all available variables.

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | Yes | Path to Firebase service account JSON |
| `FIREBASE_PROJECT_ID` | Yes | Firebase project ID |
| `GEMINI_API_KEY` | No | Server-only Gemini key; local explainable triage is used when omitted |
| `FIREBASE_STORAGE_BUCKET` | No | Firebase Storage bucket name |
| `PORT` | No | HTTP port (default: 3000) |

## API Reference

### Authentication
All routes require `Authorization: Bearer <firebase_id_token>`.

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check |
| `POST` | `/v1/reports` | Submit emergency report |
| `GET` | `/v1/reports` | List reports (own or all for admins) |
| `GET` | `/v1/reports/:id` | Get single report |
| `PATCH` | `/v1/reports/:id/status` | Update report status (authority/NGO/volunteer) |
| `POST` | `/v1/volunteers/match` | Return up to five available volunteers ranked by Haversine distance and requested skills |
| `POST` | `/v1/route/safe` | Simulated safe-route estimate around supplied blocked-road coordinates |
| `GET` | `/v1/admin/overview` | Authority/NGO dashboard counts and recent incidents |
| `POST` | `/v1/notifications/send` | Role-gated Firebase multicast push delivery |

### POST /v1/reports

Creates a report, runs AI triage, dual-writes to Firestore.

**Request body** (mirrors `EmergencyReport.toJson()`):
```json
{
  "id": "<uuid>",
  "reporter_id": "uid123",
  "input_type": "text",
  "description": "Five people trapped on first floor, water rising",
  "latitude": 17.3850,
  "longitude": 78.4867,
  "people_at_risk": 5,
  "urgency_user": "high",
  "attachments": []
}
```

**Response** `201`:
```json
{
  "report": {
    "id": "...",
    "report_code": "AID-2026-123456",
    "urgency_ai": "critical",
    "ai_severity_score": 0.83,
    "ai_confidence": 0.89,
    "status": "submitted",
    ...
  }
}
```

## Architecture

```
POST /v1/reports
  │
  ├─ Zod validation
  ├─ Auth middleware (Firebase ID token)
  ├─ Insert → PostgreSQL (source of truth)
  ├─ Gemini JSON triage (local rules fallback) → update severity fields
  └─ Firestore dual-write (real-time for dashboards)
```

## Database Schema

See `migrations/` directory.

- `emergency_reports` — core table
- `report_attachments` — media files per report
- `volunteer_profiles` — matching directory (profile sync must populate it)
- `conversations`, `chat_messages`, `chat_receipts` — chat persistence schema
- `user_devices` — push token registry schema

`/v1/notifications/send` is an authorized delivery primitive; callers must
resolve and authorize recipient tokens. Rate limiting uses PostgreSQL as a
shared store across API instances; apply every migration before production.
The route estimator is a hackathon simulation and is not turn-by-turn guidance.
```
