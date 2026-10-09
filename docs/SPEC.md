# Seizure / Fall Alert App: Technical Specification & UI Guide

_For: Competition Development Team. Converted from [`seizure-fall-alert-app-spec.docx`](seizure-fall-alert-app-spec.docx)._

# 1. App overview

A mobile app that helps people with epilepsy, stroke, and similar conditions when they fall — whether bystanders are present or they are alone. The app combines a manual panic trigger with automatic fall detection to send emergency alerts and play loud multilingual first-aid instructions for bystanders.

**Target languages:** Amharic, English, Afaan Oromo (pre-recorded audio)

**Target platform:** Android first (primary market share in Ethiopia), iOS as stretch goal

**Offline-first:** Core trigger, audio playback, and SMS fallback must work with zero data connectivity

# 2. STARK Hackathon requirements — mandatory compliance

**TIMELINE (updated): Idea submission closes SEP 25 — no new ideas accepted after that date, so the concept we lock in today is the concept we ship. Building runs SEP 25 → OCT 10. Judging is CONTINUOUS throughout via STARK Changelogs and GitHub history, not just at the end. Roughly 15 days of build time. See section 9 for the sprint plan.**

**IDEA SUBMISSION — lock the scope today. Because no new ideas can be submitted after SEP 25, the submitted concept must already include the voice layer. Submit it as a voice-first emergency response app, not as a fall-detection app that happens to play audio. If the submitted idea does not mention voice interaction, we cannot add it later as a headline feature. Wording to use: “A voice-first emergency alert app for people with epilepsy and stroke risk. The user triggers help by speaking, by pressing a button, or automatically via fall detection. The phone then alerts emergency contacts with location and speaks first-aid instructions to bystanders in Amharic, Afaan Oromo and English — and bystanders can talk back to it to ask what to do.”**

These are the six rules every project must satisfy. Three of them materially change our architecture.

## 2.1 The six rules

| # | Rule | Platform | Applies to us? |
|---|---|---|---|
| 1 | Prove your ideation — document and prove the ideation process: the problem identified, routes considered, how you arrived at the solution. Building on Scholarxiv itself, or using its MCP server / Papers API, counts in your favour. | Scholarxiv | YES — mandatory. Also a scoring opportunity (see 2.3). |
| 2 | Voice interaction is required — every project must support voice interaction through Voxide, in Amharic, Oromiffa, English or any other language. Must show voice becoming a meaningful part of the product experience. | Voxide | YES — mandatory. Our pre-recorded audio does NOT satisfy this. See 2.2. |
| 3 | Host on EthioDeploy — for websites and web platforms, hosting is optional but a strong advantage in judging. | EthioDeploy | YES if we ship a web dashboard. Strongly recommended — see 2.4. |
| 4 | Build from scratch, on the clock — project must start after kickoff. Prove work via GitHub development history and STARK Changelogs. | GitHub + STARK | YES — mandatory. Nothing from before SEP 09 counts. |
| 5 | Local payments via Links.et — only if the project requires payment functionality. | Links.et | NO — our app has no payments. Skip. |
| 6 | ALX registration for the in-person announcement event — not mandatory, anyone can register on the day. | ALX | Optional — but at least one team member should attend to present. |

## 2.2 CRITICAL: the voice requirement changes our design

**Our original design only PLAYS audio at bystanders. That is voice output, not voice interaction. Judges are explicitly looking for voice to be “a meaningful part of the product experience.” We must add real voice input via Voxide.**

The good news: voice input is arguably the single best fit for this product, and we should lead the pitch with it. A person having a seizure aura, or one who has already fallen, may be physically unable to press a button but still able to speak. Voice is not a bolted-on requirement here — it is a genuine accessibility win.

**Voice features to build with Voxide (in priority order):**

