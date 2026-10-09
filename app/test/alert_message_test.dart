import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:seizure_alert/core/alert_message.dart';

void main() {
  final alert = AlertDetails(
    status: AlertStatus.active,
    trigger: 'voice',
    time: DateTime.utc(2026, 9, 25, 9, 30),
    lat: 9.0301,
    lng: 38.7408,
    name: 'አበበ ከበደ',
    condition: 'Epilepsy',
    medications: 'Carbamazepine',
  );

  test('alert round-trips through the link fragment, including Ge’ez text', () {
    final decoded = decodeAlert('#${encodeAlert(alert)}')!;
    expect(decoded.name, 'አበበ ከበደ');
    expect(decoded.lat, 9.0301);
    expect(decoded.trigger, 'voice');
    expect(decoded.time.millisecondsSinceEpoch, alert.time.millisecondsSinceEpoch);
  });

  test('the fragment is URL-safe and uses the web dashboard field names', () {
    final encoded = encodeAlert(alert);
    expect(encoded, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(encoded)))) as Map;
    expect(json['s'], 'active');
    expect(json['la'], 9.0301);
    expect(json['t'], alert.time.millisecondsSinceEpoch);
  });

  test('decodes a link produced by the web prototype', () {
    // encodeAlert() output from prototype/js/core/alertLink.js for the same alert.
    const fromJs =
        'eyJzIjoiYWN0aXZlIiwiZyI6InZvaWNlIiwidCI6MTc5MDMyODYwMDAwMCwibGEiOjkuMDMwMSwibG4iOjM4Ljc0MDgsIm4iOiLhiqDhiaDhiaAg4Yqo4Ymg4YuwIiwiYyI6IkVwaWxlcHN5IiwibSI6IkNhcmJhbWF6ZXBpbmUiLCJhIjoiIn0';
    final decoded = decodeAlert(fromJs)!;
    expect(decoded.name, 'አበበ ከበደ');
    expect(decoded.lng, 38.7408);
  });

  test('a malformed fragment decodes to null', () {
    expect(decodeAlert('#not-valid'), isNull);
  });

  test('SMS body follows the spec format and handles a missing GPS fix', () {
    expect(
      smsBody(alert, 'https://example.test/d'),
      startsWith('[EMERGENCY] አበበ ከበደ may be having a seizure/fall event. Location: https://www.openstreetmap.org/'),
    );
    final noFix = AlertDetails(status: AlertStatus.active, trigger: 'fall', time: alert.time);
    expect(smsBody(noFix, 'x'), contains('Location: unknown (no GPS fix)'));
    expect(smsBody(alert.resolved(), 'x'), contains('has marked themselves as okay'));
  });
}
