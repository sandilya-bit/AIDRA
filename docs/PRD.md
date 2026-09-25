# AIDRA — Product Requirements Document (PRD)

**Product:** AIDRA — AI-Powered Disaster Response Platform
**Tagline:** "Connecting Help Before It's Too Late."
**Version:** 1.0 · **Date:** September 25, 2026 · **Status:** Draft for review
**Companion doc:** [DESIGN-SYSTEM.md](./DESIGN-SYSTEM.md) (locked UI structure)

---

## 1. Executive Summary

### 1.1 Problem
During disasters, four critical information gaps cost lives:
1. **People don't know who needs help** — victims are unreachable, uncounted, and un-prioritized.
2. **Responders don't know where resources are** — volunteers, NGOs, hospitals, and supplies operate in silos.
3. **Nobody knows which roads are open** — blocked/flooded routes waste the golden hour.
4. **Coordination is manual** — phone trees and spreadsheets fail at scale.

### 1.2 Solution
AIDRA is an AI-coordinated disaster response platform connecting **victims, volunteers, NGOs, hospitals, and authorities** in real time. It turns fragmented crisis signals into a single operating picture: who needs help, who can help, where resources are, and the safest route to reach them — even with low connectivity and across language barriers.

### 1.3 Product Pillars
| Pillar | Feature set |
|---|---|
| See the crisis | Emergency reporting, live maps, real-time notifications |
| Understand the crisis | AI urgency detection, analytics |
| Act on the crisis | Volunteer matching, safe route navigation, resource management |
| Coordinate the response | NGO & hospital coordination, dashboards |
| Reach everyone | Multilingual support, offline mode |

### 1.4 Success Metrics (v1 targets)
- Median time from incident report → assignment to a responder: **< 5 minutes**
- % of reports triaged automatically by AI urgency detection: **≥ 80%**
- Duplicate/redundant dispatch rate: **< 10%**
- Volunteer response acceptance rate: **≥ 60%**
- Offline report sync success rate: **≥ 99%**

---

## 2. Scope

### 2.1 In Scope (v1)
Mobile app (victims + volunteers), web dashboard (NGOs, hospitals, authorities), landing page, AI triage service, live map, notifications, offline capture, multilingual UI (EN + 4 languages at launch).

### 2.2 Out of Scope (v1, roadmap candidates)
Drone/satellite imagery ingestion, payments/donations, insurance integration, native wearables, predictive disaster simulation, e-commerce supply marketplace.

---

## 3. User Roles

| # | Role | Description | Primary surfaces |
|---|---|---|---|
| R1 | **Victim / Citizen** | Person affected or reporting an emergency; may need rescue, aid, or info | Mobile app |
| R2 | **Volunteer** | Trained or spontaneous helper; medical, rescue, logistics skills | Mobile app |
| R3 | **NGO Coordinator** | Staff of relief organizations managing teams and supplies | Web dashboard |
| R4 | **Hospital / Medical Coordinator** | Manages bed capacity, casualties, medical dispatch | Web dashboard |
| R5 | **Authority / Admin** | Government/EOC command: full visibility, assignment, verification | Web dashboard (Command Center) |
| R6 | **Super Admin** | Platform operator: tenant/NGO onboarding, roles, system config | Web dashboard (Admin) |

**Role matrix (high level):** Victims: report, view own reports, receive alerts. Volunteers: accept assignments, update status, navigate. NGO/Hospital: manage resources & teams, respond to requests. Authority: everything + verification, assignment, broadcasts. Super Admin: everything + configuration.

---

## 4. User Stories

### 4.1 Victim / Citizen (R1)
- **US-101** — As a victim, I want to report an emergency via text, voice, image, or video so that I can ask for help even when typing is hard.
- **US-102** — As a victim, I want the app to auto-detect my location so that I don't have to describe where I am.
- **US-103** — As a victim, I want to set urgency (Low/Medium/High/Critical) — or have AI infer it — so that critical cases jump the queue.
- **US-104** — As a victim, I want to report offline so that my SOS sends when connectivity returns.
- **US-105** — As a victim, I want to use the app in my native language so that I can report accurately.
- **US-106** — As a victim, I want status updates ("volunteer assigned, ETA 8 min") so that I know help is coming.
- **US-107** — As a nearby citizen, I want to see incidents within 2 km so that I can stay clear or help.
- **US-108** — As a victim, I want safe route guidance to the nearest shelter/hospital so that I can evacuate safely.