- **1. Voice-activated alert trigger (highest priority):** A wake phrase in any of the three languages triggers the alert countdown hands-free. E.g. “Help me” / “እርዳታ” / “Na gargaari”. This is the killer feature — someone mid-aura who cannot coordinate a tap can still speak. Runs continuously in the background service, on-device wake-word spotting where possible to save battery, Voxide for intent recognition.
- **2. Voice cancellation of a false alarm:** During the countdown, the user says “I’m okay” / “ደህና ነኝ” / “Nagaan jira” to cancel without touching the screen. Solves the same coordination problem in reverse.
- **3. Voice-guided bystander interaction (creativity points):** The bystander can SPEAK to the phone during an active alert. “How long has it been?” → the phone answers with the elapsed seizure time. “What do I do now?” → repeats the current first-aid step. “Call for help” → dials emergency services. This is the demo moment that will stand out to judges — a stranger having a conversation with the phone of someone lying on the ground.
- **4. Voice-driven onboarding and medical profile entry:** Users with tremor or low literacy can set up their profile by speaking. “My medication is carbamazepine” → fills the field. Extends the accessibility story across the whole app, not just the emergency flow.
- **5. Voice queries on event history:** “When was my last seizure?” → spoken answer. Lower priority, but cheap to add once Voxide intent routing exists.

**Implementation note:** Build a single VoiceService module that wraps Voxide and routes intents to the AlertStateMachine. All five features above then become intent handlers on one shared pipeline rather than five separate integrations. This also makes the architecture easy to explain to judges.

## 2.3 Scholarxiv ideation trail — do this immediately

Ideation is the first of five judging criteria, and it has to be traceable, not just presentable. Judges want the problem you picked, the routes you rejected, and why you landed where you did. Post to Scholarxiv now, backfilling honestly with dated entries covering what you have already worked through:

- The problem: epilepsy/stroke falls in contexts with limited bystander knowledge and unreliable connectivity, grounded in the Ethiopian context.
- Routes rejected and why — this is the part teams skip and judges reward. Include: (a) full on-device seizure detection from phone motion, rejected because wearable research shows even wrist-worn sensors produce meaningful false-alarm rates, and a pocketed phone is noisier; (b) wearable hardware companion, rejected as out of scope for the timeline; (c) data-only alerting, rejected due to connectivity gaps, leading to the SMS fallback design.
- The research grounding — cite the accelerometer/EDA seizure-detection literature. Use the Scholarxiv Papers API to pull and reference these properly, since using the API counts in your favour.
- Clinical input from Care Epilepsy Ethiopia on the first-aid script — this is real primary-source ideation evidence most teams will not have.
- The pivot from “seizure detection” to “fall detection + voice trigger” — document this as a deliberate, evidence-driven scope decision. It reads as engineering maturity.

**Bonus:** The Scholarxiv MCP server is explicitly fair game and counts in your favour. If you have spare capacity, wire the MCP server into your own research workflow and mention it in a changelog — cheap points.

## 2.4 EthioDeploy — ship a web dashboard to claim the advantage

Hosting on EthioDeploy is a strong judging advantage, but only applies to websites and web platforms. A mobile-only app claims nothing. Fortunately we already have a natural web surface:

- **Caregiver web dashboard:** Emergency contacts open a link (from the SMS) in any browser and see the patient’s live location, alert status, and medical ID — with no app install required. This directly solves a real problem: contacts who do not have the app currently only get a text.
- **Also serves as:** the patient’s event history viewer, exportable for doctors or CEE. And a public landing page explaining the project.
- **Why this is worth the time:** It claims the EthioDeploy advantage, removes the app-install barrier for caregivers, and gives judges something they can open on a laptop during the presentation without needing your phone.

**Stack:** Keep it simple — a lightweight React or plain HTML/JS front end reading from the same Firebase/Supabase backend, deployed to EthioDeploy. This is a 1–2 day job for one team member working in parallel with the mobile work.

## 2.5 Changelogs and GitHub — the continuous record

Judges follow along for the whole round and comment on what you ship, and repositories are tracked for development progress, individual contributions, and overall activity. A history that starts at kickoff and moves steadily says more than a single large commit at the end.

- **Everyone commits under their own account.** Individual contributions are tracked. Do not let one person push everyone’s work — teamwork is a scored criterion and the repo is the evidence.
- **Commit daily, in small pieces.** Steady activity beats a single large dump. If you have local work not yet pushed, push it now in logical commits rather than one blob.
- **Post changelogs regularly, framed as a running log.** Use the observed style: feat / fix / docs prefixes with a short description of what changed and why.
- **Judges comment while you can still act.** Read and respond to their comments — visible responsiveness is part of how teamwork and building-under-pressure get assessed.
- **Nothing from before kickoff counts.** If any code predates SEP 09, do not include it. Rewrite it inside the repo history instead.

