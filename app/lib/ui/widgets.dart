import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/content.dart';
import '../models.dart';
import '../services/services.dart';
import 'theme.dart';

/// A control that fires only after being held for [duration], showing
/// progress. Screen readers and switch access activate it with one tap.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.duration,
    required this.onComplete,
    required this.semanticLabel,
    required this.builder,
  });

  final Duration duration;
  final VoidCallback onComplete;
  final String semanticLabel;
  final Widget Function(BuildContext context, double progress, bool pressed) builder;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _anim.reset();
        widget.onComplete();
      }
    });
  bool _pressed = false;

  void _release() {
    // Completing usually swaps the screen, so the finger lifts after dispose.
    if (!mounted) return;
    _anim.reset();
    setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      onTap: widget.onComplete,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) {
          setState(() => _pressed = true);
          _anim.forward(from: 0);
        },
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) => widget.builder(context, _anim.value, _pressed),
        ),
      ),
    );
  }
}

/// The big round button on the home screen.
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.onTriggered});
  final VoidCallback onTriggered;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return HoldButton(
      duration: const Duration(milliseconds: 800),
      onComplete: onTriggered,
      semanticLabel: 'Hold to send an emergency alert',
      builder: (context, p, pressed) => AnimatedScale(
        scale: pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox.square(
          dimension: Sizes.helpButton + 24,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: p,
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                color: t.text,
                backgroundColor: t.border,
              ),
            ),
            Container(
              width: Sizes.helpButton,
              height: Sizes.helpButton,
              decoration: BoxDecoration(
                color: pressed ? t.accentPressed : t.accent,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.28), blurRadius: 32, offset: const Offset(0, 12))],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.front_hand_rounded, size: 60, color: t.onAccent),
                const SizedBox(height: Space.sm),
                Text('Hold for help', style: TypeScale.heading.copyWith(color: t.onAccent)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The P.A.Z.I.Y.O.N logo tile.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.225),
        child: Image.asset('assets/brand/logo.png', width: size, height: size, semanticLabel: '$appName logo'),
      );
}

/// A dot that breathes while something is live (listening, protected).
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, required this.color, this.live = true, this.size = 10});
  final Color color;
  final bool live;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(LiveDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.live && !reduce) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.live = false});
  final String label;
  final Color color;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
        decoration: BoxDecoration(
          color: context.t.surface,
          border: Border.all(color: context.t.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          LiveDot(color: color, live: live, size: 8),
          const SizedBox(width: Space.sm),
          Text(label, style: TypeScale.caption.copyWith(color: context.t.text)),
        ]),
      );
}

/// AM · OR · EN switch.
class LangSwitch extends StatelessWidget {
  const LangSwitch({super.key, required this.value, required this.onChanged, this.onDark = false});
  final Lang value;
  final ValueChanged<Lang> onChanged;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final fg = onDark ? AppTokens.emergencyText : t.text;
    final bg = onDark ? AppTokens.emergencySurface : t.surfaceMuted;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.sm)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final l in Lang.values)
          Semantics(
            selected: l == value,
            button: true,
            label: l.label,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onChanged(l),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                constraints: const BoxConstraints(minWidth: 52, minHeight: 44),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
                // Selected is inverted so it reads clearly in light and dark.
                decoration: BoxDecoration(
                  color: l == value ? fg : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.sm - 4),
                ),
                child: Text(l.short,
                    style: TypeScale.label.copyWith(color: l == value ? (onDark ? AppTokens.emergencyBg : t.bg) : fg)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Microphone state, what it is hearing live, and why it is not working if
/// it isn't. Used on every screen that listens.
class VoiceStrip extends StatelessWidget {
  const VoiceStrip({super.key, required this.c, required this.prompt, this.onDark = false});
  final AppController c;
  final String prompt;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final text = onDark ? AppTokens.emergencyText : t.text;
    final muted = onDark ? AppTokens.emergencyMuted : t.textMuted;
    final ok = onDark ? Palette.green400 : t.ok;
    final warn = onDark ? Palette.amber400 : t.warn;
    final (label, color, listening) = c.usingVoxide
        ? switch (c.agentStatus) {
            AgentStatus.listening => ('Voxide is listening', ok, true),
            AgentStatus.thinking || AgentStatus.executing => ('Voxide is thinking', ok, true),
            AgentStatus.speaking => ('Voxide is speaking', ok, true),
            AgentStatus.connecting || AgentStatus.off => ('Connecting to Voxide…', muted, false),
            AgentStatus.error => ('Voxide problem', warn, false),
          }
        : switch (c.voiceStatus) {
            VoiceStatus.listening => ('Listening', ok, true),
            VoiceStatus.off => ('Voice off', muted, false),
            VoiceStatus.denied => ('Microphone blocked', warn, false),
            VoiceStatus.unavailable => ('No speech recognizer', warn, false),
            VoiceStatus.error => ('Voice problem', warn, false),
          };
    final detail = c.usingVoxide ? c.agentError : c.voiceDetail;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(listening ? Icons.mic_rounded : Icons.mic_off_rounded, color: color, size: 22),
        const SizedBox(width: Space.sm),
        Flexible(child: Text(label, style: TypeScale.label.copyWith(color: text))),
        if (listening) ...[const SizedBox(width: Space.sm), LiveDot(color: ok, size: 8)],
      ]),
      const SizedBox(height: Space.xs),
      Text(prompt, style: TypeScale.body.copyWith(color: muted)),
      if (c.hearing != null) ...[
        const SizedBox(height: Space.sm),
        Semantics(
          liveRegion: true,
          child: Text('“${c.hearing}”',
              key: const Key('hearing'), style: TypeScale.heading.copyWith(color: text, fontStyle: FontStyle.italic)),
        ),
      ],
      if (detail != null) ...[
        const SizedBox(height: Space.sm),
        Notice(text: detail, onDark: onDark),
      ],
    ]);
  }
}

