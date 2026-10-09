// Alert lifecycle: idle → countdown → active → resolved.
// Time only moves forward through tick(), so the UI drives it with a timer
// and tests drive it with a fake clock. Port of prototype/js/core/alertStateMachine.js.

enum AlertState { idle, countdown, active, resolved }

enum TriggerSource { voice, manual, fall }

enum AlertOutcome { cancelled, resolved }

enum AlertEvent { triggered, countdown, activated, tick, cancelled, resolved, reset }

class AlertSnapshot {
  const AlertSnapshot({
    required this.state,
    required this.event,
    this.source,
    this.triggeredAt,
    this.activatedAt,
    this.resolvedAt,
    this.outcome,
    this.resolvedBy,
    this.remaining = 0,
    this.elapsed = 0,
  });

  final AlertState state;
  final AlertEvent event;
  final TriggerSource? source;
  final DateTime? triggeredAt;
  final DateTime? activatedAt;
  final DateTime? resolvedAt;
  final AlertOutcome? outcome;

  /// 'voice' or 'tap'.
  final String? resolvedBy;

  /// Whole seconds left in the countdown.
  final int remaining;

  /// Whole seconds since the alert went active.
  final int elapsed;
}

typedef Clock = DateTime Function();

class AlertStateMachine {
  AlertStateMachine({this.cancelWindowSeconds = 15, Clock? clock}) : _clock = clock ?? DateTime.now;

  int cancelWindowSeconds;
  final Clock _clock;
  final _listeners = <void Function(AlertSnapshot)>[];

  AlertState _state = AlertState.idle;
  TriggerSource? _source;
  DateTime? _triggeredAt, _deadline, _activatedAt, _resolvedAt;
  AlertOutcome? _outcome;
  String? _resolvedBy;
  int? _lastRemaining;

  AlertState get state => _state;

  int get remaining {
    if (_state != AlertState.countdown) return 0;
    final ms = _deadline!.difference(_clock()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  int get elapsed =>
      _state == AlertState.active ? _clock().difference(_activatedAt!).inSeconds : 0;

  AlertSnapshot snapshot([AlertEvent event = AlertEvent.tick]) => AlertSnapshot(
        state: _state,
        event: event,
        source: _source,
        triggeredAt: _triggeredAt,
        activatedAt: _activatedAt,
        resolvedAt: _resolvedAt,
        outcome: _outcome,
        resolvedBy: _resolvedBy,
        remaining: remaining,
        elapsed: elapsed,
      );

  void Function() subscribe(void Function(AlertSnapshot) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _emit(AlertEvent event) {
    final snap = snapshot(event);
    for (final l in List.of(_listeners)) {
      l(snap);
    }
  }

  bool trigger(TriggerSource source) {
    if (_state != AlertState.idle) return false;
    final t = _clock();
    _state = AlertState.countdown;
    _source = source;
    _triggeredAt = t;
    _deadline = t.add(Duration(seconds: cancelWindowSeconds));
    _lastRemaining = remaining;
    _emit(AlertEvent.triggered);
    return true;
  }

  bool cancel([String by = 'tap']) {
    if (_state != AlertState.countdown) return false;
    _finish(AlertOutcome.cancelled, by);
    return true;
  }

  void tick() {
    if (_state == AlertState.countdown) {
      if (!_clock().isBefore(_deadline!)) {
        _state = AlertState.active;
        _activatedAt = _clock();
        _emit(AlertEvent.activated);
      } else if (remaining != _lastRemaining) {
        _lastRemaining = remaining;
        _emit(AlertEvent.countdown);
      }
    } else if (_state == AlertState.active) {
      _emit(AlertEvent.tick);
    }
  }

  /// Ends an active alert (patient returned / hold-to-confirm).
  bool resolve([String by = 'tap']) {
    if (_state != AlertState.active) return false;
    _finish(AlertOutcome.resolved, by);
    return true;
  }

  /// Takes over an alert that started elsewhere (the background service),
  /// keeping its original timing. Emits `triggered` for a countdown or
  /// `activated` for an alert that has already been sent.
  bool restore({
    required TriggerSource source,
    required DateTime triggeredAt,
    DateTime? activatedAt,
  }) {
    if (_state != AlertState.idle) return false;
    _source = source;
    _triggeredAt = triggeredAt;
    _deadline = triggeredAt.add(Duration(seconds: cancelWindowSeconds));
    if (activatedAt == null) {
      _state = AlertState.countdown;
      _lastRemaining = remaining;
      _emit(AlertEvent.triggered);
    } else {
      _state = AlertState.active;
      _activatedAt = activatedAt;
      _emit(AlertEvent.activated);
    }
    return true;
  }

  void reset() {
    _state = AlertState.idle;
    _source = null;
    _triggeredAt = _deadline = _activatedAt = _resolvedAt = null;
    _outcome = null;
    _resolvedBy = null;
    _emit(AlertEvent.reset);
  }

  void _finish(AlertOutcome outcome, String by) {
    _state = AlertState.resolved;
    _outcome = outcome;
    _resolvedBy = by;
    _resolvedAt = _clock();
    _emit(outcome == AlertOutcome.cancelled ? AlertEvent.cancelled : AlertEvent.resolved);
  }
}
