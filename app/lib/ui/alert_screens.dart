import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/alert_state_machine.dart';
import '../core/content.dart';
import 'theme.dart';
import 'widgets.dart';

const _sources = {
  TriggerSource.voice: (Icons.mic_rounded, 'Voice trigger'),
  TriggerSource.manual: (Icons.front_hand_rounded, 'Button pressed'),
  TriggerSource.fall: (Icons.sensors_rounded, 'Fall detected'),
};

const _onDark = TextStyle(color: AppTokens.emergencyText);

/// Screen A: the cancel window (spec 4.3). Full-screen, gets redder as time
/// runs out; cancel by voice or the big green button.
class CountdownScreen extends StatelessWidget {
  const CountdownScreen({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final n = c.alert.remaining;
    final total = c.settings.cancelWindowSeconds;
    final heat = (1 - n / total).clamp(0.0, 1.0);
    final (icon, label) = _sources[c.alert.source] ?? (Icons.warning_rounded, 'Alert');
    final lang = c.settings.language;
    return Scaffold(
      backgroundColor: Color.lerp(const Color(0xFF7C2D12), Palette.red700, heat),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(children: [
            Row(children: [
              Icon(icon, color: AppTokens.emergencyText),
              const SizedBox(width: Space.sm),
              Text(label, style: TypeScale.label.merge(_onDark)),
            ]),
            const Spacer(),
            Semantics(
              liveRegion: true,
              label: 'Alert sends in $n seconds',
              excludeSemantics: true,
              child: SizedBox.square(
                dimension: 240,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: n / total,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      color: AppTokens.emergencyText,
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  Text('$n', style: TypeScale.countdown.merge(_onDark)),
                ]),
              ),
            ),
            const SizedBox(height: Space.xl),
            Text(countdownPrompt(lang, n), textAlign: TextAlign.center, style: TypeScale.heading.merge(_onDark)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: VoiceStrip(c: c, onDark: true, prompt: 'Say “I’m okay” · “ደህና ነኝ” · “Nagaan jira” to cancel.'),
            ),
            const SizedBox(height: Space.lg),
            SizedBox(
              width: double.infinity,
              height: Sizes.emergency + 8,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: t.ok,
                  foregroundColor: t.onOk,
                  textStyle: TypeScale.title,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
                ),
                onPressed: c.cancelAlert,
                icon: const Icon(Icons.check_circle_rounded, size: 32),
                label: const Text('I’m okay, cancel'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Screen B: what a bystander sees and hears (spec 4.3).
class BystanderScreen extends StatefulWidget {
  const BystanderScreen({super.key, required this.c});
  final AppController c;

  @override
  State<BystanderScreen> createState() => _BystanderScreenState();
}

class _BystanderScreenState extends State<BystanderScreen> {
  final _ask = TextEditingController();

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ask.text.trim();
    if (text.isNotEmpty) widget.c.handleTranscript(text);
    _ask.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = context.t;
    final secs = c.alert.elapsed;
    final steps = firstAidSteps[c.stepLang]!;
    final late = secs >= 300;

    return Theme(
      data: buildTheme(Brightness.dark),
      child: Builder(builder: (context) {
        return Scaffold(
          backgroundColor: AppTokens.emergencyBg,
          body: SafeArea(
            child: Column(children: [
              Container(
                width: double.infinity,
                color: Palette.red600,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                child: Column(children: [
                  for (final l in Lang.values)
                    Text(emergencyHeader[l]!,
                        textAlign: TextAlign.center, style: TypeScale.heading.copyWith(color: Colors.white)),
                ]),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xxl),
                  children: [
                    Row(children: [
                      Icon(Icons.timer_outlined, color: late ? Palette.red400 : AppTokens.emergencyMuted),
                      const SizedBox(width: Space.sm),
                      Text(
                        '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
                        semanticsLabel: '${secs ~/ 60} minutes ${secs % 60} seconds since the alert',
                        style: TypeScale.title.copyWith(
                          color: late ? Palette.red400 : AppTokens.emergencyText,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      LangSwitch(value: c.stepLang, onChanged: c.setBystanderLang, onDark: true),
                    ]),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: AppTokens.emergencyMuted),
                        onPressed: c.cycleLanguages ? null : () => c.setBystanderLang(null),
                        icon: Icon(c.cycleLanguages ? Icons.autorenew_rounded : Icons.repeat_rounded, size: 20),
                        label: Text(c.cycleLanguages ? 'Cycling all languages' : 'Cycle all languages'),
                      ),
                    ),
                    Text('Step ${c.step + 1} of ${steps.length}',
                        style: TypeScale.caption.copyWith(color: AppTokens.emergencyMuted)),
                    const SizedBox(height: Space.sm),
                    Semantics(
                      liveRegion: true,
                      child: Text(steps[c.step], style: TypeScale.emergencyStep.merge(_onDark)),
                    ),
                    const SizedBox(height: Space.md),
                    Row(children: [
                      for (var i = 0; i < steps.length; i++)
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            height: 6,
                            margin: EdgeInsets.only(right: i == steps.length - 1 ? 0 : 6),
                            decoration: BoxDecoration(
                              color: i <= c.step ? AppTokens.emergencyText : AppTokens.emergencyBorder,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: Space.xl),
                    SizedBox(
                      height: Sizes.emergency,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Palette.red600,
                          foregroundColor: Colors.white,
                          textStyle: TypeScale.heading,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
                        ),
                        onPressed: c.callEmergency,
                        icon: const Icon(Icons.call_rounded, size: 30),
                        label: const Text('Call emergency services · $emergencyNumber'),
                      ),
                    ),
                    if (c.settings.siren && !c.sirenMuted)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: AppTokens.emergencyMuted),
                          onPressed: c.muteSiren,
                          icon: const Icon(Icons.volume_off_rounded),
                          label: const Text('Silence siren'),
                        ),
                      ),
                    if (c.smsStatus != null) ...[
                      const SizedBox(height: Space.sm),
                      Row(children: [
                        const Icon(Icons.sms_rounded, color: AppTokens.emergencyMuted, size: 20),
                        const SizedBox(width: Space.sm),
                        Expanded(child: Text(c.smsStatus!, style: TypeScale.body.merge(_onDark))),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: AppTokens.emergencyText),
                          onPressed: c.sendAlertSms,
                          child: const Text('Resend'),
                        ),
                      ]),
                    ],
                    const SizedBox(height: Space.xl),
                    Container(
                      padding: const EdgeInsets.all(Space.lg),
                      decoration: BoxDecoration(
                        color: AppTokens.emergencySurface,
                        border: Border.all(color: AppTokens.emergencyBorder),
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Talk to this phone', style: TypeScale.heading.merge(_onDark)),
                        const SizedBox(height: Space.md),
                        VoiceStrip(
                          c: c,
                          onDark: true,
                          prompt: 'Ask “How long has it been?”, “What do I do now?”, “Next”, '
                              '“Any medication?” or “Call for help”.',
                        ),
                        const SizedBox(height: Space.md),
                        TextField(
                          key: const Key('askField'),
                          controller: _ask,
                          style: TypeScale.body.merge(_onDark),
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: 'Or type a question',
                            suffixIcon: IconButton(
                              tooltip: 'Ask',
                              icon: const Icon(Icons.arrow_upward_rounded),
                              onPressed: _submit,
                            ),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        for (final line in c.convo.take(6)) _Bubble(line: line),
                      ]),
                    ),
                    const SizedBox(height: Space.lg),
                    MedicalCard(profile: c.profile, contacts: c.contacts, onDark: true),
                    const SizedBox(height: Space.xl),
                    HoldButton(
                      duration: const Duration(seconds: 2),
                      onComplete: c.resolveAlert,
                      semanticLabel: 'Patient returned: hold to stop the alert',
                      builder: (context, p, pressed) => Container(
                        height: 64,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTokens.emergencyBorder),
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                        child: Stack(children: [
                          FractionallySizedBox(widthFactor: p, child: Container(color: t.ok)),
                          Center(
                            child: Text('Patient returned — hold to stop alert', style: TypeScale.label.merge(_onDark)),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    Text(
                      'Amharic and Afaan Oromo text is a draft pending review by native speakers and Care Epilepsy Ethiopia.',
                      textAlign: TextAlign.center,
                      style: TypeScale.caption.copyWith(color: AppTokens.emergencyMuted),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.line});
  final ConvoLine line;

  @override
  Widget build(BuildContext context) {
    final fromBystander = line.fromBystander;
    return Align(
      alignment: fromBystander ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: Space.sm),
        constraints: BoxConstraints(maxWidth: math.min(MediaQuery.sizeOf(context).width * 0.8, 520)),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm + 2),
        decoration: BoxDecoration(
          color: fromBystander ? AppTokens.emergencyText : Palette.zinc800,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Text(
          line.text,
          style: TypeScale.body.copyWith(color: fromBystander ? AppTokens.emergencyBg : AppTokens.emergencyText),
        ),
      ),
    );
  }
}

class ResolvedScreen extends StatelessWidget {
  const ResolvedScreen({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final a = c.alert;
    final cancelled = a.outcome == AlertOutcome.cancelled;
    final duration = a.activatedAt == null ? 0 : a.resolvedAt!.difference(a.activatedAt!).inSeconds;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: t.ok, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, size: 56, color: t.onOk),
            ),
            const SizedBox(height: Space.xl),
            Text(cancelled ? 'Alert cancelled' : 'Alert resolved',
                style: TypeScale.display.copyWith(color: t.text), textAlign: TextAlign.center),
            const SizedBox(height: Space.sm),
            Text(
              cancelled
                  ? 'Cancelled by ${a.resolvedBy == 'voice' ? 'voice' : 'tap'} before anything was sent.'
                  : 'Alert lasted ${formatDuration(duration)}.'
                      '${c.contacts.isEmpty ? '' : ' Your contacts have been told you are okay.'}',
              textAlign: TextAlign.center,
              style: TypeScale.body.copyWith(color: t.textMuted),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: t.text, foregroundColor: t.bg),
                onPressed: c.finishAlert,
                child: const Text('Done'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - Space.xl * 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: Space.xxl),
                const AppLogo(size: 96),
                const SizedBox(height: Space.xl),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(appName, style: TypeScale.display.copyWith(color: t.text, fontSize: 44)),
                ),
                const SizedBox(height: Space.sm),
                Text(appTagline, style: TypeScale.heading.copyWith(color: t.textMuted, fontWeight: FontWeight.w400)),
                const SizedBox(height: Space.xxxl),
                Text('Choose your language', style: TypeScale.label.copyWith(color: t.text)),
                const SizedBox(height: Space.md),
                for (final l in [Lang.am, Lang.en, Lang.om])
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          textStyle: TypeScale.heading,
                          backgroundColor: t.surface,
                        ),
                        onPressed: () => c.completeWelcome(l),
                        child: Row(children: [
                          Expanded(child: Text(l.label)),
                          Icon(Icons.arrow_forward_rounded, color: t.textMuted),
                        ]),
                      ),
                    ),
                  ),
                const SizedBox(height: Space.sm),
                Text('Sets the spoken language. You can change it later. A demo profile is filled in for you.',
                    style: TypeScale.caption.copyWith(color: t.textMuted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