class Notice extends StatelessWidget {
  const Notice({super.key, required this.text, this.onDark = false});
  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: onDark ? const Color(0xFF2A1F0A) : t.warnSurface,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 20, color: onDark ? Palette.amber400 : t.onWarnSurface),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(text, style: TypeScale.caption.copyWith(color: onDark ? Palette.amber400 : t.onWarnSurface)),
        ),
      ]),
    );
  }
}

/// A grouped surface with rows separated by hairlines, instead of a stack of
/// separate cards.
class Group extends StatelessWidget {
  const Group({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.sm),
          child: Text(title!.toUpperCase(),
              style: TypeScale.caption.copyWith(color: t.textMuted, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
        ),
      Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: t.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: Space.lg, endIndent: Space.lg),
            children[i],
          ],
        ]),
      ),
    ]);
  }
}

class Row2 extends StatelessWidget {
  const Row2({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          child: Row(children: [
            Icon(icon, color: t.textMuted, size: 24),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TypeScale.label.copyWith(color: t.text)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TypeScale.caption.copyWith(color: t.textMuted)),
                ],
              ]),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Space.md),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 168), child: trailing!),
            ],
          ]),
        ),
      ),
    );
  }
}

class MedicalCard extends StatelessWidget {
  const MedicalCard({super.key, required this.profile, required this.contacts, this.onDark = false});

  final UserProfile profile;
  final List<EmergencyContact> contacts;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final rows = [
      ('Name', profile.name),
      ('Condition', profile.condition),
      ('Seizure type', profile.seizureType),
      ('Medications', profile.medications),
      ('Allergies', profile.allergies),
      ('Blood type', profile.bloodType),
      for (final c in contacts)
        ('Contact', '${c.name}${c.relationship.isEmpty ? '' : ' (${c.relationship})'} · ${c.phone}'),
    ].where((r) => r.$2.isNotEmpty);
    final muted = onDark ? AppTokens.emergencyMuted : t.textMuted;
    final text = onDark ? AppTokens.emergencyText : t.text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: onDark ? AppTokens.emergencySurface : t.surface,
        border: Border.all(color: onDark ? Palette.red500 : t.accent, width: 2),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.medical_information_rounded, color: onDark ? Palette.red400 : t.accent, size: 22),
          const SizedBox(width: Space.sm),
          Text('MEDICAL ID',
              style: TypeScale.caption.copyWith(
                  color: onDark ? Palette.red400 : t.accent, fontWeight: FontWeight.w700, letterSpacing: 1)),
        ]),
        const SizedBox(height: Space.md),
        if (rows.isEmpty) Text('No medical details yet', style: TypeScale.body.copyWith(color: muted)),
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 118, child: Text(k, style: TypeScale.body.copyWith(color: muted))),
              Expanded(child: Text(v, style: TypeScale.label.copyWith(color: text))),
            ]),
          ),
      ]),
    );
  }
}

String formatDuration(int s) => s < 60 ? '${s}s' : '${s ~/ 60}m ${s % 60}s';

String timeAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} days ago';
}
