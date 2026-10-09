# Decisions log

Every approach we consider and reject is recorded here with the reason. This log feeds the Scholarxiv ideation trail (STARK rule 1, and the first judging criterion).

Format: date · decision · alternatives considered · why.

---

## 2026-09-25 · Detect falls, not seizures

- **Chosen:** rule-based fall detection (freefall → impact → stillness) plus manual and voice triggers.
- **Rejected:** full seizure detection on the phone from motion data.
- **Why:** wearable research shows that even wrist-worn accelerometer/EDA sensors produce a meaningful rate of false alarms, and a phone in a pocket gives noisier data. Frequent false alarms teach contacts to ignore alerts, which is the main way alert apps fail. _Citations to be added from the Scholarxiv Papers API._

## 2026-09-25 · No wearable hardware companion

- **Rejected:** a custom wearable sensor paired with the phone.
- **Why:** it can't be built, tested and tuned within the ~15-day build window. The phone alone covers the core flow. A wearable remains possible future work.

## 2026-09-25 · SMS fallback alongside data alerts

- **Rejected:** alerting over data only (push notifications / backend).
- **Why:** data connectivity in Ethiopia is unreliable. SMS is sent straight from the phone with no backend, so the alert still goes out offline. When data is available, the backend also sends push notifications and SMS.

## 2026-09-25 · Voice-first product, not just voice output

- **Chosen:** Voxide voice interaction as the lead feature: voice trigger, voice cancel, and a bystander Q&A conversation.
- **Rejected:** pre-recorded bystander audio as the only voice feature.
- **Why:** playing audio is voice output, not voice interaction, so it does not meet STARK rule 2. Voice input also solves a real accessibility problem: someone mid-aura or already on the ground may not be able to tap a button but can still speak.

## 2026-09-25 · Caregiver web dashboard in place of a contact-side app

- **Chosen:** a browser dashboard linked from the SMS, hosted on EthioDeploy.
- **Rejected:** requiring emergency contacts to install the mobile app.
- **Why:** contacts don't have to install anything, judges can open it on a laptop, and hosting on EthioDeploy is a judging advantage.

## 2026-09-25 · Pre-recorded first-aid audio instead of on-the-fly TTS

- **Chosen:** clinically reviewed recordings in Amharic, Afaan Oromo and English, stored on the device. `flutter_tts` is used only for dynamic answers, such as elapsed time.
- **Why:** it works with no connectivity, TTS quality for Amharic and Afaan Oromo is uncertain, and Care Epilepsy Ethiopia can review the exact wording.

## 2026-09-25 · Browser prototype before the Flutter app

- **Chosen:** a static web prototype of the whole flow, with the logic in pure, unit-tested modules.
- **Why:** it can be demoed on any laptop or phone from day 0 and exercises the state machine, fall detection thresholds and voice intents before the Flutter build starts. The browser's speech engine stands in for Voxide behind one `VoiceService`, so swapping it only changes the engine.

## 2026-09-25 · Filter out the app's own voice

- **Problem:** found while testing. The microphone hears the phone speaking. The countdown prompt contains "cancel", and a first-aid step contains "call emergency services".
- **Chosen:** drop any transcript whose words mostly match something the app said recently, and route intents only by alert state (trigger when idle, cancel during the countdown, questions during an alert).
- **Rejected:** muting the microphone while the phone speaks. In bystander mode the phone is almost always speaking, so bystanders could never be heard.

## 2026-09-25 · App architecture: interfaces over plugins, no state-management package

- **Chosen:** every phone capability (voice, speech, location, motion, SMS, storage, screen) sits behind a small interface in `app/lib/services/services.dart`. One `ChangeNotifier` controller holds the app state.
- **Why:** the whole emergency flow can be tested with fakes, without a phone, and Voxide can replace the stand-in recognizer by changing one class. The spec suggests Riverpod or BLoC. The app has one screen state (the alert lifecycle) and one owner, so a plain controller is simpler to read and to explain to judges. We can revisit this if the app grows.
- **Storage:** `shared_preferences` with JSON instead of Hive or Isar. There's little data (one profile, up to 5 contacts, event history), and Hive's maintenance status is uncertain.

## 2026-09-25 · Send SMS directly, with the SMS app as a fallback

- **Chosen:** send the alert SMS directly with `SEND_SMS` permission. If permission is refused or sending fails, open the SMS app pre-filled.
- **Why:** the person may not be able to press send (spec 5.1), so sending directly is the goal. The fallback means an alert still goes out if the permission was refused.

## 2026-09-25 · Background protection: the service alerts on its own

