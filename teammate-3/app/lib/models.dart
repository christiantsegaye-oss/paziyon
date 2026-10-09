import 'core/content.dart';
import 'core/fall_detector.dart';

// Local data models (spec section 7.1). Everything is stored on the device,
// as one JSON document under [storeKey] (shared with the background service).

const storeKey = 'sfa-v1';

class UserProfile {
  UserProfile({
    this.name = '',
    this.condition = 'Epilepsy',
    this.seizureType = 'Tonic-clonic',
    this.medications = '',
    this.allergies = '',
    this.bloodType = '',
  });

  String name, condition, seizureType, medications, allergies, bloodType;

  static const conditions = ['Epilepsy', 'Stroke risk', 'Other'];
  static const seizureTypes = ['Tonic-clonic', 'Absence', 'Focal', 'Unknown / unsure'];

  factory UserProfile.demo(Lang lang) => UserProfile(
        name: const {Lang.en: 'Abebe Kebede', Lang.am: 'አበበ ከበደ', Lang.om: 'Caalaa Guddataa'}[lang]!,
        medications: 'Carbamazepine 200 mg',
        allergies: 'Penicillin',
        bloodType: 'O+',
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'condition': condition,
        'seizureType': seizureType,
        'medications': medications,
        'allergies': allergies,
        'bloodType': bloodType,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        name: j['name'] as String? ?? '',
        condition: j['condition'] as String? ?? 'Epilepsy',
        seizureType: j['seizureType'] as String? ?? 'Tonic-clonic',
        medications: j['medications'] as String? ?? '',
        allergies: j['allergies'] as String? ?? '',
        bloodType: j['bloodType'] as String? ?? '',
      );
}

class EmergencyContact {
  EmergencyContact({required this.name, required this.phone, this.relationship = ''});

  final String name, phone, relationship;

  Map<String, Object?> toJson() => {'name': name, 'phone': phone, 'relationship': relationship};

  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        relationship: j['relationship'] as String? ?? '',
      );
}

class AppSettings {
  AppSettings({
    this.language = Lang.en,
    List<Lang>? languageOrder,
    this.cancelWindowSeconds = 15,
    this.fallDetection = true,
    this.sensitivity = Sensitivity.medium,
    this.voiceTrigger = true,
    this.backgroundProtection = true,
    this.voxideKey = '',
    this.voxideAlwaysListen = true,
    this.siren = true,
  }) : languageOrder = languageOrder ?? [Lang.am, Lang.om, Lang.en];

  Lang language;
  List<Lang> languageOrder;
  int cancelWindowSeconds;
  bool fallDetection;
  Sensitivity sensitivity;
  bool voiceTrigger;

  /// Fall detection keeps running with the app closed (foreground service).
  bool backgroundProtection;

  /// Voxide publishable key ("vox_pub_…") from the Voxide dashboard.
  String voxideKey;

  /// Listen through Voxide while idle too (understands Amharic and Afaan
  /// Oromo, uses Voxide sessions). Off: the phone's own recognizer listens
  /// for "help", and Voxide starts when an alert does.
  bool voxideAlwaysListen;

  /// Loud siren when an alert goes out.
  bool siren;

  Map<String, Object?> toJson() => {
        'language': language.name,
        'languageOrder': languageOrder.map((l) => l.name).toList(),
        'cancelWindowSeconds': cancelWindowSeconds,
        'fallDetection': fallDetection,
        'sensitivity': sensitivity.name,
        'voiceTrigger': voiceTrigger,
        'backgroundProtection': backgroundProtection,
        'voxideKey': voxideKey,
        'voxideAlwaysListen': voxideAlwaysListen,
        'siren': siren,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        language: Lang.values.asNameMap()[j['language']] ?? Lang.en,
        languageOrder: (j['languageOrder'] as List?)
            ?.map((n) => Lang.values.asNameMap()[n])
            .whereType<Lang>()
            .toList(),
        cancelWindowSeconds: (j['cancelWindowSeconds'] as num?)?.toInt() ?? 15,
        fallDetection: j['fallDetection'] as bool? ?? true,
        sensitivity: Sensitivity.values.asNameMap()[j['sensitivity']] ?? Sensitivity.medium,
        voiceTrigger: j['voiceTrigger'] as bool? ?? true,
        backgroundProtection: j['backgroundProtection'] as bool? ?? true,
        voxideKey: j['voxideKey'] as String? ?? '',
        voxideAlwaysListen: j['voxideAlwaysListen'] as bool? ?? true,
        siren: j['siren'] as bool? ?? true,
      );
}

/// Every trigger, including cancelled ones.
class EventLog {
  EventLog({
    required this.id,
    required this.time,
    required this.trigger,
    this.outcome = 'countdown',
    this.durationSeconds = 0,
    this.lat,
    this.lng,
    this.contactsNotified = 0,
  });

  final String id;
  final DateTime time;

  /// 'voice' | 'manual' | 'fall'
  final String trigger;

  /// 'countdown' | 'active' | 'cancelled' | 'resolved'
  String outcome;
  int durationSeconds;
  double? lat, lng;
  int contactsNotified;

  Map<String, Object?> toJson() => {
        'id': id,
        'time': time.millisecondsSinceEpoch,
        'trigger': trigger,
        'outcome': outcome,
        'durationSeconds': durationSeconds,
        'lat': lat,
        'lng': lng,
        'contactsNotified': contactsNotified,
      };

  factory EventLog.fromJson(Map<String, dynamic> j) => EventLog(
        id: j['id'] as String,
        time: DateTime.fromMillisecondsSinceEpoch((j['time'] as num).toInt()),
        trigger: j['trigger'] as String? ?? 'manual',
        outcome: j['outcome'] as String? ?? 'countdown',
        durationSeconds: (j['durationSeconds'] as num?)?.toInt() ?? 0,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        contactsNotified: (j['contactsNotified'] as num?)?.toInt() ?? 0,
      );

  static const csvHeader = 'time,trigger,outcome,durationSeconds,lat,lng,contactsNotified';
  String toCsvRow() =>
      [time.toUtc().toIso8601String(), trigger, outcome, durationSeconds, lat ?? '', lng ?? '', contactsNotified].join(',');
}