### 4.2 Volunteer (R2)
- **US-201** — As a volunteer, I want to register my skills (medical, rescue, logistics) and availability so that I get matched to the right incidents.
- **US-202** — As a volunteer, I want to see nearby incidents ranked by match quality so that I can respond effectively.
- **US-203** — As a volunteer, I want one-tap Accept/Assign with route preview (distance + ETA) so that I can commit fast.
- **US-204** — As a volunteer, I want road-closure-aware navigation so that I don't get stuck.
- **US-205** — As a volunteer, I want to update status (en route → on scene → resolved) so the system stays current.

### 4.3 NGO Coordinator (R3)
- **US-301** — As an NGO coordinator, I want a live map of incidents and my teams so that I can deploy efficiently.
- **US-302** — As an NGO coordinator, I want to manage resource inventory (food, water, blankets, boats) and see stock at distribution points.
- **US-303** — As an NGO coordinator, I want to coordinate with other NGOs to avoid duplicated coverage.
- **US-304** — As an NGO coordinator, I want reports/analytics on what was deployed so that I can plan and report to donors.

### 4.4 Hospital Coordinator (R4)
- **US-401** — As a hospital coordinator, I want to publish real-time capacity (beds, ICU, blood, oxygen) so that casualties route correctly.
- **US-402** — As a hospital coordinator, I want incoming casualty pre-alerts (count, condition, ETA) so that trauma teams prepare.
- **US-403** — As a hospital coordinator, I want AI-suggested patient-to-hospital assignment so that load is balanced.

### 4.5 Authority / Admin (R5)
- **US-501** — As an authority, I want a Command Center dashboard (KPIs, live map, recent incidents) so that I keep one operational picture.
- **US-502** — As an authority, I want to verify/flag reports and merge duplicates so that responders aren't misled.
- **US-503** — As an authority, I want to assign/reassign incidents to volunteers, NGOs, and hospitals.
- **US-504** — As an authority, I want to broadcast area alerts (evacuation, shelter, hazard) with multilingual templates.
- **US-505** — As an authority, I want analytics (response times, hotspot maps) so that I can improve operations.

### 4.6 Super Admin (R6)
- **US-601** — As a super admin, I want to onboard NGOs/hospitals as organizations with role-based access.
- **US-602** — As a super admin, I want audit logs of every assignment and data change for accountability.
- **US-603** — As a super admin, I want to configure languages, regions, and notification channels.

---

## 5. Functional Requirements

**Priority key:** P0 = v1 must-have · P1 = v1 should · P2 = later.

### 5.1 Emergency Reporting (FR-1xx)
- **FR-101 (P0):** Users can create a report with type ∈ {Text, Voice, Image, Video} and description (≤ 500 chars, live counter).
- **FR-102 (P0):** Auto-capture GPS location; allow manual pin adjustment on mini-map.
- **FR-103 (P0):** Urgency selection: Low / Medium / High / Critical (Critical styled filled-red).
- **FR-104 (P0):** AI urgency detection classifies each report and can override/confirm user's level with confidence score.
- **FR-105 (P0):** Reports submitted offline are queued and synced automatically with original timestamps.
- **FR-106 (P1):** Media compression + resumable upload on weak networks.
- **FR-107 (P1):** Duplicate detection merges similar reports within geo-temporal window (AI similarity).

### 5.2 AI Triage & Urgency (FR-2xx)
- **FR-201 (P0):** Triage pipeline scores every report (severity, people-at-risk, hazard type) within 10s of receipt.
- **FR-202 (P1):** Multilingual NLP extracts entities: location mentions, victim count, injury type, hazard.
- **FR-203 (P1):** Anomaly/cluster detection raises "escalation events" when multiple reports converge.
- **FR-204 (P2):** Model feedback loop: authority confirmations retrain triage.

