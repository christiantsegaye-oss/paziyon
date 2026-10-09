import 'package:flutter/services.dart';

/// Screen on/off changes, one event per change, as milliseconds since epoch.
/// Each power-button press produces one. Android only; elsewhere the stream
/// is empty.
Stream<int> screenToggles() => const EventChannel('com.paziyon/power_trigger/screen')
    .receiveBroadcastStream()
    .map((t) => (t as num).toInt());