## 2.6 How the five judging criteria map to our project

No single criterion carries the round, and a team that thinks clearly and ships honestly beats a team that only demos well. Here is where we are strong and where we need to work:

| Criterion | Our strength | What we must do |
|---|---|---|
| Ideation | Strong — real clinical grounding via CEE, research-backed scope decisions, genuine local problem | Get it onto Scholarxiv with the rejected routes documented. Strength is worthless if untraceable. |
| Implementation strategy | Strong — offline-first, SMS fallback, layered trigger design, false-positive mitigation | Explain the reasoning in changelogs, not just the result. Show why each fallback exists. |
| Teamwork | Depends entirely on execution | Distinct GitHub contributors, clear role split, regular changelogs from more than one person. |
| Creativity | The voice-guided bystander interaction is our most original idea | Build feature 3 in section 2.2. A stranger talking to a phone on the ground is a memorable demo. |
| Building under pressure | Judged on the visible record | Daily commits and changelogs from here to OCT 02. Ship a working demo, not a deck. |

# 3. User personas

| Persona | Who they are | What they need |
|---|---|---|
| Patient / primary user | Person with epilepsy, stroke risk, or similar condition | One-tap or auto trigger, confidence it works offline, low battery drain, privacy |
| Emergency contact | Family member, caregiver, friend | Clear alert with location, low false-alarm rate, ability to confirm safety |
| Bystander | Stranger nearby during an event | Loud, clear, step-by-step first-aid instructions in their language, no app needed |

# 4. Screen-by-screen UI specification

Below is every screen the app needs, what it looks like, and what each element does.

## 4.1 Onboarding flow (first launch only)

### Screen 1: Welcome / language select

Full-screen with app logo and name at top. Three large tappable language buttons stacked vertically (Amharic, English, Oromo). This sets the UI language AND the default audio language. A small link at the bottom: "You can change this later in Settings."

**Key UI elements:**

- App logo + name centered at top
- Three language buttons (full width, ~56dp height each, rounded corners, accent color)
- "Change later" footnote text at bottom

### Screen 2: Medical profile setup

A simple form collecting the user's seizure/medical info. This data is stored locally only and shown on the bystander screen during an event.

**Key UI elements:**

- Name (text input)
- Condition type (dropdown: epilepsy, stroke risk, other — with free-text field for "other")
- Seizure type if epilepsy (dropdown: tonic-clonic, absence, focal, unknown/unsure)
- Current medications (text input, optional)
- Allergies (text input, optional)
- "Skip for now" link at bottom — all fields optional, can fill later in settings

### Screen 3: Emergency contacts

Add 1–5 emergency contacts. Each contact entry has name, phone number, and relationship. At least one contact is required to proceed. A note explaining that these people will receive SMS/data alerts with your GPS location during an event, and that they should be told in advance.

**Key UI elements:**

- Contact cards (name + phone + relationship, with delete icon)
- "+Add contact" button
- Explanatory note about what contacts will receive
- "Next" button (disabled until at least one contact added)

### Screen 4: Trigger setup

Explains the two trigger methods and lets the user configure them.

**Key UI elements:**

- Toggle: Enable manual trigger (on by default) — explains "press power button 3 times rapidly"
- Toggle: Enable fall detection (on by default) — explains "phone detects sudden fall + stillness and starts a 15-second countdown"
- Cancel window slider: 10–30 seconds (default 15) — "How long to wait before sending alert"
- "Done" button → goes to home screen

## 4.2 Home screen (main dashboard)

This is where the user spends 95% of their time. It needs to be dead simple — one glance tells you the app is running and ready.

### Layout

Clean, minimal screen. The entire center is dominated by a single large circular trigger button.

**Key UI elements:**

- **Status bar (top):** Small text showing "Protection active" in green or "Protection paused" in amber. Battery indicator for the app's background service. Connection status icon (wifi/cellular/offline).
- **Main trigger button (center):** Large circle (~200dp diameter), accent color, with a simple icon (hand/palm or shield). Label below: "Hold to alert" or "Tap 2x to alert" depending on setting. This button should be reachable with a thumb on any phone size.
- **Quick stats strip (below button):** Small, unobtrusive row: "Last event: 3 days ago" or "No events yet". Number of active contacts.
- **Bottom navigation bar:** 4 tabs — Home, History, Medical ID, Settings. Use clear icons + labels.

