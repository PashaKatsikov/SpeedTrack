import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../cfg/route_config.dart';
import '../pipe/alert_hub.dart';
import '../pipe/link_pulse.dart';
import '../pipe/gate_probe.dart';
import '../pipe/local_store.dart';
import '../pipe/signal_relay.dart';
import 'liftoff_gate.dart';

/// Root widget. Owns the long-lived bridges and hands them to the
/// [LiftoffGate] router (loading screen + native-vs-gray decision).
class TrackShell extends StatelessWidget {
  const TrackShell({
    super.key,
    required this.store,
    required this.linkPulse,
    required this.signalRelay,
    required this.gateProbe,
    required this.alertHub,
  });

  final LocalStore store;
  final LinkPulse linkPulse;
  final SignalRelay signalRelay;
  final GateProbe gateProbe;
  final AlertHub alertHub;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: RouteConfig.displayName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: AppText.fontFallback,
        scaffoldBackgroundColor: AppColors.bgDeep,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.neonBlue,
          brightness: Brightness.dark,
        ),
      ),
      home: LiftoffGate(
        store: store,
        linkPulse: linkPulse,
        signalRelay: signalRelay,
        gateProbe: gateProbe,
        alertHub: alertHub,
      ),
    );
  }
}