- **Problem:** after a fall the person may be unconscious with the phone in a pocket. An app that only alerts while it's open does nothing in exactly that case.
- **Chosen:** a foreground service (type `health`) runs the fall detector. If the app is on screen, meaning it sent a heartbeat in the last 10 s, the service hands the fall to the app, which has voice cancel. Otherwise the service runs the countdown, sends the SMS and speaks the first-aid steps itself. Opening the app takes over the alert with its original timing.
- **Rejected:** always forwarding to the app, which does nothing if the app was killed. Rejected always alerting from the service, which would double-alert when the app is open. Rejected an "app is visible" flag with no expiry, because a killed app could leave it set and swallow a real fall.
- **Limit:** voice can't run in the background on Android. The voice trigger needs the app on screen.

## 2026-09-27 · Act on partial speech results, once per utterance

- **Problem:** on a real phone the voice trigger listened but never acted. Android often ends a session on silence without sending a final result, and the app only acted on final results.
- **Chosen:** act on the first partial result that matches an intent, and ignore the rest of that utterance. Questions to the phone with no matching intent are answered once, on the final result.
- **Rejected:** waiting for final results only, which is what failed. Rejected acting on every partial, which would answer one question several times.

## 2026-09-27 · Language fallback instead of silent failure

- **Chosen:** if the recognizer can't do the chosen language, listen in English and say so on screen. Typed Amharic and Oromo phrases still work, and Voxide will replace the recognizer for those languages.
- **Why:** a voice feature that fails silently is worse than one that clearly says what it can do. This matters most in a demo.

## 2026-09-27 · Name and visual design

- **Name:** FirstVoice. It combines "first aid" and "voice": the phone is the first voice at the scene. It lives in one constant (`appName` in `app/lib/ui/theme.dart`, `APP_NAME` in `prototype/js/app.js`) so it's easy to change.
- **Design:** calm and legible under stress rather than flashy. Low layout variety, little motion, and one accent colour that always means emergency. Emoji were replaced by icons because they render differently on every phone.

## 2026-10-01 · Amharic and Afaan Oromo: bundled audio now, Voxide for recognition

- **Spoken output:** neither language has a text-to-speech voice on Android, so the clips are pre-generated with espeak-ng (offline, open source) and bundled. Meta's MMS-TTS sounds better, but its host is blocked from the build environment and it is licensed non-commercial. The spec's plan of human recordings reviewed by Care Epilepsy Ethiopia stays the goal: same file names, drop-in replacements.
- **Recognition:** no on-device engine recognizes Afaan Oromo, and Amharic works only on some phones, online. Cloud services exist (Addis AI, EthiopicAI), but the hackathon requires Voxide, so recognition waits on Voxide's API. The `VoiceInput` interface means only one class changes.

## 2026-10-01 · Triggering help with the phone locked

- **Chosen:** three power-button presses within 3 seconds, counted from screen on/off changes in the background service, plus a Get help now button on the lock-screen notification.
- **Rejected:** volume-button combinations, which need an accessibility service and would get the app rejected or flagged on most phones. Rejected listening for voice with the screen off, which Android blocks.
- **Name:** P.A.Z.I.Y.O.N, chosen by the team. It replaces FirstVoice everywhere (`appName` / `APP_NAME`).

## 2026-10-09 · Voxide as the voice, with a siren

- **Why now:** the espeak-ng clips were too robotic to understand in Amharic and Afaan Oromo, and the hackathon requires Voxide. Voxide's agent hears and speaks all three languages in a natural voice.
- **How the Android app runs it:** Voxide ships as a browser SDK, so the app hosts it in a hidden 1×1 WebView, on a page the app serves itself from `http://localhost`. Voxide allows localhost without domain whitelisting, and localhost counts as a secure origin for the microphone. Rejected: re-implementing Voxide's protocol in Dart (undocumented, would break on SDK updates).
- **Shared engine:** one file, `paziyon-voxide.js`, registers the capabilities and instructions for both the app and the web demo, so they behave the same.
- **The app stays in charge:** the agent acts only through the app's capabilities (start or cancel the alert, status, first-aid step, medical ID, call 907). It reads first-aid steps word for word and gives no medical advice of its own. The app also matches trigger and cancel phrases from Voxide's transcript, in case the agent doesn't call its tool.
- **Offline fallback kept:** an emergency can happen without data, so the phone recognizer, the bundled clips and SMS still work with no connection.
- **Siren:** a voice alone doesn't carry across a street or market. A generated two-tone siren (no licensing questions) plays on Android's alarm channel at full volume, before and between steps. It pauses whenever a bystander speaks, and they can silence it.
