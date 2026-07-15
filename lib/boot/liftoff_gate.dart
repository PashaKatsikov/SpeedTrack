import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_assets.dart';
import '../app_theme.dart';
import '../canvas/alert_optin_panel.dart';
import '../canvas/no_wifi_panel.dart';
import '../canvas/web_canvas.dart';
import '../game/sprite_cache.dart';
import '../pipe/alert_hub.dart';
import '../pipe/gate_probe.dart';
import '../pipe/link_pulse.dart';
import '../pipe/local_store.dart';
import '../pipe/signal_relay.dart';
import '../screens/menu_screen.dart';
import '../storage.dart';
import '../insight/insight.dart';
import '../types/gate_verdict.dart';
import '../types/run_mode.dart';
import 'dart:math' as math;
// (math import is used by the progress driver clamp below)

/// Loading screen + gray/native decision engine. Direct implementation
/// of the state machine documented in the gray-flow guide:
///
/// - fresh install → attribution + gate → gray (WebView) or arcade (game)
/// - returning gray → cached link priority + fresh gate
/// - returning arcade → game (no network needed)
///
/// FIRST-LAUNCH UX INVARIANT
/// -------------------------
/// If the device is offline on the FIRST launch (OneLink install with
/// Wi-Fi disabled), _firstBoot() short-circuits into _openOffline()
/// BEFORE AppsFlyer / SDK init is awaited. The user sees the No-Wifi
/// screen on frame 1, and Retry restarts the full pipeline.
class LiftoffGate extends StatefulWidget {
  const LiftoffGate({
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
  State<LiftoffGate> createState() => _LiftoffGateState();
}

class _LiftoffGateState extends State<LiftoffGate>
    with SingleTickerProviderStateMixin {
  double _progress = 0.05;
  bool _routed = false;
  late final AnimationController _dots;

  @override
  void initState() {
    super.initState();
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    Insight.screen('loading');
    // onTokenRotated is wired in main.dart (long-lived) so that gate
    // re-posts survive pushReplacement to the opt-in / WebView screens.
    _drive();
  }

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  void _lift(double v) {
    if (mounted) setState(() => _progress = v.clamp(0.0, 1.0));
  }

  Future<void> _drive() async {
    await widget.alertHub.boot();
    _lift(0.18);

    switch (widget.store.readMode()) {
      case RunMode.arcade:
        await _goArcade(startAt: 0.4);
        break;
      case RunMode.gray:
        await _resumeGray();
        break;
      case RunMode.fresh:
        await _firstBoot();
        break;
    }
  }

  Future<void> _firstBoot() async {
    // Connectivity gate BEFORE AppsFlyer init — see First-Launch UX
    // Contract in the gray-flow guide. If we start the SDK offline it
    // can hang for tens of seconds while the OS launch background is
    // still on screen.
    if (!await widget.linkPulse.isReachable()) {
      _openOffline();
      return;
    }
    _lift(0.4);

    await widget.signalRelay.ignite();
    await Future.wait<void>(<Future<void>>[
      widget.signalRelay.awaitInstallData(),
      widget.signalRelay.awaitDeepLink(),
    ]);
    _lift(0.7);

    final GateVerdict verdict = await _ask();
    if (verdict.allowed && verdict.hasLink) {
      await widget.store.writeMode(RunMode.gray);
      _lift(1.0);
      await _settle();
      _openGray(verdict.link!);
    } else {
      // Permanent commitment to arcade — per §9 of the config request
      // contract, no further gate calls for the lifetime of this install.
      await widget.store.writeMode(RunMode.arcade);
      await _goArcade(startAt: 0.85);
    }
  }

  Future<void> _resumeGray() async {
    if (!await widget.linkPulse.isReachable()) {
      _lift(1.0);
      _openOffline();
      return;
    }
    _lift(0.4);

    // A pending push URL wins over EVERYTHING.
    final String? pending = await widget.store.takePendingLink();
    if (pending != null) {
      Insight.event('route_push_link');
      _lift(1.0);
      await _settle();
      _openGray(pending);
      return;
    }

    final String? cached = await widget.store.readCachedLink();

    await widget.signalRelay.ignite();
    await Future.wait<void>(<Future<void>>[
      widget.signalRelay.awaitInstallData(seconds: 10),
      widget.signalRelay.awaitDeepLink(),
    ]);
    _lift(0.75);

    final GateVerdict verdict = await _ask();
    _lift(1.0);
    await _settle();

    if (verdict.allowed && verdict.hasLink) {
      _openGray(verdict.link!);
    } else if (cached != null && cached.isNotEmpty) {
      // Last-known-good — never fall back to game on a returning gray
      // launch, never show a blank state.
      Insight.event('route_cached_link');
      _openGray(cached);
    } else {
      _openOffline();
    }
  }

  Future<GateVerdict> _ask() async {
    final String locale = Platform.localeName.replaceAll('-', '_');
    final Map<String, dynamic> body =
        await widget.signalRelay.assembleGateBody(
      locale: locale,
      pushToken: widget.alertHub.token,
    );
    // Identify AFTER af_id is known so session grouping is correct.
    Insight.identify(
      body['af_id']?.toString(),
      tags: <String, String>{
        'af_status': body['af_status']?.toString() ?? '',
        'media_source': body['media_source']?.toString() ?? '',
        'campaign': body['campaign']?.toString() ?? '',
        'os': body['os']?.toString() ?? '',
        'locale': body['locale']?.toString() ?? '',
      },
    );
    return widget.gateProbe.query(body);
  }

  Future<void> _settle() =>
      Future<void>.delayed(const Duration(milliseconds: 320));

  // ── Routing ─────────────────────────────────────────────────────

  Future<void> _goArcade({required double startAt}) async {
    Insight.tag('run_mode', 'native');
    Insight.event('route_native');
    _lift(startAt);
    // Game locks to portrait. The two loading + WebView screens rotate
    // freely; this call takes effect only for the game screen.
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await _warmGameArt();
    _lift(1.0);
    await _settle();
    if (_routed || !mounted) return;
    _routed = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (BuildContext ctx, Animation<double> a, Animation<double> sec) =>
            FadeTransition(opacity: a, child: const MenuScreen()),
      ),
    );
  }

