# Browser prototype

A clickable demo of the whole alert flow, built so the idea can be shown before the Flutter app exists. It runs in any modern browser with no build step and no backend.

| Spec feature | In this demo |
|---|---|
| Voice trigger: “Help me” / “እርዳታ” / “Na gargaari” | ✅ Web Speech API; typed phrases use the same pipeline |
| Voice cancel: “I’m okay” / “ደህና ነኝ” / “Nagaan jira” | ✅ |
| Bystander talks to the phone | ✅ “How long has it been?”, “What do I do now?”, “Next”, “Repeat”, “Call for help”, “Any medication?”, answered in the language asked |
| Hold-to-alert button, countdown with cancel window | ✅ 10–30 s, spoken prompt, vibration, pulsing screen that gets redder |
| Fall detection (freefall → impact → stillness) | ✅ real accelerometer on a phone; **Simulate a fall** on a laptop |
| Bystander mode | ✅ three-language header, looping first-aid steps, language toggle, medical ID, call 907, hold-to-stop |
| SMS with GPS link | ⚠️ opens the SMS app pre-filled (browsers can't send SMS on their own; the Android app will) |
| Caregiver web dashboard | ⚠️ `dashboard.html`: status, map and medical ID from the SMS link. Not live yet: no backend |
| Event history + CSV export, Medical ID, settings, contacts | ✅ stored on the device only |

**Voxide:** paste a `vox_pub_` key under **Settings → Voxide voice** and Voxide does the listening, speaking and acting, with the same engine as the Android app (`vendor/paziyon-voxide.js`). See [docs/VOXIDE_SETUP.md](../docs/VOXIDE_SETUP.md); a hosted copy needs its domain allowed in the Voxide dashboard. Without a key the browser's speech recognizer (`js/services/voiceService.js`) and the recorded clips are used.

**Siren:** during an alert a loud siren plays for 6 s before the first step and 3 s between steps (`js/services/siren.js`). Bystanders can tap **Silence siren**; turn it off under **Settings → Alert**.

## Run it

```bash
cd prototype
npm start            # node server.js (no dependencies; uses $PORT if set)
# open http://localhost:8080
npm test             # unit tests for the core logic (Node 18+)
```

- **Voice input** needs microphone permission. With Voxide, any modern browser works and all three languages are heard. Without it, use Chrome or Edge: Amharic (`am-ET`) works in Chrome, and Afaan Oromo has no browser recognizer, so type Oromo phrases.
- **Hosting (EthioDeploy or any Git-based host):** root directory `prototype`, no build command. As a static site, publish the folder as it is. As a Node app, the start command is `npm start`, and `server.js` listens on the host's `$PORT`. Then add the site's domain in the Voxide dashboard, or leave the whitelist blank.
- **On a phone** (motion sensor, SMS, calling), serve over HTTPS. Browsers block the microphone, motion sensor and location on plain `http://` except on `localhost`. Deploying the folder to EthioDeploy or any static host is enough.
- **Spoken output** uses recordings from `audio/` when present, otherwise the browser's voices. Most browsers have no Amharic or Oromo voice, so that text appears on screen only until the recordings are added.

## Demo script (about 3 minutes)

1. Pick a language on the welcome screen. This loads a demo profile. Add a teammate's number under **Settings → Emergency contacts**.
2. **Voice trigger:** say “Help me” (or type it). The countdown starts.
3. **Voice cancel:** say “I’m okay”. The alert is cancelled and logged.
4. **Fall:** press **Simulate a fall** and watch the stages (freefall → impact → stillness), then let the countdown run out.
5. **Bystander conversation:** ask “How long has it been?”, then “What do I do now?”, then “ምን ያህል ጊዜ ሆነ?”. The phone answers each in the language it was asked in.
6. **SMS + dashboard:** tap **Send alert SMS** and send it. Open the link on a laptop to show the caregiver dashboard.
7. **Hold to stop**, then send the “I’m okay” SMS. Show the event in **History**.

## Layout

```
index.html, dashboard.html, css/app.css
js/core/        pure logic, unit-tested: alert state machine, fall detector, voice intents, content, SMS/link format
js/services/    browser adapters: voice, speech output, location, motion, storage
js/app.js       UI wiring
test/           node --test
audio/          first-aid recordings go here
```

The code in `js/core/` is a reference implementation for the Flutter port: same states, thresholds, phrases and message formats.

> The Amharic and Afaan Oromo first-aid text and answers are drafts. They must be reviewed by native speakers and by Care Epilepsy Ethiopia before real use.
