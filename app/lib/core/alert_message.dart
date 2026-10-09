import 'dart:convert';

// The alert SMS and the caregiver dashboard link. The link format matches
// prototype/js/core/alertLink.js, so links sent by the app open the web
// dashboard (prototype/dashboard.html). With no backend yet, the alert details
// travel in the link's #fragment, which browsers never send to a server.

/// Where the caregiver dashboard (prototype/dashboard.html) is hosted, e.g.
/// `flutter build apk --dart-define=DASHBOARD_URL=https://…/dashboard.html`.
/// Empty leaves the link out of the SMS.
const dashboardBase = String.fromEnvironment('DASHBOARD_URL');

enum AlertStatus { active, resolved }

class AlertDetails {
  const AlertDetails({
    required this.status,
    required this.trigger,
    required this.time,
    this.lat,
    this.lng,
    this.name = '',
    this.condition = '',
    this.seizureType = '',
    this.medications = '',
    this.allergies = '',
    this.bloodType = '',
  });

  final AlertStatus status;

  /// 'voice' | 'manual' | 'fall'
  final String trigger;
  final DateTime time;
  final double? lat, lng;
  final String name, condition, seizureType, medications, allergies, bloodType;

  AlertDetails resolved() => AlertDetails(
        status: AlertStatus.resolved,
        trigger: trigger,
        time: time,
        lat: lat,
        lng: lng,
        name: name,
        condition: condition,
        seizureType: seizureType,
        medications: medications,
        allergies: allergies,
        bloodType: bloodType,
      );
}

String encodeAlert(AlertDetails a) {
  final compact = <String, Object?>{
    's': a.status.name,
    'g': a.trigger,
    't': a.time.millisecondsSinceEpoch,
    'la': a.lat,
    'ln': a.lng,
    'n': a.name,
    'c': a.condition,
    'st': a.seizureType,
    'm': a.medications,
    'a': a.allergies,
    'b': a.bloodType,
  }..removeWhere((_, v) => v == null);
  return base64Url.encode(utf8.encode(jsonEncode(compact))).replaceAll('=', '');
}

AlertDetails? decodeAlert(String fragment) {
  try {
    var b64 = fragment.startsWith('#') ? fragment.substring(1) : fragment;
    b64 = b64.padRight((b64.length + 3) ~/ 4 * 4, '=');
    final c = jsonDecode(utf8.decode(base64Url.decode(b64))) as Map<String, dynamic>;
    return AlertDetails(
      status: c['s'] == 'resolved' ? AlertStatus.resolved : AlertStatus.active,
      trigger: c['g'] as String? ?? 'manual',
      time: DateTime.fromMillisecondsSinceEpoch((c['t'] as num).toInt()),
      lat: (c['la'] as num?)?.toDouble(),
      lng: (c['ln'] as num?)?.toDouble(),
      name: c['n'] as String? ?? '',
      condition: c['c'] as String? ?? '',
      seizureType: c['st'] as String? ?? '',
      medications: c['m'] as String? ?? '',
      allergies: c['a'] as String? ?? '',
      bloodType: c['b'] as String? ?? '',
    );
  } catch (_) {
    return null;
  }
}

String? mapLink(double? lat, double? lng) => lat == null || lng == null
    ? null
    : 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng';

String dashboardUrl(String dashboardBase, AlertDetails a) => '$dashboardBase#${encodeAlert(a)}';

String _two(int n) => n.toString().padLeft(2, '0');
String _formatTime(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

/// Message formats from spec section 4.3 (Screen C) and 6.2 step 4.
/// [dashboardLink] may be empty when no dashboard is deployed.
String smsBody(AlertDetails a, String dashboardLink, {String appName = 'P.A.Z.I.Y.O.N'}) {
  final name = a.name.isEmpty ? 'Your contact' : a.name;
  if (a.status == AlertStatus.resolved) {
    return '$name has marked themselves as okay. Alert resolved.${dashboardLink.isEmpty ? '' : ' $dashboardLink'}';
  }
  final where = mapLink(a.lat, a.lng) ?? 'unknown (no GPS fix)';
  final details = dashboardLink.isEmpty ? '' : 'Details: $dashboardLink ';
  return '[EMERGENCY] $name may be having a seizure/fall event. Location: $where. '
      'Time: ${_formatTime(a.time)}. $details'
      'This is an automated alert from $appName. Please check on them or call emergency services.';
}
