# P.A.Z.I.Y.O.N: Android app (Flutter)

The real app from the spec (section 5). The logic is ported one-to-one from the tested browser prototype: same states, thresholds, phrases, message formats and dashboard link. An SMS sent by the app opens the same caregiver dashboard.

## What works

| Feature | How |
|---|---|
| Voice trigger / voice cancel / bystander Q&A in AM, OR, EN | **Voxide** (natural voice, hears all three languages, calls the app's capabilities), run in a hidden WebView by `lib/services/voxide_bridge.dart`. Needs a `vox_pub_` key: see [docs/VOXIDE_SETUP.md](../docs/VOXIDE_SETUP.md). Without one, Android's recognizer (`speech_to_text`) is the fallback |
| **Loud siren during an alert** | 6 s before the first step and 3 s between steps, on the alarm channel at full volume (sounds on silent). Bystanders can tap **Silence siren**; off in Settings |
| Hold-to-alert button, countdown (10–30 s) with spoken prompt and vibration | `AlertStateMachine` |
| Fall detection (freefall → impact → stillness) | `sensors_plus` accelerometer at game rate, plus **Simulate a fall** |
| Alert SMS with GPS link, sent **directly from the phone** (works offline) | `another_telephony`; falls back to the SMS app if permission is refused |
| "I'm okay" follow-up SMS when the alert is resolved | spec 6.2 step 4 |
| Bystander mode: 3-language header, looping first-aid steps, language toggle, medical ID, call 907, hold-to-stop | `flutter_tts`, or recordings in `assets/audio/<lang>/step-N.mp3` once added |
| **Protection with the app closed or the screen off** | Foreground service runs the same fall detector. With nobody at the phone, it counts down in a full-screen notification (with an **I'm okay** button), sends the SMS itself, and speaks the first-aid steps. Opening the app takes over with the same timing, and nothing is sent twice |
| **Help with the phone locked or the screen off** | Press the **power button 3 times** within 3 seconds (`packages/power_trigger` counts screen on/off changes in the background service), or tap **Get help now** on the lock-screen notification |
| **Amharic and Afaan Oromo spoken output** | Voxide's voice when connected. Offline fallback: bundled clips in `assets/audio/` (espeak-ng, robotic; replace any clip with a human recording of the same name) |
| History (copy as CSV), Medical ID, Settings, up to 5 contacts | stored on the device only (`shared_preferences`) |

## Not yet

- **Voice with the app closed.** Android only lets the speech recognizer run while the app is on screen. The background service covers falls, not voice.
- **Real-device check of background protection.** It is covered by unit and widget tests but not yet tried on a phone. Battery-saver settings on some phones (Tecno, Infinix, Xiaomi) kill foreground services, so test it on the demo phone.
- **A live Voxide test.** The bridge, capabilities and fallbacks are covered by tests with a fake Voxide, but not yet run against the real service. Try it on the demo phone with the team's key first.
- **Amharic and Afaan Oromo recognition without Voxide.** Android's recognizer handles Amharic only on some phones, and no phone handles Afaan Oromo. Offline, the app falls back to English with an on-screen reason.
- **Recorded first-aid audio.** Add the files and register `assets/audio/` in `pubspec.yaml`.
- **Live dashboard.** The link carries a snapshot of the alert until the backend exists.

## Build and run

```bash
cd app
flutter pub get
flutter test                      # 64 tests: core logic, background rules, full-app flows with fake phone services and a fake Voxide
flutter run                       # on a connected Android phone
flutter build apk --release --dart-define=DASHBOARD_URL=https://<host>/dashboard.html --dart-define=VOXIDE_KEY=vox_pub_…
```

CI (`.github/workflows/ci.yml`) runs the tests and builds `app-release.apk` on every push. Download it from the run's **Artifacts**. Set the repository variable `DASHBOARD_URL` to include the dashboard link in the SMS, and `VOXIDE_KEY` to build the Voxide key in. The release APK is signed with the debug key, which is fine for sideloading a demo but not for the Play Store.

On first use, Android asks for notification, microphone, location and SMS permissions. Grant all of them for the full demo. For the background countdown to cover the lock screen on Android 14+, also allow **full-screen notifications** for the app in system settings.

## Layout

```
lib/core/       pure logic (ported from prototype/js/core): state machine, fall detector, voice intents, content, SMS/link
lib/services/   services.dart = interfaces; device_services.dart = the real Android implementations;
                voxide_bridge.dart = Voxide in a hidden WebView (page and SDK in assets/voxide/);
                background_service.dart = the foreground service (fall detection with the app closed)
lib/core/background_coordinator.dart   the rules for who handles a fall: app or service
lib/app_controller.dart   alert lifecycle, bystander loop, voice routing, persistence
lib/ui/         screens: welcome, tabs (home/history/medical/settings), countdown, bystander, resolved
test/           unit tests + widget tests driving the whole app through fakes (test/fakes.dart)
```
