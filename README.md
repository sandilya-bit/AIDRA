# AIDRA — Flutter Application

> **Connecting Help Before It's Too Late.**
> AI-powered disaster response platform connecting victims, volunteers, NGOs, hospitals and authorities.

This repository contains the AIDRA **Flutter client** (mobile + responsive web) plus the product and
data documentation it was built from:

| Document | Contents |
|---|---|
| [`docs/PRD.md`](docs/PRD.md) | Core product requirements (roles, stories, FR/NFR, API, security, roadmap) |
| [`docs/PRD-VOLUME-II.md`](docs/PRD-VOLUME-II.md) | Vision, KPIs, severity framework, AI specs, playbooks, analytics, compliance |
| [`docs/DATABASE-DESIGN.md`](docs/DATABASE-DESIGN.md) | Production PostgreSQL + PostGIS schema, RLS policies, partitioning |
| [`docs/DESIGN-SYSTEM.md`](docs/DESIGN-SYSTEM.md) | **Locked UI structure** — every screen in this app follows it |

---

## 1. Quick start

Flutter is not vendored in this repo, so generate the platform folders once, then run:

```bash
# 1. Platform scaffolding (android/ios/web/macos/…). Existing lib/ and pubspec.yaml are preserved.
flutter create --org com.aidra --project-name aidra --platforms=android,ios,web .

# 2. Dependencies
flutter pub get

# 3. Run (demo mode — bundled dataset, no backend needed)
flutter run

# 4. Run against a real backend
flutter run \
  --dart-define=AIDRA_USE_REMOTE=true \
  --dart-define=AIDRA_API_BASE_URL=https://api.aidra.app/v1
```

Quality gates:

```bash
flutter analyze     # zero warnings expected (see analysis_options.yaml)
flutter test        # unit tests for geo maths, severity framework, offline sync
```

> If `flutter create` overwrites `lib/main.dart`, restore it with `git checkout -- lib pubspec.yaml`
> and re-run `flutter pub get`. Platform folders are the only thing being generated.

---

## 2. Roles

Five roles, one app — the home dashboard adapts to the signed-in role
(mirrors the role matrix in `docs/PRD.md` §3):

| Role | Sees |
|---|---|
| **Victim / Citizen** | Active emergency card, own reports with AI triage results, nearby incidents, chat support |
| **Volunteer** | Availability toggle, ranked matches, task lifecycle (accept → en route → on scene → resolved), safe route |
| **NGO Coordinator** | Coverage map, field teams, inter-org request board, resource burn rate |
| **Hospital Coordinator** | Live capacity grid, casualty pre-alerts with the 5-minute ack SLA, AI receiving suggestions |
| **Authority / Admin** | Command-Center KPIs, incident queue, escalations, broadcasts, analytics |

Demo mode lets you switch roles from the login screen or **More → Profile → Switch role**, which
rebuilds the session as that persona so every dashboard is reviewable in one build.

---

## 3. Architecture

Clean architecture with a strict dependency direction
(`presentation → domain ← data`), Riverpod for state, GoRouter for navigation.

```
lib/
├── main.dart                     # bootstrap: LocalStore → ProviderScope override
├── app/
│   ├── app.dart                  # MaterialApp.router, theme, locale, a11y wrappers
│   ├── router/app_router.dart    # GoRouter + auth redirect + 4-tab stateful shell
│   ├── shell/app_shell.dart      # bottom nav + More tab
│   ├── theme/                    # brand tokens, palette, type ramp, Material 3 themes
│   └── l10n/                     # 5-language catalogue (en/hi/te/ta/es) + delegate
├── core/
│   ├── config/                   # build-time config (API URL, flags, locales)
│   ├── constants/                # domain enums mirroring the PostgreSQL enum types
│   ├── data/demo_data.dart       # bundled dataset so the app runs with no backend
│   ├── di/providers.dart         # infrastructure providers (api, store, sync, connectivity)
│   ├── error/failure.dart        # sealed Failure hierarchy
│   ├── models/                   # entities + defensive JSON parsing
│   ├── network/                  # ApiClient (Dio), ConnectivityService
│   ├── settings/                 # persisted theme/language/role/a11y preferences
│   ├── storage/                  # LocalStore (SharedPreferences), OutboxStore (offline queue)
│   ├── sync/sync_service.dart    # FIFO outbox drain + SyncState
│   ├── utils/                    # formatters, validators
│   └── widgets/                  # design-system component library + vector logo + tactical map
└── features/<feature>/
    ├── domain/                   # abstract repository + entities (no Flutter/Dio imports)
    ├── data/                     # repository implementation (remote-first, cache fallback)
    └── presentation/             # providers (Riverpod), screens, widgets
```

