import 'package:flutter_test/flutter_test.dart';
import 'package:seizure_alert/core/power_press.dart';

void main() {
  late int triggers;
  late PowerPressDetector d;
  setUp(() {
    triggers = 0;
    d = PowerPressDetector(onTriggered: () => triggers++);
  });

  test('three presses within 3 seconds trigger', () {
    for (final t in [0, 400, 900]) {
      d.toggle(t);
    }
    expect(triggers, 1);
  });

  test('turning the screen on and off normally does not', () {
    for (final t in [0, 5000, 60000, 64000]) {
      d.toggle(t);
    }
    expect(triggers, 0);
  });

  test('presses spread over more than 3 seconds do not', () {
    for (final t in [0, 2000, 4500]) {
      d.toggle(t);
    }
    expect(triggers, 0);
  });

  test('one burst triggers once, and a second burst triggers again', () {
    for (final t in [0, 300, 600, 900, 1200]) {
      d.toggle(t);
    }
    expect(triggers, 1);
    for (final t in [20000, 20300, 20600]) {
      d.toggle(t);
    }
    expect(triggers, 2);
  });
}