### 5.3 Volunteer Matching (FR-3xx)
- **FR-301 (P0):** Match engine ranks volunteers by distance, skills, availability, and load; target "Best Match" panel.
- **FR-302 (P0):** Assign flow shows recommended route (distance + ETA) and one-tap Assign/Accept.
- **FR-303 (P0):** Volunteer status lifecycle: Available → Assigned → En Route → On Scene → Resolved.
- **FR-304 (P1):** Auto-escalation if no acceptance within N minutes (re-match or notify authority).

### 5.4 NGO & Hospital Coordination (FR-4xx)
- **FR-401 (P0):** Hospital capacity registry: beds, ICU, blood units, oxygen; updateable by R4, visible on dashboard.
- **FR-402 (P0):** Casualty pre-alerts to hospitals with patient count, triage tags, ETA.
- **FR-403 (P1):** Resource request/offer workflow between NGOs and authorities (request → approve → dispatch → confirm).
- **FR-404 (P1):** Coverage map showing which NGO owns which area to prevent duplication.

### 5.5 Resource Management (FR-5xx)
- **FR-501 (P0):** Resource catalog (type, quantity, location, owner) with add/edit/consume flows.
- **FR-502 (P1):** Low-stock alerts and burn-rate projections per distribution point.
- **FR-503 (P2):** Demand forecasting from incident trends.

### 5.6 Safe Route Navigation (FR-6xx)
- **FR-601 (P0):** Routing engine with hazard/closure overlays: computes safe route with distance + ETA ("2.8 km · 8 min").
- **FR-602 (P0):** Road-closure reports (e.g., "Road Blocked – Medium") instantly affect routing graph.
- **FR-603 (P1):** Reroute on new hazard along active route + push notification.

### 5.7 Live Maps (FR-7xx)
- **FR-701 (P0):** Real-time map with pin classes: Incidents (red), Volunteers (blue), Hospitals (green H), Resources (orange); legend chips.
- **FR-702 (P0):** Critical clusters highlighted with radar pulse + summary card ("5 people trapped — High Priority").
- **FR-703 (P1):** Heatmap layer of incident density; filters by type, urgency, time.

### 5.8 Notifications (FR-8xx)
- **FR-801 (P0):** Push (mobile), email, and in-app notifications for: assignment, status change, area alerts, escalations.
- **FR-802 (P0):** Authority broadcast: area polygon + severity + multilingual template.
- **FR-803 (P1):** Quiet-hours exceptions for Critical only.

### 5.9 Multilingual (FR-9xx)
- **FR-901 (P0):** Full UI localization framework; launch languages: English + Hindi, Telugu, Tamil, Spanish (configurable).
- **FR-902 (P0):** Language selection at onboarding and in settings; RTL-ready structure.
- **FR-903 (P1):** Real-time translation of user-generated descriptions for responders.

### 5.10 Offline Mode (FR-10xx)
- **FR-1001 (P0):** Offline cache of last-known map tiles, own reports, assigned tasks.
- **FR-1002 (P0):** Outbox queue for reports/status updates with conflict-safe sync.
- **FR-1003 (P1):** Mesh/SMS fallback channel for SOS (platform-dependent, P2 possible).

### 5.11 Auth & Accounts (FR-11xx)
- **FR-1101 (P0):** Sign-in via Email, Phone (OTP), Google; password reset ("Forgot Password").
- **FR-1102 (P0):** RBAC per Section 3; volunteer verification workflow (docs → approved badge).
- **FR-1103 (P0):** Organization onboarding for NGOs/Hospitals (Super Admin approves).

---

## 6. Non-Functional Requirements

| Category | Requirement |
|---|---|
| **Performance** | Map/refresh latency < 2s; triage score < 10s; dashboard KPI refresh ≤ 30s; support 100k concurrent mobile sessions during a major event. |
| **Availability** | ≥ 99.9% core API; graceful degradation to read-only/offline modes during outages. |
| **Scalability** | Horizontal scaling; burst 10× baseline traffic within 10 minutes (auto-scaling). |
| **Reliability** | Offline sync ≥ 99% success; no data loss on crash — local persistence before any network call. |
| **Security** | Per Section 9 (TLS 1.3, encryption at rest, RBAC, audit logs). |
| **Privacy** | Location data collected only during active crisis use; victim identity visible only to authorized responders; DSR (export/delete) support. |
| **Accessibility** | WCAG 2.1 AA; voice reporting as first-class input; large-touch targets (≥ 44px). |
| **i18n** | All strings externalized; UTC storage with local-timezone display. |
| **Compatibility** | Mobile: iOS 15+, Android 9+; Web: last 2 versions of major browsers; low-bandwidth mode. |
| **Maintainability** | ≥ 80% test coverage on core services; CI/CD with blue-green deploys. |
| **Observability** | Structured logs, distributed tracing, alerting on error budgets and triage-queue depth. |

