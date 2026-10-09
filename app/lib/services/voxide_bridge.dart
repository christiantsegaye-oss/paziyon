import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/content.dart';
import 'services.dart';

/// Runs Voxide inside the app.
///
/// Voxide's SDK only runs in a browser engine, so the app hosts it in a hidden
/// 1×1 WebView ([host]) on a page it serves itself from http://localhost
/// (assets/voxide/). Voxide accepts localhost without domain whitelisting, and
/// localhost counts as a secure origin, so the page may use the microphone.
/// Messages go both ways: Dart calls `window.pz.*`; the page answers through
/// the `PZ` JavaScript channel.
class VoxideBridge implements VoiceAgent {
  VoxideBridge() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('PZ', onMessageReceived: (m) => _onMessage(m.message));
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // Speak without a tap, and let the page use the microphone (the app
      // itself already holds RECORD_AUDIO).
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setOnPlatformPermissionRequest((request) => request.grant());
    }
  }

  late final WebViewController controller;

  /// Mount once, anywhere in the tree. It has to be attached for audio and
  /// the microphone to work, but is invisible.
  Widget get host => SizedBox(
        width: 1,
        height: 1,
        child: Opacity(opacity: 0.01, child: WebViewWidget(controller: controller)),
      );

  HttpServer? _server;
  bool _pageReady = false;
  final _pending = <String>[];
  int _nextSayId = 1;
  final _sayWaiters = <int, Completer<bool>>{};

  AgentStatus _status = AgentStatus.off;
  final _statusCtl = StreamController<AgentStatus>.broadcast();
  final _heardCtl = StreamController<Heard>.broadcast();
  final _saidCtl = StreamController<String>.broadcast();
  final _toolCtl = StreamController<AgentToolCall>.broadcast();
  final _errorCtl = StreamController<String>.broadcast();
  int _utterance = 0;
  bool _inUtterance = false;

  @override
  AgentStatus get status => _status;
  @override
  Stream<AgentStatus> get statusChanges => _statusCtl.stream;
  @override
  Stream<Heard> get heard => _heardCtl.stream;
  @override
  Stream<String> get said => _saidCtl.stream;
  @override
  Stream<AgentToolCall> get toolCalls => _toolCtl.stream;
  @override
  Stream<String> get errors => _errorCtl.stream;

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'application/javascript; charset=utf-8',
  };

  Future<void> _ensurePage() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((req) async {
      final name = req.uri.pathSegments.isEmpty ? 'bridge.html' : req.uri.pathSegments.last;
      final ext = name.split('.').last;
      try {
        if (!_types.containsKey(ext) || name.contains('..')) throw const FormatException();
        final data = await rootBundle.load('assets/voxide/$name');
        req.response.headers.set(HttpHeaders.contentTypeHeader, _types[ext]!);
        req.response.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      } catch (_) {
        req.response.statusCode = HttpStatus.notFound;
      }
      await req.response.close();
    });
    await controller.loadRequest(Uri.parse('http://localhost:${server.port}/bridge.html'));
  }

  void _call(String js) {
    if (_pageReady) {
      controller.runJavaScript(js);
    } else {
      _pending.add(js);
    }
  }

  void _onMessage(String raw) {
    final Map<String, dynamic> e;
    try {
      e = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (e['type']) {
      case 'bridge_ready':
        _pageReady = true;
        for (final js in _pending) {
          controller.runJavaScript(js);
        }
        _pending.clear();
      case 'status':
        _status = switch (e['status']) {
          'connecting' => AgentStatus.connecting,
          'listening' || 'armed' => AgentStatus.listening,
          'thinking' => AgentStatus.thinking,
          'speaking' => AgentStatus.speaking,
          'executing' => AgentStatus.executing,
          'error' => AgentStatus.error,
          _ => AgentStatus.off,
        };
        _statusCtl.add(_status);
      case 'heard':
        // One utterance runs from its first partial to its final result.
        if (!_inUtterance) {
          _utterance++;
          _inUtterance = true;
        }
        final isFinal = e['final'] == true;
        _heardCtl.add(Heard(e['text'] as String? ?? '', isFinal: isFinal, utterance: 100000 + _utterance));
        if (isFinal) _inUtterance = false;
      case 'said':
        _saidCtl.add(e['text'] as String? ?? '');
      case 'tool':
        _toolCtl.add(AgentToolCall(
          (e['id'] as num).toInt(),
          e['name'] as String,
          Map<String, Object?>.from(e['args'] as Map? ?? const {}),
        ));
      case 'say_done':
        _sayWaiters.remove((e['id'] as num).toInt())?.complete(e['ok'] == true);
      case 'error':
        _errorCtl.add(e['message'] as String? ?? 'Voxide error');
    }
  }

  @override
  Future<void> start({required String key, required Lang lang}) async {
    await _ensurePage();
    _call('pz.start(${jsonEncode(key)}, ${jsonEncode(lang.name)})');
  }

  @override
  Future<void> stop() async {
    _call('pz.stop()');
    _status = AgentStatus.off;
    _statusCtl.add(_status);
  }

  @override
  void setLanguage(Lang lang) => _call('pz.setLanguage(${jsonEncode(lang.name)})');

  @override
  void setState(Map<String, Object?> state) => _call('pz.setState(${jsonEncode(state)})');

  @override
  void resolveTool(int id, Map<String, Object?> result) => _call('pz.resolveTool($id, ${jsonEncode(result)})');

  @override
  Future<bool> say(String text, Lang lang) {
    if (!_pageReady || _status == AgentStatus.off || _status == AgentStatus.error || _status == AgentStatus.connecting) {
      return Future.value(false);
    }
    final id = _nextSayId++;
    final done = Completer<bool>();
    _sayWaiters[id] = done;
    _call('pz.say($id, ${jsonEncode(text)}, ${jsonEncode(lang.name)})');
    return done.future.timeout(const Duration(seconds: 40), onTimeout: () {
      _sayWaiters.remove(id);
      return false;
    });
  }

  @override
  void interrupt() {
    _call('pz.interrupt()');
    for (final w in _sayWaiters.values) {
      if (!w.isCompleted) w.complete(true);
    }
    _sayWaiters.clear();
  }
}