**Design principles for this screen:** High contrast, large touch targets (minimum 56dp), no clutter. The trigger button must be usable by someone with shaking hands or impaired coordination. Dark background option for visibility. Nothing on this screen should require reading small text to understand.

## 4.3 Alert sequence screens

### Screen A: Countdown / cancel window

Triggered by manual press or auto fall detection. Full-screen takeover with maximum urgency. Screen brightness goes to maximum.

**Key UI elements:**

- Large countdown number (e.g. "15") centered, counting down second by second
- Pulsing red/amber background that intensifies as countdown progresses
- Huge "I'M OKAY — CANCEL" button (full width, bottom third of screen, green, minimum 80dp height)
- Audio: repeated spoken prompt in user's language — "Alert will send in [N] seconds. Tap cancel if you are okay."
- Vibration pattern: steady pulse every second

### Screen B: Alert sent — bystander mode

Countdown reached zero or user didn't cancel. This is the screen bystanders see and hear. Designed for a stranger who picks up the phone off the ground.

**Key UI elements:**

- **Visual layout:** Maximum brightness. Large text in the detected/default language. Red header bar with "MEDICAL EMERGENCY — PLEASE HELP" in all three languages.
- **Audio playback (near-max volume, loops):** Pre-recorded first-aid instructions cycling through all three languages. Content (clinically reviewed):
- "This person may be having a seizure. Please help them."
- "Do NOT restrain them. Do NOT put anything in their mouth."
- "Clear the area around them of hard or sharp objects."
- "If possible, gently ease them onto their side."
- "Cushion their head with something soft."
- "Time the seizure. If it lasts more than 5 minutes, call emergency services."
- "Stay with them until they are fully conscious."

**Additional on-screen elements:**

- Medical ID card displayed prominently: name, condition, medications, allergies
- "Call emergency services" button (dials local emergency number)
- Language toggle buttons (AM / EN / OR) to switch audio and on-screen text
- Small "Patient returned — stop alert" button (requires hold-to-confirm to prevent accidental dismissal)

### Screen C: Alert sent — contact notification view

What emergency contacts receive (not a screen in the app itself, but defines the message format):

**Key UI elements:**

- SMS format: "[EMERGENCY] [Name] may be having a seizure/fall event. Location: [GPS link]. Time: [timestamp]. This is an automated alert from [AppName]. Please check on them or call emergency services."
- Data/push notification: Same content + a map pin + "Mark as responded" button in the notification
- If contact has the app installed: opens a live status screen showing the patient's location updating in real time

## 4.4 Event history screen

### Layout

A chronological list of all triggered events.

**Key UI elements:**

- Each event card shows: date/time, trigger type (manual/auto), duration (if seizure timed), location (map thumbnail), outcome (cancelled / alert sent / false alarm marked)
- Tap a card to expand: full details, which contacts were notified, response times
- Export button: generate a PDF/CSV summary (useful for sharing with doctors or CEE)
- Filter: by date range, trigger type, outcome

## 4.5 Medical ID screen

### Layout

Editable medical profile that doubles as what bystanders see during an alert.

**Key UI elements:**

- Name, photo (optional), condition, seizure type, medications, allergies, blood type (optional), emergency contact names and numbers
- "Preview bystander view" button — shows exactly what a stranger would see on the alert screen
- All data stored locally on device — explicit note: "This information never leaves your phone except during an active alert"

## 4.6 Settings screen

### Layout

Organized in clear sections.

**Key UI elements:**

- **Trigger settings:** Manual trigger method (power button 3x, volume button combo, or shake). Fall detection sensitivity (low/medium/high). Cancel window duration (10–30s slider).
- **Alert settings:** Audio volume override (always max, or follow system). Languages to cycle through. Alert message customization.
- **Contact management:** Add/edit/remove emergency contacts. Test alert button (sends a clearly marked test to contacts).
- **Language:** App UI language. Audio instruction language order.
- **Battery optimization:** Info about keeping the app alive in background. Auto-link to Android battery optimization settings for this app.
- **Data and privacy:** Export event history. Delete all data. Privacy policy link.

# 5. Frontend architecture

## 5.1 Recommended tech stack