---

## 7. Database Requirements

### 7.1 Core Entities
- **users** (id, role, name, phone, email, language, password_hash/otp refs, avatar, org_id?, verification_status)
- **volunteer_profiles** (user_id, skills[], availability, current_location, load, rating)
- **organizations** (id, type ∈ {ngo, hospital, authority}, name, contact, verified)
- **reports/incidents** (id, reporter_id, type, description, media_ids[], lat/lng, accuracy, urgency ∈ {low,medium,high,critical}, ai_urgency, ai_confidence, status ∈ {new,verified,assigned,in_progress,resolved,false_alarm,duplicate}, parent_incident_id, timestamps)
- **assignments** (id, incident_id, assignee_id, org_id?, route_snapshot, eta, status, assigned_by, timestamps)
- **resources** (id, type, quantity, unit, location, owner_org_id, status)
- **resource_transactions** (id, resource_id, delta, reason, actor, timestamp)
- **hospitals** (org_id, lat/lng, beds_total, beds_available, icu, blood{}, oxygen, updated_at)
- **routes/road_status** (id, geometry, status ∈ {open,blocked,damaged}, source, updated_at)
- **notifications** (id, user_id?, audience, channel, payload, read_at)
- **broadcasts** (id, area_polygon, severity, message{}, languages[], created_by)
- **audit_logs** (id, actor, action, entity, before/after, ip, timestamp)
- **sync_outbox** (client-side: queued mutations with monotonic sequence + idempotency keys)

### 7.2 Non-Functional Data Requirements
- PostGIS / geo-indexing (R-tree / geohash) for radius + polygon queries (< 100ms at city scale).
- Time-series store for analytics metrics (response times, KPIs).
- Object storage (S3-compatible) for media with signed URLs.
- Redis (or similar) for live location/presence + pub-sub fan-out.
- Soft deletes + retention policy: PII purged 90 days post-incident by default.
- Full audit trail, append-only.

---

## 8. API Requirements

### 8.1 Principles
REST (JSON) over HTTPS for CRUD; WebSocket for live map/assignments; versioned (`/v1`); idempotency keys on all mutating mobile-cached calls; cursor pagination; standard error envelope `{code, message, details, traceId}`.

### 8.2 Key Endpoints (representative)

**Auth**
- `POST /v1/auth/register` · `POST /v1/auth/login` (email/password) · `POST /v1/auth/otp/request` · `POST /v1/auth/otp/verify` · `POST /v1/auth/refresh` · `POST /v1/auth/password/reset`

**Reports / Incidents**
- `POST /v1/reports` (type, description, media[], location, urgency?) → returns id + ai_urgency
- `GET /v1/reports?bbox=&urgency=&status=&radius=` · `GET /v1/reports/:id` · `PATCH /v1/reports/:id` (status/verification)
- `POST /v1/reports/:id/media` (resumable upload) · `POST /v1/reports/:id/merge`

**Matching & Assignments**
- `GET /v1/incidents/:id/matches` → ranked volunteers w/ distance, ETA, skills
- `POST /v1/assignments` · `PATCH /v1/assignments/:id` (accept/en_route/on_scene/resolve)
- `POST /v1/assignments/:id/route` → safe route (distance, duration, geometry)

**Volunteers**
- `GET /v1/volunteers/nearby?lat=&lng=&km=&skill=` · `PATCH /v1/volunteers/me` (skills, availability, location)

**Resources / Hospitals / NGOs**
- `CRUD /v1/resources` + `POST /v1/resources/:id/transactions`
- `GET/PATCH /v1/hospitals/:id/capacity` · `POST /v1/hospitals/:id/prealerts`

