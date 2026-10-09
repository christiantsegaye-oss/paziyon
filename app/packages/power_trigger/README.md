# power_trigger

Android apps cannot read the power button, but every press turns the screen on
or off. This plugin streams those changes so the app's background service can
count rapid presses (see `PowerPressDetector` in the app) and start an alert
with the phone locked or the screen off.

It is a plugin rather than app code so it is also registered in the background
service's own Flutter engine.