| Layer | Technology | Why |
|---|---|---|
| Framework | Flutter (Dart) | Single codebase for Android + iOS. Strong in Ethiopia's developer community. Excellent offline/local storage support. |
| State management | Riverpod or BLoC | Clean separation of UI and logic. Handles the complex alert state machine well. |
| Local database | Hive or Isar | Fast, lightweight, no SQL overhead. Stores medical profile, contacts, event history on device. |
| Audio | audioplayers + flutter_tts | audioplayers for pre-recorded .mp3/.ogg files. flutter_tts as fallback for dynamic text if needed. |
| Background service | flutter_background_service | Keeps fall detection running when app is in background or screen is off. |
| Location | geolocator | GPS coordinates for alert messages. Works offline (caches last known location). |
| SMS | telephony / flutter_sms | Direct SMS sending without opening the SMS app — critical for when the user can't interact. |
| Hardware triggers | volume_key_board / power button listener | Listens for rapid power button presses or volume button combos even when screen is off. |
| Sensors | sensors_plus | Accelerometer + gyroscope access for fall detection algorithm. |

## 5.2 Key frontend components

The app's frontend is organized into these logical modules:

- **TriggerService:** Background service that listens for manual triggers (hardware buttons) and runs the fall detection algorithm on accelerometer data. This is the most critical component — it must be rock-solid and battery-efficient.
- **AlertStateMachine:** Manages the full alert lifecycle — idle → triggered → countdown → active → resolved. Handles transitions, timeouts, and cancellation. Everything else reacts to this state.
- **AudioManager:** Handles multilingual audio playback at max volume. Pre-loads audio files on app start. Cycles through languages on a timer (e.g., 30 seconds per language, then repeat).
- **ContactAlertService:** Sends alerts to emergency contacts. Tries data-based push notification first, falls back to SMS, retries on failure. Tracks which contacts have been reached.
- **LocationService:** Gets GPS coordinates. Caches last known location every 30 seconds when the app is active. Includes the location as a Google Maps / OpenStreetMap link in the alert message.
- **EventLogger:** Records every trigger, cancellation, and alert in the local database with timestamp, location, duration, and trigger type.

## 5.3 Fall detection algorithm (frontend, on-device)

This runs in the background service. It is a rule-based algorithm, not ML (for v1):

- **Step 1 — Freefall detection:** Monitor accelerometer magnitude (sqrt(x² + y² + z²)). If magnitude drops below 3 m/s² for more than 200ms, flag as potential freefall. Normal resting = ~9.8 m/s².
- **Step 2 — Impact detection:** Within 1 second after freefall, check for a spike above 25 m/s² (impact with ground). Both conditions must be met.
- **Step 3 — Stillness detection:** After impact, monitor for 3 seconds. If the phone remains relatively still (variance < threshold), classify as a confirmed fall. If the phone is moving normally (person picked it up, walking), classify as a drop/bump and ignore.
- **Step 4 — Trigger countdown:** If fall confirmed, start the cancel countdown. The person or a bystander can cancel during this window.

**Tuning:** The thresholds above are starting points. You will need to test with actual phones in pockets/hands and adjust. The sensitivity setting in the app (low/medium/high) shifts these thresholds — "high" is more sensitive (lower freefall threshold, shorter stillness window), "low" is stricter (fewer false positives but might miss some falls).

# 6. Backend architecture

The backend is intentionally lightweight. Most logic lives on the device. The backend handles what the phone can't do alone.

## 6.1 Tech stack

| Component | Technology | Purpose |
|---|---|---|
| Server | Firebase (free tier) or Supabase | Auth, real-time database, push notifications, hosting — free tier covers a competition and early users easily |
| Push notifications | Firebase Cloud Messaging (FCM) | Send alert notifications to contacts who have the app installed |
| SMS gateway | Twilio or AfricasTalking API | Send SMS alerts when data fails or contacts don't have the app. AfricasTalking has better Ethiopian carrier support and local pricing. |
| Auth | Firebase Auth (phone number) | Phone-number-based sign-in — no email needed, works for Ethiopian users |
| Database | Firestore (Firebase) or Supabase Postgres | Stores: user profiles (encrypted), contact links, alert event logs (for sharing with doctors) |
| Cloud function | Firebase Cloud Functions or Supabase Edge Functions | Receives alert from phone → fans out push notifications + SMS to all contacts in parallel |
| Location sharing | Real-time database (Firebase RTDB) | During active alert: streams patient's updating GPS to contacts who have the app |

