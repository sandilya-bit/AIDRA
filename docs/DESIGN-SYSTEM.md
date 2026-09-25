# AIDRA — Locked UI Structure & Design System

> **This file is the SINGLE SOURCE OF TRUTH for all AIDRA screens.**
> Every screen built in this project must follow this spec exactly.
> Brand: **AIDRA — "Connecting Help Before It's Too Late."**
> App type: **AI-powered disaster response platform** (mobile app + web dashboard + landing page).

---

## 1. Brand & Logo

- **Logo:** Shield shape containing a medical cross, cradled by two cupped hands; a stylized "A" (peak/mountain shape) inside the cross. Rounded modern shield, gradient from blue → teal.
- **Tagline:** "Connecting Help Before It's Too Late."
- **Logo symbolism:**
  - Shield = Protection & Safety
  - Cross = Health & Life
  - Hands = Support & Community
  - A = Action & Hope
- **App icon:** Same shield mark on white rounded-square background.

## 2. Color Psychology & Palette (LOCKED)

| Token | Hex (approx) | Meaning |
|---|---|---|
| `--primary` (Blue) | `#1B6FF1` | Trust, Safety, Stability — primary actions, buttons, links |
| `--success` (Green) | `#1DB97A` | Hope, Health, Growth — success states, "Available", volunteers |
| `--warning` (Orange) | `#F5A623` | Action, Urgency, Energy — Medium priority, warnings |
| `--navy` (Navy) | `#0E2A47` / deep navy `#0B2239` | Professionalism, Authority — dark surfaces, sidebar, splash bg |
| `--white` (White) | `#FFFFFF` | Clarity, Simplicity, Cleanliness — light surfaces |
| Critical (Red) | `#F03D3D` | Emergency/Critical priority, incidents |
| Purple (accent) | `#7C4DFF` | Chat Support tile accent |

- Gradients: blue → teal on logo/mark; dark navy gradient on splash & landing hero.
- Priority scale: **Low (grey/green) → Medium (orange) → High (red) → Critical (deep red)**.

## 3. Typography & Shape

- Font: Modern geometric sans (Inter / Poppins family). Bold headers, regular body.
- Cards: 14–16px corner radius, soft shadow, white on light-grey page bg (`#F4F6FA`).
- Buttons: fully rounded (pill) on mobile, 8–10px radius on dashboard; primary = blue filled, secondary = white with border.
- Iconography: filled rounded icons; colored rounded-square tiles for quick actions.

---

## 4. Mobile App Screens (structure locked)

### 4.1 Splash Screen
- Dark navy gradient background with disaster-rescue hero imagery (low opacity).
- Centered logo mark + "AIDRA" + tagline.
- White pill **"Get Started"** button near bottom.
- Footer link: "Already have an account? **Login**".

### 4.2 Login Screen
- White background, centered logo + "AIDRA" + tagline.
- Heading "Welcome Back", subtext "Sign in to continue".
- Segmented tabs: **Email | Phone | Google**.
- Inputs: Email or Phone Number; Password (with eye toggle).
- Link: "Forgot Password?" (blue).
- Blue full-width pill **Login** button.
- "Or continue with" → Google / Apple / social round icon buttons.
- Footer: "Don't have an account? **Sign Up**".

### 4.3 Home Dashboard (mobile)
- Header: "Good Morning, **Riya Sharma**" + avatar; subtext "Stay safe. Help when needed."
- 2×2 quick-action tile grid (rounded, colored):
  - **Report Emergency** (red) · **Nearby Incidents** (blue)
  - **Resources** (green) · **Chat Support** (purple)
- **Active Emergency card:** "Flooded area – 2.4 km", "5 people trapped", badge **High Priority** (red), green "View Details" link.
- Bottom tab bar: **Home · Map · Reports · More**.

### 4.4 Report Emergency
- Header with back arrow + title "Report Emergency".
- 4 report-type tiles: **Text · Voice · Image · Video**.
- Description box with typed example: "5 people trapped in building near the river." + char counter.
- **Location** card: "Current Location", coordinates, mini-map with red pin, expand icon.
- **Urgency Level** chips: **Low · Medium · High · Critical** (Critical = filled red when selected).
- Blue pill **Submit Report** button.

### 4.5 Live Map
- Header: back arrow, "Live Map", search icon.
- Full-screen map with colored pins (red incidents, blue volunteers, green hospitals/resources).
- Floating incident card: "5 people trapped — **High Priority**" with red alert icon.
- Radar pulse highlight on critical cluster.
- Bottom legend chips: **Incidents · Volunteers · Hospitals · Resources**.
- Bottom tab bar (Map tab active).

### 4.6 Volunteer Matching
- Header: "Nearby Volunteers".
- Green success banner: "Best Match Found — 3 volunteers within 2 km".
- Volunteer list cards: avatar, name, skills (e.g., Volunteer · Medical), distance + "Available" (green), blue **Assign** button.
- **Recommended Route** card: "2.8 km · 8 min" + blue "View Route" button.
- Bottom tab bar.

## 5. Web Dashboard — Disaster Command Center (structure locked)

- **Left sidebar (navy):** logo "AIDRA" top; menu: Dashboard, Live Map, Incidents, Volunteers, Hospitals, Resources, NGOs, Reports, Analytics, Settings. Active item = blue pill highlight.
- **Top bar:** global search ("Search locations, incidents, or people...") + Admin/Authority profile chip.
- **Page title:** "Disaster Command Center".
- **KPI stat cards row:** Active Incidents (12, "+3 new" red), People in Need (248, "↑12%"), Volunteers Active (156, "↑8%"), Resources Available (8, "+2 new").
- **Main area split:**
  - Large **live map** with incident pins, heat/radar zone, "Flooded Area" label.
  - Right panel: **Recent Incidents** list — each item: colored alert icon, title (Building Collapse, Flood Rescue, Road Blocked, Medical Emergency), priority badge (High/Critical/Medium), people trapped, time + distance.

## 6. Landing Page (Web) (structure locked)

- Navy top nav: logo "AIDRA" left; links Home · Features · About · Contact; white pill "Get Started" button right.
- **Hero:** dark navy gradient over disaster-rescue imagery (rescuer + drone). Headline: "AI-Powered" (white) + "Disaster Response" (green) + "for a Safer Tomorrow" (white). Supporting paragraph. Green **Get Started** button + "Watch Video" outline button.
- **Feature strip (4 items):** Real-Time Alerts · AI-Powered Coordination · Safe Route Navigation · Resource Management.
- Footer note: "Together We Save Lives."

## 7. Component Inventory (shared)

- Stat/KPI card · Incident list item · Priority badge · Volunteer card · Quick-action tile
- Map pin set (incident/volunteer/hospital/resource) · Legend chip · Segmented tabs
- Pill button (primary/secondary/danger) · Input field · Urgency chip selector · Bottom tab bar · Sidebar nav item

**Rule for future screens:** reuse only these components, tokens, and layout patterns. New screens must visually match (navy + white + blue/green accents, rounded cards, pill buttons, colored priority badges).