Features: `auth`, `dashboard`, `incidents` (shared operational feed), `reports`, `map`,
`volunteer`, `hospital`, `resources`, `ngo`, `notifications`, `chat`, `profile`.

### Patterns used consistently

- **Repository pattern** — presentation never touches `Dio` or `SharedPreferences`; it
  depends on `domain` interfaces resolved through Riverpod providers.
- **AsyncNotifier controllers** own loading/error/data state per feature, with optimistic
  local updates and silent background refresh.
- **Sealed `Failure`** — transport exceptions are translated once, in `ApiClient`, so the UI
  branches on `NetworkFailure` / `AuthFailure` / `ServerFailure` / `ValidationFailure`.
- **Version-tolerant integrations** — `ConnectivityService` parses both the single-result and
  list-result shapes of `connectivity_plus`; theme usage avoids renames like
  `CardTheme` → `CardThemeData` by styling components explicitly.

---

## 4. Offline support

AIDRA's write path is offline-first by design (FR-105, FR-1002):

1. **Persist locally first** — a report exists on the device before any network call.
2. **Try the network** when connectivity allows.
3. **Queue an idempotent mutation** in the outbox on failure; the sync service replays FIFO,
   stops on a retryable failure to preserve ordering, and records attempts for backoff.
4. **Surface the truth** — the UI shows *queued offline*, never a fake success, and the
   `OfflineBanner` appears app-wide with the live queue depth.

Reads fall back through: remote → local cache → bundled demo dataset. That is why the app is
fully usable in a field camp with no signal.

Toggle **More → Profile → Force offline mode** to exercise the whole queue-and-sync path.

---

## 5. Testing

```bash
flutter test
```

- `test/core/units_test.dart` — haversine distance, formatters, validators.
- `test/core/severity_test.dart` — L1–L4 response targets, AI-vs-human triage authority, the
  Golden-Hour Rescue Rate calculation, SLA breach detection.
- `test/features/offline_reports_test.dart` — offline queueing, FIFO replay, retryable-failure
  head-of-line blocking, attempt ceiling, cache trimming, corrupt-JSON resilience.
- `test/core/auth_test.dart` — JWT decoding and fail-closed lifetime rules, the role/permission
  matrix, token-vs-requested role precedence, session expiry, idle auto-logout and warning events.

---

## 6. Authentication (Firebase)

Identity and authorization are deliberately separate:

- **Firebase Authentication** proves *who* someone is — email + password, phone OTP, Google, Apple.
- **The AIDRA backend** decides *what they may do*: it verifies the Firebase ID token, resolves the
  account's role server-side, and signs an access JWT carrying a `role` claim.
- **The client never grants a role.** `RolePolicy.resolveRole` always prefers the token's claim, and
  a locally requested role is honoured only when no authoritative backend is configured
  (`AIDRA_USE_REMOTE=false`). That is the demo path, and it is unreachable in a real deployment.

### Enabling it

```bash
# 1. One-time: generate lib/firebase_options.dart (replaces the placeholder file).
dart pub global activate flutterfire_cli
flutterfire configure --project=<your-firebase-project>

# 2. In the Firebase console enable the providers: Email/Password, Phone, Google (Apple for iOS).
#    Add your Android SHA-1/SHA-256 fingerprints, then supply the OAuth *server* client ID,
#    which is what makes Google Sign-In return an idToken on Android:
flutter run --dart-define=AIDRA_USE_FIREBASE=true \
            --dart-define=AIDRA_GOOGLE_SERVER_CLIENT_ID=123.apps.googleusercontent.com
```

Without `AIDRA_USE_FIREBASE=true` (the default) the whole feature set still runs: email/password
accepts any 8+ character password, the SMS code is simulated (any 4+ digits), and the social
buttons mint a local identity. That is what keeps `flutter run` usable with no Firebase project,
and it is why a broken Firebase config degrades instead of refusing to start.

### Files

| File | Role |
|---|---|
| `core/auth/jwt.dart` | Dependency-free JWT reader: claims, `exp`/`nbf`/`iat`, and a `JwtCheck` verdict. Decodes; never verifies. |
| `core/auth/session_store.dart` | `SessionStore` plus Keychain/Keystore (`flutter_secure_storage`), SharedPreferences and in-memory implementations. |
| `core/auth/session_manager.dart` | Token lifetime, refresh window, idle auto-logout, `SessionEvent` stream. |
| `core/auth/permissions.dart` | `Permission` matrix per role, guarded route prefixes, token → role resolution. |
| `features/auth/data/firebase_auth_gateway.dart` | The only file that imports `firebase_auth` / `google_sign_in`. |
| `features/auth/data/auth_repository_impl.dart` | Joins provider identity with AIDRA authorization; offline-tolerant. |
| `features/auth/presentation/otp_screen.dart` | Phone code entry with resend cooldown. |
| `features/auth/presentation/forgot_password_screen.dart` | Account recovery. |

