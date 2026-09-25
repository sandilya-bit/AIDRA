# Local integration setup

The dashboard's local API URL is set in `admin-dashboard/.env.local` and the
backend allows the Vite development origin `http://localhost:5173` by default.
Local environment files and generated Firebase platform configuration are
ignored by Git.

## Credentials and external project access still required

Do not commit these values. Add them directly on the developer machine:

- `backend/.env`: `DATABASE_URL`, `FIREBASE_PROJECT_ID`,
  `FIREBASE_STORAGE_BUCKET`, `FIREBASE_SERVICE_ACCOUNT_PATH`, and
  `GEMINI_API_KEY`. Start with `backend/.env.example`; replace every example
  database/project value and set `ALLOW_DEMO_AUTH=false` before live use.
- Put the downloaded Firebase Admin service account at
  `backend/firebase-service-account.json` (already gitignored).
- After PostgreSQL and npm dependencies are available, run `npm run migrate`
  from `backend/`. This applies migrations 001–004, including the shared
  PostgreSQL rate-limit table.
- Install/configure Firebase CLI credentials, then deploy rules with
  `firebase deploy --only firestore:rules --project <firebase-project-id>`.
- Generate Flutter platform scaffolding and Firebase options with Flutter and
  FlutterFire CLI: `flutter create --org com.aidra --project-name aidra
  --platforms=android,ios,web .` followed by
  `flutterfire configure --project=<firebase-project-id>`. This project does
  not yet include a Google Maps Flutter plugin/provider; its current map is
  the built-in tactical demo map. Select a Maps SDK/provider and configure
  its restricted Android, iOS, and web keys before enabling live maps.
- Configure road/traffic/flood feed credentials only after choosing a provider
  and validating the feed's licensing and coverage for the deployment region.

The AIDRA workspace currently has none of the required database/Firebase/
Gemini credentials and does not have PostgreSQL, Firebase CLI, Flutter, or
FlutterFire CLI installed, so database migrations and Firebase deployment
cannot be run from this checkout yet.
