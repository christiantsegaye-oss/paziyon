import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../core/fall_detector.dart';
import '../models.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.c});
  final AppController c;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _tab, children: [
          HomeTab(c: c, openTab: (i) => setState(() => _tab = i)),
          HistoryTab(c: c),
          MedicalTab(c: c),
          SettingsTab(c: c),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
          NavigationDestination(
              icon: Icon(Icons.medical_information_outlined),
              selectedIcon: Icon(Icons.medical_information_rounded),
              label: 'Medical ID'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, this.subtitle, this.leading, this.trailing, required this.children});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xxxl),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (leading != null) ...[leading!, const SizedBox(width: Space.md)],
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(title, style: TypeScale.display.copyWith(color: t.text)),
            ),
          ),
          const SizedBox(width: Space.sm),
          ?trailing,
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: Space.xs),
          Text(subtitle!, style: TypeScale.body.copyWith(color: t.textMuted)),
        ],
        ...children,
      ],
    );
  }
}

// ---------------------------------------------------------------- home

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.c, required this.openTab});
  final AppController c;
  final ValueChanged<int> openTab;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _type = TextEditingController();

  @override
  void dispose() {
    _type.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _type.text.trim();
    if (text.isNotEmpty) widget.c.handleTranscript(text);
    _type.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = context.t;
    final s = c.settings;
    final protected = s.fallDetection || c.listening;
    final last = c.events.isEmpty ? null : c.events.first;
    const stage = {
      FallStage.monitor: 'Watching for falls',
      FallStage.freefall: 'Freefall detected…',
      FallStage.impact: 'Impact. Checking stillness…',
    };

    return _Page(
      title: appName,
      leading: const AppLogo(size: 40),
      trailing: StatusPill(
        label: protected ? 'Protected' : 'Paused',
        color: protected ? t.ok : t.warn,
        live: protected,
      ),
      children: [
        const SizedBox(height: Space.xl),
        Center(child: HelpButton(onTriggered: c.triggerManual)),
        const SizedBox(height: Space.md),
        Text('Or just say “Help” · “እርዳታ” · “Gargaari”',
            textAlign: TextAlign.center, style: TypeScale.body.copyWith(color: t.textMuted)),
        Group(title: 'Voice', children: [
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              VoiceStrip(c: c, prompt: 'Say “Help” to start the countdown hands-free.'),
              const SizedBox(height: Space.lg),
              Row(children: [
                Expanded(
                  child: c.listening
                      ? OutlinedButton.icon(
                          onPressed: c.stopListening,
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text('Stop'),
                        )
                      : FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: t.text, foregroundColor: t.bg),
                          onPressed: c.startListening,
                          icon: const Icon(Icons.mic_rounded),
                          label: const Text('Start listening'),
                        ),
                ),
                const SizedBox(width: Space.md),
                LangSwitch(value: c.listenLang, onChanged: c.setListenLang),
              ]),
              const SizedBox(height: Space.md),
              TextField(
                key: const Key('typeField'),
                controller: _type,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Or type what you would say',
                  suffixIcon: IconButton(
                    tooltip: 'Send',
                    icon: const Icon(Icons.arrow_upward_rounded),
                    onPressed: _submit,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ]),
          ),
        ]),
        Group(title: 'Protection', children: [
          Row2(
            icon: Icons.sensors_rounded,
            title: 'Fall detection',
            subtitle: s.fallDetection
                ? (c.motionAvailable ? stage[c.fallStage] : 'No motion sensor found')
                : 'Off',
            trailing: TextButton(
              onPressed: c.simulatingFall || !s.fallDetection ? null : c.simulateFall,
              child: Text(c.simulatingFall ? 'Simulating…' : 'Simulate a fall'),
            ),
          ),
          if (s.fallDetection && s.backgroundProtection)
            const Row2(
              icon: Icons.power_settings_new_rounded,
              title: 'Phone locked? Press power 3 times',
              subtitle: 'Or tap Get help now on the lock-screen notification',
            ),
          Row2(
            icon: Icons.people_alt_rounded,
            title: '${c.contacts.length} emergency contact${c.contacts.length == 1 ? '' : 's'}',
            subtitle: c.contacts.isEmpty ? 'Add someone who should get the SMS' : c.contacts.map((x) => x.name).join(', '),
            trailing: Icon(Icons.chevron_right_rounded, color: t.textMuted),
            onTap: () => widget.openTab(3),
          ),
          Row2(
            icon: Icons.history_rounded,
            title: last == null ? 'No events yet' : 'Last event ${timeAgo(last.time, DateTime.now())}',
            trailing: Icon(Icons.chevron_right_rounded, color: t.textMuted),
            onTap: () => widget.openTab(1),
          ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------- history

class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key, required this.c});
  final AppController c;

  static const _outcomes = {
    'cancelled': 'Cancelled',
    'resolved': 'Alert sent, resolved',
    'active': 'Alert sent',
    'countdown': 'Countdown',
  };
  static const _triggers = {'voice': 'Voice', 'manual': 'Button', 'fall': 'Fall detected'};
  static const _icons = {'voice': Icons.mic_rounded, 'manual': Icons.front_hand_rounded, 'fall': Icons.sensors_rounded};

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return _Page(
      title: 'History',
      subtitle: 'Every alert, including cancelled ones. Useful for your doctor.',
      trailing: c.events.isEmpty
          ? null
          : IconButton(
              tooltip: 'Copy as CSV',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: c.eventsCsv()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History copied as CSV')));
                }
              },
            ),
      children: [
        if (c.events.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xxxl),
            child: Column(children: [
              Icon(Icons.event_available_rounded, size: 56, color: t.textMuted),
              const SizedBox(height: Space.md),
              Text('No events yet', style: TypeScale.heading.copyWith(color: t.text)),
              const SizedBox(height: Space.xs),
              Text('Alerts and cancelled countdowns will appear here.',
                  textAlign: TextAlign.center, style: TypeScale.body.copyWith(color: t.textMuted)),
            ]),
          )
        else
          Group(children: [
            for (final e in c.events)
              Row2(
                icon: _icons[e.trigger] ?? Icons.warning_rounded,
                title: _outcomes[e.outcome] ?? e.outcome,
                subtitle: [
                  '${MaterialLocalizations.of(context).formatShortDate(e.time)} '
                      '${TimeOfDay.fromDateTime(e.time).format(context)}',
                  _triggers[e.trigger] ?? e.trigger,
                  if (e.durationSeconds > 0) formatDuration(e.durationSeconds),
                  '${e.contactsNotified} contact${e.contactsNotified == 1 ? '' : 's'}',
                ].join(' · '),
                trailing: e.outcome == 'cancelled'
                    ? null
                    : Container(width: 10, height: 10, decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle)),
              ),
          ]),
      ],
    );
  }
}