**Map & Notifications**
- `GET /v1/map/pins?bbox=&layers=` · `WS /v1/stream` (events: report.created, incident.updated, assignment.changed, broadcast.new)
- `POST /v1/broadcasts` · `GET /v1/notifications` · `PATCH /v1/notifications/:id/read`

**Offline Sync**
- `POST /v1/sync/push` (batch of queued mutations, idempotent) · `GET /v1/sync/pull?since=cursor`

**Analytics / Admin**
- `GET /v1/analytics/kpis` · `GET /v1/analytics/response-times` · `GET /v1/admin/audit-logs`

### 8.3 SLAs
p95 latency: reads < 300ms, writes < 500ms, triage < 10s, WS event fan-out < 2s. Rate limits: per-user token buckets; stricter on auth/OTP. Webhooks for NGO/hospital systems (HMAC-signed).

---

## 9. Security Requirements

1. **Authentication:** Phone OTP + email/password + OAuth (Google/Apple); short-lived JWT access (≤ 15 min) + rotating refresh tokens; device binding for volunteer accounts.
2. **Authorization:** RBAC per Section 3; row-level checks (a volunteer sees only assigned + nearby incidents; victim sees own report status only).
3. **Encryption:** TLS 1.3 in transit; AES-256 at rest; field-level encryption for PII (phone, precise location, medical notes).
4. **Privacy by design:** Precise victim location blurred (±500m) to non-assigned roles; only assigned responder gets exact coordinates; identity revealed only on assignment acceptance.
5. **Abuse prevention:** OTP throttling, captcha on signup, report-rate limits, trusted-device flags for verified volunteers, fraud heuristics on fake reports.
6. **Auditability:** Append-only audit log for every assignment, status change, data edit, and admin action; tamper-evident (hash-chained).
7. **Data governance:** Configurable retention (default 90d PII purge), regional data residency option, DPDP/GDPR-aligned consent flows, DSR endpoints.
8. **Infrastructure:** WAF + DDoS protection, secrets in a vault, least-privilege service accounts, dependency scanning, annual pen-test, incident response runbook with EOC escalation.
9. **Availability hardening:** Offline-first clients, multi-AZ deployment, backup (RPO ≤ 5 min) and DR (RTO ≤ 30 min).

---

## 10. Mobile Screens (v1)

Locked layout/visual spec: see [DESIGN-SYSTEM.md](./DESIGN-SYSTEM.md) §4.

1. **Splash** — logo, tagline, Get Started, Login link.
2. **Login/Signup** — Email/Phone/Google tabs, password, Forgot Password, social buttons, Sign Up.
3. **Onboarding** — language selection, role selection (Victim/Volunteer), permissions (location, notifications, mic/camera).
4. **Home Dashboard** — greeting header, 2×2 quick actions (Report Emergency / Nearby Incidents / Resources / Chat Support), Active Emergency card, bottom tabs (Home · Map · Reports · More).
5. **Report Emergency** — type tiles (Text/Voice/Image/Video), description + counter, location mini-map card, urgency chips (Low/Medium/High/Critical), Submit.
6. **My Reports** — list with status badges + detail view (status timeline, assigned responder card).
7. **Live Map** — full map, pin classes, legend chips, incident summary card, radar pulse on critical.
8. **Volunteer: Task Feed** — nearby incidents ranked, match quality, Accept flow.
9. **Volunteer: Assignment Detail** — incident summary, recommended route card (2.8 km · 8 min, View Route), status updater.
10. **Navigation** — hazard-aware turn-by-turn with closures overlay.
11. **Resources** — nearby shelters/supplies list + map.
12. **Notifications** — grouped feed (assignments, alerts, broadcasts).
13. **Profile & Settings** — language, skills (volunteers), verification status, offline sync status.
14. **Chat Support** — AI assistant + escalate-to-coordinator (P1).

## 11. Dashboard Screens (v1)

Locked layout/visual spec: see [DESIGN-SYSTEM.md](./DESIGN-SYSTEM.md) §5–6.

