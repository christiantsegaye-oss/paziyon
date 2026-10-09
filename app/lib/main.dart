import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'core/alert_state_machine.dart';
import 'services/device_services.dart';
import 'services/voxide_bridge.dart';
import 'ui/alert_screens.dart';
import 'ui/tabs.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(deviceServices())..load();
  runApp(SeizureAlertApp(controller: controller));
}

class SeizureAlertApp extends StatelessWidget {
  const SeizureAlertApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          // Voxide runs in a hidden WebView that must stay mounted.
          final agent = c.services.agent;
          if (agent is VoxideBridge) {
            return Stack(children: [_screen(c), Positioned(left: 0, top: 0, child: agent.host)]);
          }
          return _screen(c);
        },
      ),
    );
  }

  Widget _screen(AppController c) {
    if (!c.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!c.onboarded) return WelcomeScreen(c: c);
    // The alert screens take over the whole display (spec 4.3).
    return switch (c.alert.state) {
      AlertState.idle => HomeShell(c: c),
      AlertState.countdown => CountdownScreen(c: c),
      AlertState.active => BystanderScreen(c: c),
      AlertState.resolved => ResolvedScreen(c: c),
    };
  }
}