// ---------------------------------------------------------------- medical ID

class MedicalTab extends StatelessWidget {
  const MedicalTab({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final p = c.profile;
    Widget field(String label, String value, void Function(String) set, {String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: TextFormField(
            // Rebuild when the profile is replaced (e.g. demo profile).
            key: ValueKey('$label:${identityHashCode(p)}'),
            initialValue: value,
            decoration: InputDecoration(labelText: label, hintText: hint),
            onChanged: (v) => c.updateProfile((p) => set(v.trim())),
          ),
        );
    Widget choice(String label, String value, List<String> options, void Function(String) set) => Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: DropdownButtonFormField<String>(
            key: ValueKey('$label:${identityHashCode(p)}'),
            initialValue: options.contains(value) ? value : options.first,
            decoration: InputDecoration(labelText: label),
            items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
            onChanged: (v) => c.updateProfile((p) => set(v!)),
          ),
        );

    return _Page(
      title: 'Medical ID',
      subtitle: 'Stays on this phone. Shown to bystanders and sent to contacts only during an alert.',
      children: [
        const SizedBox(height: Space.xl),
        field('Name', p.name, (v) => p.name = v),
        choice('Condition', p.condition, UserProfile.conditions, (v) => p.condition = v),
        choice('Seizure type', p.seizureType, UserProfile.seizureTypes, (v) => p.seizureType = v),
        field('Medications', p.medications, (v) => p.medications = v, hint: 'e.g. Carbamazepine 200 mg'),
        field('Allergies', p.allergies, (v) => p.allergies = v),
        field('Blood type', p.bloodType, (v) => p.bloodType = v, hint: 'Optional'),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.lg, Space.xs, Space.sm),
          child: Text('WHAT A BYSTANDER SEES',
              style: TypeScale.caption.copyWith(color: context.t.textMuted, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
        ),
        MedicalCard(profile: p, contacts: c.contacts),
      ],
    );
  }
}

// ---------------------------------------------------------------- settings

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.c});
  final AppController c;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _relationship = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relationship.dispose();
    super.dispose();
  }

  void _addContact() {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _error = 'Name and phone are both needed.');
      return;
    }
    widget.c.addContact(EmergencyContact(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      relationship: _relationship.text.trim(),
    ));
    _name.clear();
    _phone.clear();
    _relationship.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final s = c.settings;
    final t = context.t;
    return _Page(
      title: 'Settings',
      children: [
        Group(title: 'Emergency contacts · ${c.contacts.length}/5', children: [
          for (final (i, contact) in c.contacts.indexed)
            Row2(
              icon: Icons.person_rounded,
              title: contact.name,
              subtitle: [contact.phone, if (contact.relationship.isNotEmpty) contact.relationship].join(' · '),
              trailing: IconButton(
                tooltip: 'Remove ${contact.name}',
                icon: Icon(Icons.close_rounded, color: t.textMuted),
                onPressed: () => c.removeContact(i),
              ),
            ),
          if (c.contacts.length < 5)
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('They get an SMS with your location during an alert. Tell them in advance.',
                    style: TypeScale.caption.copyWith(color: t.textMuted)),
                const SizedBox(height: Space.md),
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: Space.sm),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone', hintText: '+251 9…'),
                ),
                const SizedBox(height: Space.sm),
                TextField(
                  controller: _relationship,
                  decoration: const InputDecoration(labelText: 'Relationship', hintText: 'Optional'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(_error!, style: TypeScale.caption.copyWith(color: t.accent)),
                ],
                const SizedBox(height: Space.md),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: t.text, foregroundColor: t.bg),
                  onPressed: _addContact,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add contact'),
                ),
              ]),
            ),
        ]),
        Group(title: 'Alert', children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
            child: Row(children: [
              Expanded(child: Text('Cancel window', style: TypeScale.label.copyWith(color: t.text))),
              Text('${s.cancelWindowSeconds} s', style: TypeScale.label.copyWith(color: t.text)),
            ]),
          ),
          Slider(
            value: s.cancelWindowSeconds.toDouble(),
            min: 10,
            max: 30,
            divisions: 20,
            label: '${s.cancelWindowSeconds} s',
            onChanged: (v) => c.updateSettings((s) => s.cancelWindowSeconds = v.round()),
          ),
          _SwitchRow(
            icon: Icons.campaign_rounded,
            title: 'Siren',
            subtitle: 'A loud siren at full volume draws people over when an alert goes out',
            value: s.siren,
            onChanged: (v) => c.updateSettings((s) => s.siren = v),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Spoken prompts language', style: TypeScale.label.copyWith(color: t.text)),
              const SizedBox(height: Space.sm),
              LangSwitch(value: s.language, onChanged: (l) => c.updateSettings((s) => s.language = l)),
            ]),
          ),
        ]),
        Group(title: 'Voxide voice', children: [
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'Voxide listens and speaks Amharic, Afaan Oromo and English naturally. '
                'Paste the publishable key from your Voxide dashboard.',
                style: TypeScale.caption.copyWith(color: t.textMuted),
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                key: const Key('voxideKey'),
                initialValue: s.voxideKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Voxide key',
                  hintText: 'vox_pub_…',
                  errorText: s.voxideKey.isNotEmpty && !s.voxideKey.trim().startsWith('vox_pub_')
                      ? 'Publishable keys start with vox_pub_'
                      : null,
                ),
                onChanged: (v) => c.updateSettings((s) => s.voxideKey = v.trim()),
              ),
              const SizedBox(height: Space.sm),
              Text(
                !c.voxideConfigured
                    ? 'Not set up: using the phone\'s own voice and the bundled clips.'
                    : c.agentLive
                        ? 'Connected to Voxide.'
                        : c.usingVoxide
                            ? (c.agentError ?? 'Connecting…')
                            : 'Ready. Voxide starts when an alert does.',
                style: TypeScale.caption.copyWith(color: c.agentError != null ? t.warn : t.textMuted),
              ),
            ]),
          ),
          _SwitchRow(
            icon: Icons.hearing_rounded,
            title: 'Listen with Voxide all the time',
            subtitle: 'Hears “help” in Amharic and Oromo too. Uses Voxide sessions while idle.',
            value: s.voxideAlwaysListen,
            onChanged: c.voxideConfigured ? (v) => c.updateSettings((s) => s.voxideAlwaysListen = v) : null,
          ),
        ]),
        Group(title: 'Triggers', children: [
          _SwitchRow(
            icon: Icons.mic_rounded,
            title: 'Voice trigger',
            subtitle: 'Say “Help” to start the countdown',
            value: s.voiceTrigger,
            onChanged: (v) => c.updateSettings((s) => s.voiceTrigger = v),
          ),
          _SwitchRow(
            icon: Icons.sensors_rounded,
            title: 'Fall detection',
            subtitle: 'Freefall, impact, then stillness',
            value: s.fallDetection,
            onChanged: (v) => c.updateSettings((s) => s.fallDetection = v),
          ),
          _SwitchRow(
            icon: Icons.lock_clock_rounded,
            title: 'Keep protecting when closed',
            subtitle: 'Falls are detected with the app closed. Voice needs the app open.',
            value: s.backgroundProtection,
            onChanged: s.fallDetection ? (v) => c.updateSettings((s) => s.backgroundProtection = v) : null,
          ),
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: DropdownButtonFormField<Sensitivity>(
              initialValue: s.sensitivity,
              decoration: const InputDecoration(labelText: 'Fall sensitivity'),
              items: const [
                DropdownMenuItem(value: Sensitivity.low, child: Text('Low: fewer false alarms')),
                DropdownMenuItem(value: Sensitivity.medium, child: Text('Medium')),
                DropdownMenuItem(value: Sensitivity.high, child: Text('High: catches more falls')),
              ],
              onChanged: (v) => c.updateSettings((s) => s.sensitivity = v!),
            ),
          ),
        ]),
        Group(title: 'Data', children: [
          Row2(
            icon: Icons.person_search_rounded,
            title: 'Load demo profile',
            onTap: () => c.loadDemoProfile(s.language),
          ),
          Row2(
            icon: Icons.delete_outline_rounded,
            title: 'Delete all data',
            subtitle: 'Profile, contacts, settings and history',
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete all data?'),
                  content: const Text('Profile, contacts, settings and history are removed from this phone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) await c.deleteAll();
            },
          ),
        ]),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.title, required this.subtitle, required this.value, this.onChanged});
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Row2(
          icon: icon,
          title: title,
          subtitle: subtitle,
          onTap: onChanged == null ? null : () => onChanged!(!value),
          trailing: Switch(value: value, onChanged: onChanged),
        ),
      );
}
