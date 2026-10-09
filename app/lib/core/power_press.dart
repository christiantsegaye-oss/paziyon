// Detects rapid power-button presses from screen on/off changes. Each press
// toggles the screen, so three presses within a few seconds give three
// toggles, starting from either state. Ordinary use (turn on, glance, turn
// off) gives two, spread out.

class PowerPressDetector {
  PowerPressDetector({required this.onTriggered, this.presses = 3, this.window = const Duration(seconds: 3)});

  final void Function() onTriggered;
  final int presses;
  final Duration window;
  final _times = <int>[];

  /// [t] is the toggle time in milliseconds.
  void toggle(int t) {
    _times
      ..add(t)
      ..removeWhere((x) => t - x > window.inMilliseconds);
    if (_times.length >= presses) {
      _times.clear();
      onTriggered();
    }
  }
}
