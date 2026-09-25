# AIDRA Steps 5–14 implementation map

## Available in this repository

- Flutter emergency report form supports text, voice transcription, image/video attachments, GPS, victim count, and urgency. Existing repository persists locally for offline sync and can submit to the API.
- Backend report API validates payloads, stores reports/attachments in PostgreSQL, mirrors the report to Firestore, and authenticates Firebase ID tokens.
- Gemini server integration returns structured triage fields; absent keys or provider failures use local rule-based triage.
- Volunteer UI and profile model already support local ranked matching. The new API ranks populated `volunteer_profiles` rows by Haversine distance and skill fit.
- Existing map screen shows incidents/responders/hospitals/resources using the app's tactical map. Safe-route API provides a simulated estimate from submitted blocked-road areas.
- Existing chat screen is an offline support-chat experience. PostgreSQL chat tables and Firebase security baseline are supplied for the realtime incident-chat implementation.
- FCM multicast delivery endpoint and responsive React operations dashboard are provided.
- Backend has request validation, Firebase-token auth, role checks, Helmet, constrained CORS, rate limiting, and deny-by-default Firestore rules.

## Setup still required for a live deployment

Configure PostgreSQL, Firebase Admin credentials and Gemini key in `backend/.env`; apply migrations 001–003; populate volunteer profiles and device tokens from authenticated profile registration; deploy Firestore rules; configure the Flutter Firebase platform files, Google Maps key/provider, and dashboard API URL. Use a shared rate-limit store and real road/traffic hazard feeds before production dispatch. The demo map and route estimate are not live Google Maps or navigation.

## Continuation prompt

> Continue the AIDRA implementation in `C:\Users\SANDILYA\Desktop\AIDRA` from `docs/IMPLEMENTATION-STEPS-5-14.md`. Finish the live integrations that remain: implement Firestore realtime incident chat with receipts and image uploads, device-token registration and event-triggered push notifications, Google Maps Flutter integration with live location/markers/clustering/routes, dashboard analytics and live refresh, and production API/storage hardening. Preserve the existing Flutter architecture and backend contracts. Add and run the requested unit, widget, API, security, and load checks where the required toolchains and credentials are available. Configure no real secrets; document exact setup needed. First inspect the current working tree and continue without repeating completed work.