1. **Landing Page** — navy hero, headline, feature strip, Get Started / Watch Video.
2. **Command Center (Dashboard home)** — sidebar nav; KPI cards (Active Incidents, People in Need, Volunteers Active, Resources Available); live map + Recent Incidents panel.
3. **Live Map (full)** — layers, heatmap, filters, cluster inspector.
4. **Incidents** — queue with filters + detail drawer (verify/merge/assign/escalate; media viewer; timeline).
5. **Volunteers** — roster, skills/availability, verification queue, assignments map.
6. **Hospitals** — capacity grid (beds/ICU/blood/oxygen), pre-alerts inbox, patient routing board.
7. **Resources** — inventory table + transactions, low-stock alerts, distribution points map.
8. **NGOs** — coverage map, request/offer board, contact directory.
9. **Broadcasts** — compose area alert (polygon draw, severity, languages), history.
10. **Reports & Analytics** — response-time trends, hotspot maps, exportable reports (CSV/PDF).
11. **Settings & Admin** — user/org management, RBAC, languages, audit logs, integrations/webhooks.

---

## 12. Complete Development Roadmap

### Phase 0 — Discovery & Foundations (Weeks 1–3)
- Stakeholder interviews (EOC, 2 NGOs, 1 hospital group); finalize this PRD.
- System architecture, data model, design system (already locked in DESIGN-SYSTEM.md).
- Infra bootstrap: repo, CI/CD, IaC, environments, auth provider, map provider selection.

### Phase 1 — Core MVP "Report → See → Assign" (Weeks 4–10)
- Auth + RBAC (email/phone/Google), organizations onboarding.
- Report creation (text/image), GPS location, urgency chips; basic AI triage v0 (rules + classifier).
- Live map (pins, legend, cluster card), incident queue, verify/merge.
- Volunteer profiles + matching v1 (distance+skills), assignment flow with accept/status.
- Basic notifications (push + in-app); Command Center dashboard shell with KPI cards.
- **Exit criteria:** a victim report in < 5 min reaches an assigned volunteer with ETA on map.

### Phase 2 — AI Triage & Coordination (Weeks 11–16)
- AI urgency detection v1 (multilingual NLP: EN/HI/TE/TA), duplicate detection, escalation clustering.
- Hospital capacity registry + casualty pre-alerts; resource catalog + transactions.
- NGO coverage map + request/offer workflow.
- Command Center completion (Recent Incidents panel, filters, detail drawer).

### Phase 3 — Navigation, Offline & Scale (Weeks 17–22)
- Safe route navigation with road closures + rerouting.
- Offline mode: outbox, sync engine, cached tiles/tasks; conflict resolution.
- Broadcasts (polygon + multilingual templates); analytics/reports module.
- Load testing to 100k sessions; chaos drills; security pen-test #1.

### Phase 4 — Hardening & Pilots (Weeks 23–26)
- Closed beta with one district EOC + partner NGOs; feedback loops.
- Accessibility audit (WCAG AA), i18n QA, performance tuning.
- Privacy/compliance review, audit-log verification, DR drill.

### Phase 5 — Public Launch (Week 27)
- App store + web launch in pilot region; onboarding runbooks for NGOs/hospitals/authorities.
- 24×7 launch war-room for 2 weeks; SLO dashboards.

### Phase 6 — Post-Launch (Weeks 28+)
- Voice/video reporting polish, SMS/mesh SOS fallback, demand forecasting.
- Additional languages; hospital PMS/HIS integrations; predictive simulation (P2).
- Quarterly model retraining + public trust report.

### Team Shape (indicative)
2 mobile · 2 web · 2 backend · 1 AI/ML · 1 DevOps/SRE · 1 designer · 1 PM · QA shared. Map/routing via Google Maps or Mapbox; AI on cloud GPU inference; notifications via FCM/APNs.

### Top Risks
1. **Connectivity assumptions** → offline-first from Phase 1 data model.
2. **AI false triage** → human-in-loop verification; Critical always confirmable.
3. **Adoption by authorities** → pilot with one district, show response-time wins.
4. **Fake reports** → verification workflows + rate limits + fraud heuristics.
5. **Privacy backlash** → blurring rules, retention policy, transparent consent.
