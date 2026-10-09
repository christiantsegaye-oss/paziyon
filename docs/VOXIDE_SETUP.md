# Voxide setup

[Voxide](https://voxide.app) is P.A.Z.I.Y.O.N's voice layer, as the STARK hackathon requires. When it is connected, it does three jobs:

- It **listens**. It hears "help" and "I'm okay" in Amharic, Afaan Oromo and English, and it hears bystanders' questions.
- It **speaks** in a natural voice. It reads out the countdown prompt, every first-aid step and every answer.
- It **acts**. It calls the app's capabilities: start or cancel the alert, get the alert status, get a first-aid step, get the medical ID, and call 907.

Without a key, or with no internet, the app still works. It falls back to the phone's own speech recognizer and to the recorded clips.

## 1. Get a key

1. Sign in at **voxide.app** and create a project, or open an existing one.
2. Copy its **publishable key**. It starts with `vox_pub_`.
   - Publishable keys are meant to sit in client code. Voxide limits where they can be used by domain, so the key is not a secret.
   - Never put a secret or server key in the app.

## 2. Put the key in

| Where | How |
|---|---|
| **Android app, one phone** | Open **Settings → Voxide voice → Voxide key** and paste the key. The status line under it reads "Connected to Voxide" once it is connected. |
| **Android app, every APK from CI** | In GitHub, open **Settings → Secrets and variables → Actions → Variables** and add `VOXIDE_KEY` = `vox_pub_…`. CI builds it in with `--dart-define=VOXIDE_KEY=…`. A key typed in Settings still overrides it. |
| **Local APK build** | `flutter build apk --release --dart-define=VOXIDE_KEY=vox_pub_…` |
| **Web demo** | Open **Settings → Voxide voice → Voxide key**, paste it, then tap anywhere on the page so the browser allows sound. |

## 3. Allow the domains

Voxide accepts a publishable key only on domains you have whitelisted for the project in its dashboard.

- **Android app:** nothing to do. The app runs Voxide inside a hidden WebView that loads from `http://localhost`, and Voxide always allows `localhost`.
- **Web demo on your laptop** (`npm start` → `http://localhost:8080`): nothing to do, for the same reason.
- **Web demo hosted on EthioDeploy** (or any other host): add that domain to the project's allowed domains.

## 4. Agent prompt (optional)

The app sends its own instructions and live state with every turn, so you can leave the dashboard prompt empty. If you want to set one anyway, use this:

> You are P.A.Z.I.Y.O.N, the emergency voice of a seizure and fall alert app in Ethiopia. Reply in the language the person speaks: Amharic, Afaan Oromo or English. Keep every reply to one or two short, calm sentences. If anyone asks for help or sounds unwell, call start_emergency_alert at once. During an alert you are talking to bystanders: use the app's tools and read the results aloud. Never give medical advice beyond the first-aid steps the app returns.

The capabilities are registered from code, in `paziyon-voxide.js`, so you do not need to create them in the dashboard.

## How it fits together

```
app/assets/voxide/
  voxide.browser.js    Voxide SDK (@voxide/react 0.8.0, MIT, see VOXIDE_LICENSE)
  paziyon-voxide.js    P.A.Z.I.Y.O.N engine: capabilities, instructions, reconnects, say()
  bridge.html          page the Android app runs in a hidden WebView
app/lib/services/voxide_bridge.dart   Dart side of the bridge (VoiceAgent)
app/lib/app_controller.dart           handleAgentTool(): what each capability does
prototype/vendor/                     same three files for the web demo (a test keeps them identical)
```

- **One microphone owner.** While Voxide is connected, it is the only thing listening; the phone's recognizer is off.
- **When Voxide runs.**
  - It always runs during a countdown or an alert.
  - It also runs while idle when **Listen with Voxide all the time** is on.
  - Turn that switch off to save Voxide minutes.
- **What reads the steps aloud.** During an alert, Voxide reads each first-aid step word for word. If Voxide is not connected at that moment, the recorded clip plays instead.
- **Trigger and cancel phrases.** The app also matches these itself from Voxide's live transcript, as a backup if the agent does not call its tool.
- **If the Voxide plan runs out**, the app shows "The Voxide plan has run out of voice sessions" and switches to the fallback.

## Siren

During an alert, the phone sounds a loud two-tone siren to draw people over:

- **6 seconds** before the first instruction,
- **3 seconds** between steps.

The siren pauses whenever a bystander speaks, so the phone can hear them and they can hear it.

On Android it plays on the **alarm** channel at full volume, so it sounds even when the phone is on silent. The app restores the previous volume afterwards.

Turn it off with **Settings → Alert → Siren**. A bystander can stop it with **Silence siren**. To regenerate the sound, run `python3 tools/generate_siren.py`.