### Session policy

| Behaviour | Value | Where |
|---|---|---|
| Refresh window (renew *before* expiry) | 5 min | `AppConfig.refreshSkew` |
| Auto-logout on inactivity | 30 min without a pointer event | `AppConfig.idleTimeout` |
| Watchdog interval | 30 s | `AppConfig.sessionWatchInterval` |
| Local session fallback TTL | 12 h | `AppConfig.localSessionTtl` |
| Token storage | Keychain (iOS/macOS), Keystore + AES-GCM (Android) | `SecureSessionStore` |

Three independent things can end a session, and all three are enforced: the token's own `exp`
(authoritative — the server rejects the token regardless of what the client believes), the stored
deadline, and inactivity. A `warning` event fires two ticks before the idle timeout so the shell can
offer *Stay signed in*; an `ended` event drives the redirect back to login with an explanation.

### Security properties worth stating

- **Client-side decoding is not verification.** `Jwt` reads claims to drive UX only. Authorization
  belongs to the server, backed by the row-level security policies in `docs/DATABASE-DESIGN.md` §13.
- **No account enumeration.** `wrong-password`, `invalid-credential` and `user-not-found` collapse
  into one message, and password reset returns identical copy whether or not the address exists.
- **Tokens never touch SharedPreferences** when Firebase is enabled.
- **AIDRA never sees a password.** Reset emails are sent by Firebase, and changing a password
  requires re-authentication with the current one.

---

## 7. Wiring the real backend

Everything already speaks the API contract in `docs/PRD.md` §8 — set
`AIDRA_USE_REMOTE=true` and point `AIDRA_API_BASE_URL` at your service:

| Feature | Endpoints used |
|---|---|
| Auth | `POST /auth/login`, `/auth/otp/verify`, `/auth/provider`, `POST /auth/register`, `POST /auth/firebase/exchange` (Firebase ID token → AIDRA access JWT), `POST /auth/refresh` |
| Reports | `GET/POST /reports`, `GET /reports/:id` |
| Incidents | `GET /incidents`, `GET /incidents/:id`, `PATCH /incidents/:id`, `GET /events` |
| Matching | `GET /volunteers/nearby`, `POST /assignments`, `PATCH /assignments/:id`, `POST /route` |
| Hospitals | `GET /hospitals`, `PATCH /hospitals/:id/capacity`, `GET/PATCH /hospitals/prealerts` |
| Resources | `GET/POST /resources`, `POST /resources/:id/transactions`, `/resources/requests` |
| Notifications | `GET/PATCH /notifications`, `GET /broadcasts` |
| Analytics | `GET /analytics/kpis` |

Every mutating call sends an `Idempotency-Key`, matching the `idempotency_keys` registry in the
database design — so a replayed offline mutation can never create a duplicate incident.

---

## 8. Maps

`TacticalMap` renders the operational picture with a `CustomPainter` (streets, river, blocks,
grid, scale bar) plus real pin widgets for incidents, volunteers, hospitals and resources,
animated radar pulses for critical clusters, and layer toggles.

It needs no API key and works offline. Swapping in tiles is a drop-in change: keep the `pins`
input and replace the backdrop painter with a tile layer (`flutter_map` + OSM, Google Maps or
Mapbox) — the pins, radar, legend and selection logic above it stay identical.

---

## 9. Accessibility & i18n

- Minimum 48 px tap targets, semantic labels on every interactive element, `liveRegion` on the
  offline banner and error states.
- Larger-text mode scales the whole type ramp on top of the platform text scale; reduce-motion
  disables implicit animations and the map radar pulse.
- Five languages ship in `app/l10n/app_strings.dart` (English, Hindi, Telugu, Tamil, Spanish)
  with English fallback. Keys map 1:1 to a future `gen-l10n` or translation-vendor pipeline.

---

## 10. Design system compliance

Colours, spacing, radii and component shapes come from `docs/DESIGN-SYSTEM.md`:
navy `#0E2A47` surfaces, blue `#1B6FF1` primary, green `#1DB97A` success/health,
orange `#F5A623` warning, red `#F03D3D` danger, purple `#7C4DFF` chat/AI, 14–18 px cards,
pill buttons, and the L1–L4 priority badge scale.