## 6.2 Backend flow on alert trigger

When the countdown expires and an alert fires:

- **1. Phone sends alert payload to cloud function:** Contains: user ID, GPS coordinates, timestamp, trigger type (manual/auto), medical profile summary (encrypted).
- **2. Cloud function fans out:** For each emergency contact: send FCM push notification (if they have app) AND send SMS via gateway (always, as backup). Both happen in parallel.
- **3. Real-time location stream starts:** Phone writes GPS coordinates to a real-time database node every 10 seconds. Contacts with the app see a live-updating map.
- **4. "I'm okay" resolution:** When the alert is cancelled/resolved on the phone, cloud function sends a follow-up notification + SMS to all contacts: "[Name] has marked themselves as okay. Alert resolved."
- **5. Event logged:** Cloud function writes a summary to the events collection. Patient can later view/export this from the app.

## 6.3 Offline fallback (no data connection)

If the phone has no data connection when an alert fires:

- SMS is sent directly from the phone (no backend needed) to all emergency contacts with GPS coordinates
- Bystander audio plays from local storage (pre-downloaded, never streamed)
- When data reconnects, the phone syncs the event to the backend retroactively
- If there is no cell signal at all (no SMS either): bystander audio is the only defense. This is why the audio feature must be excellent.

# 7. Data models

## 7.1 Local storage (on device)

| Model | Fields | Notes |
|---|---|---|
| UserProfile | name, condition_type, seizure_type, medications, allergies, blood_type, photo_path, language_pref | Stored locally. Only sent to backend encrypted, only during active alerts. |
| EmergencyContact | id, name, phone, relationship, has_app, last_notified_at | 1–5 contacts. Phone number is the primary identifier. |
| AppSettings | trigger_method, fall_detection_enabled, sensitivity, cancel_window_seconds, audio_volume, language_order | All trigger/alert configuration. |
| EventLog | id, timestamp, trigger_type, location_lat, location_lng, duration_seconds, outcome, contacts_notified, synced_to_backend | Every trigger, including cancelled ones. |

## 7.2 Backend database

| Collection | Document fields | Access |
|---|---|---|
| users | uid, phone_number, fcm_token, created_at | Read/write by owner only |
| contacts | uid (owner), contact_phone, contact_name, relationship | Read/write by owner only |
| active_alerts | uid, location, timestamp, trigger_type, medical_summary_encrypted, status (active/resolved) | Read by owner's contacts during active alert |
| alert_history | uid, timestamp, trigger_type, location, duration, outcome, contacts_reached | Read by owner only. Export endpoint. |

# 8. UI design guidelines

These rules apply across all screens:

- **Color palette:** Primary/accent: deep blue (#2B6CB0). Danger/alert: red (#E53E3E). Success/safe: green (#38A169). Warning/countdown: amber (#D69E2E). Background: near-white (#FAFAFA) in light mode, near-black (#1A1A2E) in dark mode.
- **Typography:** Use a font that supports Ge'ez script (Amharic) natively. Noto Sans Ethiopic (Google Fonts, free) is the best option — it covers Latin + Ge'ez in one font family. Body: 16sp. Buttons/labels: 18sp bold. Emergency screen text: 24–32sp bold.
- **Touch targets:** Minimum 56dp for any interactive element. Emergency buttons (cancel, call): minimum 80dp height, full screen width.
- **Accessibility:** High contrast ratios (4.5:1 minimum for normal text, 3:1 for large text). No information conveyed by color alone. Screen reader labels on all interactive elements.
- **Animations:** Minimal. Countdown pulse is the only animation that matters. Everything else should be instant. No loading spinners during an emergency flow — it must feel instantaneous.
- **Dark mode:** Essential. A phone screen at max brightness in a dark room during an event should not blind the bystander — but the emergency content must still be readable. Red/white on dark background works well.

# 9. Build plan — SEP 25 to OCT 10

**About 15 days of build time. That is enough to ship something genuinely good — but judges will expect a working prototype to be the floor, not the achievement. Plan to finish the core in the first week so the second week goes to the differentiating features and rehearsal, not to firefighting.**

## 9.0 Today (SEP 25) — idea submission day

Only two things matter today. Everything else can wait until tomorrow.

- **Submit the idea with voice in the headline.** See the callout in section 2. The submitted concept is locked — if voice is not in it, we cannot make it our lead feature later.
- **Create the GitHub repo and make the first commit today.** Even if it is just a README with the concept and team roles. Judges track development progress across the whole round, and a repo that starts on day one and moves steadily reads far better than one that appears in week two.
- **Optional but cheap:** post a first Scholarxiv entry describing the problem. Starts the ideation trail on the correct date.

## 9.1 Days 1–2 (SEP 26–27) — de-risk and set up

Do these in parallel, one person each. The goal is that by the end of day 2 nothing unknown remains that could sink the project.

| Owner | Task | Why it is first |
|---|---|---|
| Person A | Voxide spike: get ONE voice intent working end to end — even just a wake phrase printing to console. Confirm Amharic and Afaan Oromo actually work, not just English. | This is the mandatory requirement and the biggest unknown. If Voxide cannot do Amharic well, we need to know on day 1, not day 12. |
| Person B | Flutter project scaffold, background service running, accelerometer data streaming, SMS permission working on a real device | Android background services and SMS permissions are where Flutter projects lose days. Find the pain early. |
| Person C | Scholarxiv ideation trail: problem, rejected routes, research citations, CEE clinical input | Mandatory rule 1 and the first judging criterion. Independent of the code, so it can run fully in parallel. |
| Person D/All | Record the first-aid audio in all three languages. Script from section 4.3, reviewed by CEE first. | Recording depends on people and scheduling, not code. Start it early or it becomes the last-minute blocker. |

## 9.2 Days 3–6 (SEP 28 – OCT 01) — core loop

Target: by OCT 01 the complete primary flow works on a real phone.

- **Voice-activated trigger via Voxide:** Wake phrase in all three languages starts the countdown hands-free. Highest priority feature in the project — it satisfies the mandatory voice rule and it is our strongest accessibility story.
- **Voice cancellation:** Speaking “I’m okay” during the countdown cancels. Same Voxide pipeline, small addition.
- **Manual trigger + countdown screen:** On-screen button and hardware-button trigger, 15-second cancel window, pulsing UI, spoken countdown prompt.
- **SMS alert with GPS:** Sent directly from the phone, no backend required, works with no data connection.
- **Bystander alert screen + looping multilingual audio:** Max volume, max brightness, medical ID displayed, language toggle.

**Milestone (OCT 01):** Speak a phrase → countdown → SMS with live location arrives on a second phone → first-aid audio plays in three languages. At this point the project is compliant and demoable even if everything after this fails.

## 9.3 Days 7–10 (OCT 02–05) — differentiation

This is where the project stops being competent and starts being competitive.

- **Voice-guided bystander interaction:** The bystander speaks to the phone during an active alert — “How long has it been?”, “What do I do now?”, “Call for help” — and gets spoken answers. This is our creativity score and the moment judges will remember. Build it before fall detection if you have to choose.
- **Fall detection:** Freefall + impact + stillness per section 5.3. Rule-based is enough. Budget two days including on-device tuning with a real phone in a real pocket — the tuning always takes longer than the algorithm.
- **Caregiver web dashboard on EthioDeploy:** Contacts open the SMS link in a browser and see live location, alert status and medical ID with no app install. Claims the EthioDeploy advantage and gives judges something to open on a laptop.
- **Multiple emergency contacts + event history:** Straightforward once the core works.

## 9.4 Days 11–13 (OCT 06–08) — harden and polish

- **Edge cases, seriously:** No signal, no GPS fix, permissions denied, low battery, phone locked, phone face-down, screen off, incoming call during an alert. Judges and real users both find these.
- **Battery testing:** Leave the background service running for a full day and measure the drain. Have a real number ready — you will be asked.
- Onboarding flow, settings screen, medical ID editor
- Accessibility pass: contrast, touch target sizes, screen reader labels, Ge’ez font rendering
- False-positive testing: carry the phone through normal activity (walking, stairs, a bus ride, setting it down hard) and count how often fall detection fires incorrectly. Tune the sensitivity thresholds against real data and record the numbers — this is exactly the kind of evidence that wins the implementation-strategy criterion.

## 9.5 Days 14–15 (OCT 09–10) — freeze and rehearse

**Feature freeze on OCT 08. Nothing new after that date. Teams lose hackathons by breaking a working demo with a last-minute feature far more often than by shipping one feature fewer.**

- Rehearse the full demo (section 10) at least five times on the exact device you will present with
- Prepare for demo failure: record a backup video of the working flow, and have a second phone charged and configured
- Test the demo in a noisy room — voice recognition behaves very differently with background noise, and the presentation room will not be quiet
- Final changelog summarising the arc of the build
- Confirm who presents and who attends announcement day

## 9.6 Cut list — drop these first if you fall behind

None of these will cost meaningful points:

- ML-based fall detection — rule-based is fine, pitch ML as future work
- iOS build — Android only is completely acceptable
- Push notifications via FCM — SMS already covers it and works offline
- Voice-driven profile entry and history queries — not scored differently from the voice trigger
- Contact-side mobile app — the web dashboard replaces it and scores better
- Full backend — if time gets tight, SMS-direct-from-phone plus a static web dashboard covers everything mandatory

## 9.7 Standing rhythm for the whole round

- **Everyone commits under their own account, every day.** Individual contributions are tracked and teamwork is a scored criterion — the repo is the evidence.
- **Post a changelog daily, framed as a running log.** Use feat / fix / docs prefixes and say what changed and why. Judges comment while you can still act on it — respond to them.
- **Keep a decisions log.** Every time you reject an approach, write down why. This feeds the ideation criterion and costs nothing at the time.
- **Demo internally every Friday.** Force the app to actually run end to end weekly. It surfaces integration breakage while there is still time.

# 10. Demo script for announcement day

Judges are looking at a functioning product, not a deck describing one, and a working prototype is the floor rather than the achievement. Structure the live demo to hit all five criteria in order:

- **1. Open with the problem (20 sec):** Someone has a seizure in a place where nobody knows what to do, with no reliable connection. Name the CEE connection — real clinical grounding, not a hypothetical.
- **2. Voice trigger, live (30 sec):** Speak the wake phrase. Countdown starts. Explain why voice matters here: a person mid-aura may not be able to tap but can still speak. This is the moment that proves the voice requirement is meaningful rather than bolted on.
- **3. Let it fire (30 sec):** Countdown reaches zero. Phone starts the multilingual instructions at full volume. A judge’s phone receives the SMS with the location link in real time.
- **4. The bystander conversation (45 sec):** Have a teammate play a bystander and talk to the phone — ask how long it has been, ask what to do. The phone answers aloud. This is the memorable moment.
- **5. Open the web dashboard (20 sec):** A judge opens the SMS link on a laptop and sees the live location and medical ID, with no app installed. Mention it is hosted on EthioDeploy.
- **6. Close on airplane mode (20 sec):** Turn on airplane mode and trigger again. Audio still plays. Explain the offline-first reasoning and the SMS fallback. Reliability is the thing that separates a real product from a demo.
- **7. Point at the trail (15 sec):** Scholarxiv ideation, the commit history, the changelogs. Show that the idea is traceable, not just presentable.

# 11. Pitch angles

Things to emphasise, mapped to what is actually scored:

- **Voice as genuine accessibility, not compliance:** Most teams will bolt voice on. For us it is the answer to a real problem — a person who cannot coordinate a tap can still speak. Lead with this.
- **Local-first design:** Three Ethiopian languages, SMS fallback for connectivity gaps, works fully offline. Designed for the Ethiopian context from day one rather than localised afterwards.
- **Clinical grounding:** First-aid instructions reviewed by epilepsy clinicians at CEE. Medical ID follows real emergency protocols. Event logging produces data useful for seizure management.
- **False-positive mitigation as a design decision:** The cancel window, sensitivity tuning and voice cancellation are not afterthoughts — they prevent the primary failure mode of alert apps, which is contacts learning to ignore alerts.
- **Evidence-driven scope:** We deliberately chose fall detection over seizure detection because the wearable research shows even dedicated wrist sensors produce meaningful false-alarm rates. Showing a rejected route with a reason is exactly what the ideation criterion asks for.
- **Privacy-first:** Medical data stored on-device, shared only during active emergencies. Contacts need no account and no app.
- **Scalable beyond epilepsy:** The same core works for stroke, cardiac events and elderly falls. Mention as future scope.

--- End of specification ---