  Future<void> _warmGameArt() async {
    await Storage.instance.init();
    try {
      await SpriteCache.instance.load(AppAssets.allGameplay);
    } catch (_) {}
    if (mounted) {
      try {
        await precacheImage(const AssetImage(AppAssets.gameName), context);
      } catch (_) {}
    }
  }

  void _openGray(String link) {
    if (_routed || !mounted) return;
    _routed = true;
    Insight.tag('run_mode', 'web');
    Insight.event('route_web');
    if (widget.store.shouldOfferPushInvite()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AlertOptInPanel(
            store: widget.store,
            alertHub: widget.alertHub,
            linkPulse: widget.linkPulse,
            contentLink: link,
          ),
        ),
      );
    } else {
      // Returning user — push invite already handled; tag the known state.
      Insight.tag(
        'notif_permission',
        widget.store.isPushGranted()
            ? 'granted'
            : widget.store.isPushDeniedByOs()
                ? 'os_denied'
                : 'snoozed',
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => WebCanvas(
            link: link,
            store: widget.store,
            alertHub: widget.alertHub,
            linkPulse: widget.linkPulse,
          ),
        ),
      );
    }
  }

  void _openOffline() {
    if (_routed || !mounted) return;
    _routed = true;
    Insight.event('route_offline');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => NoWifiPanel(
          onRetryBuild: (_) => LiftoffGate(
            store: widget.store,
            linkPulse: widget.linkPulse,
            signalRelay: widget.signalRelay,
            gateProbe: widget.gateProbe,
            alertHub: widget.alertHub,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final String bg = landscape
        ? AppAssets.horizontalLoading
        : AppAssets.verticalLoading;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(bg, fit: BoxFit.cover),
              Container(color: Colors.black.withValues(alpha: 0.14)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Colors.transparent, Color(0x77000000)],
                  ),
                ),
              ),
              // В горизонтальной ориентации SafeArea добавляет боковые
              // отступы от выреза камеры и смещает горизонтальный центр.
              // Поэтому в landscape используем чистый Padding без SafeArea;
              // в portrait SafeArea нужен только для верхнего inset.
              Padding(
                padding: landscape
                    ? EdgeInsets.fromLTRB(32, 0, 32, 30)
                    : EdgeInsetsDirectional.fromSTEB(
                        32,
                        MediaQuery.of(context).viewPadding.top,
                        32,
                        60,
                      ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                      AnimatedBuilder(
                        animation: _dots,
                        builder: (BuildContext ctx, _) {
                          final int n =
                              math.max(0, (_dots.value * 4).floor() % 4);
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                'Loading',
                                style: AppText.label(20,
                                    weight: FontWeight.w800),
                              ),
                              SizedBox(
                                width: 26,
                                child: Text(
                                  '.' * n,
                                  style: AppText.label(20,
                                      weight: FontWeight.w800),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      _ProgressTrack(value: _progress),
                      const SizedBox(height: 8),
                      Text(
                        '${(_progress * 100).round()}%',
                        style: AppText.label(
                          13,
                          color: AppColors.textDim,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints c) {
        return Stack(
          children: <Widget>[
            Container(
              height: 16,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.neonBlue.withValues(alpha: 0.55),
                  width: 1.4,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              height: 16,
              width: c.maxWidth * value.clamp(0.0, 1.0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[AppColors.neonBlue, AppColors.neonCyan],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.neonCyan.withValues(alpha: 0.75),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
