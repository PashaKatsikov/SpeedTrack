import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:io';

import 'boot/track_shell.dart';
import 'pipe/alert_hub.dart';
import 'pipe/gate_probe.dart';
import 'pipe/link_pulse.dart';
import 'pipe/local_store.dart';
import 'pipe/signal_relay.dart';
import 'pipe/ua_masker.dart';

/// Bootstrap.
///
/// Wiring order (do NOT reshuffle without reading the gray-flow guide):
///   1. Bindings ensure — required before any plugin call.
///   2. Firebase + AppCheck — best-effort. When google-services.json
///      is absent (template ships without it) the try/catch swallows
///      the failure and the shell falls back to arcade mode. NEVER
///      block startup on Firebase.
///   3. Orientation whitelist — all four; game locks to portrait
///      itself inside LiftoffGate._goArcade / MenuScreen.
///   4. Status bar transparent + light icons — loading artwork is
///      edge-to-edge.
///   5. siteAgent.warmUp() — forges the device UA BEFORE any bridge
///      is created. The gate probe uses the primed value on its very
///      first HTTP call.
///   6. LocalStore.warmUp() — reads SharedPreferences into memory so
///      the first frame of LiftoffGate can decide the route
///      synchronously (no async await = no blank splash flicker).
///   7. Bridges constructed but not booted here — AlertHub +
///      SignalRelay ignite inside LiftoffGate after the UI is up.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  } catch (_) {
    // No google-services.json yet — that's fine, gray mode simply
    // won't activate until credentials land.
  }

  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await siteAgent.warmUp();

  final LocalStore store = LocalStore();
  await store.warmUp();

  final LinkPulse linkPulse = LinkPulse();
  final SignalRelay signalRelay = SignalRelay();
  final GateProbe gateProbe = GateProbe(store);
  final AlertHub alertHub = AlertHub(store);

  // Long-lived push-token → gate re-post hook. Owned here (not in
  // LiftoffGate) so it survives Navigator.pushReplacement transitions
  // to the opt-in / WebView screens. Without this the partner backend
  // never learns the FCM token for this install and every push is
  // rejected with "Установка приложения не найдена".
  alertHub.onTokenRotated = (String token) {
    () async {
      try {
        final String locale = Platform.localeName.replaceAll('-', '_');
        final Map<String, dynamic> body =
            await signalRelay.assembleGateBody(locale: locale, pushToken: token);
        await gateProbe.query(body);
      } catch (_) {}
    }();
  };

  runApp(TrackShell(
    store: store,
    linkPulse: linkPulse,
    signalRelay: signalRelay,
    gateProbe: gateProbe,
    alertHub: alertHub,
  ));
}
