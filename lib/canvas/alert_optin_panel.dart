import 'package:flutter/material.dart';

import '../app_assets.dart';
import '../cfg/route_config.dart';
import '../insight/insight.dart';
import '../pipe/alert_hub.dart';
import '../pipe/link_pulse.dart';
import '../pipe/local_store.dart';
import 'track_pill.dart';
import 'web_canvas.dart';

/// One-time push opt-in promo shown before the WebView (gray mode).
/// Uses the project's notification artwork (orientation-aware). Accept
/// triggers the OS permission dialog; Skip arms a 3-day cooldown.
/// Either way the user continues to the content immediately after.
///
/// Landscape: NO SafeArea and buttons anchored to the FULL screen
/// horizontal center — per the SpeedTrack design brief the horizontal
/// safe-area inset would visibly shift Accept / Skip away from the
/// artwork's center.
class AlertOptInPanel extends StatefulWidget {
  const AlertOptInPanel({
    super.key,
    required this.store,
    required this.alertHub,
    required this.linkPulse,
    required this.contentLink,
  });

  final LocalStore store;
  final AlertHub alertHub;
  final LinkPulse linkPulse;
  final String contentLink;

  @override
  State<AlertOptInPanel> createState() => _AlertOptInPanelState();
}

class _AlertOptInPanelState extends State<AlertOptInPanel> {
  @override
  void initState() {
    super.initState();
    Insight.screen('push_invite');
  }

  Future<void> _accept(BuildContext context) async {
    Insight.event('push_invite_accept');
    final bool granted = await widget.alertHub.askPermission();
    Insight.tag('notif_permission', granted ? 'granted' : 'denied');
    Insight.event(granted ? 'push_granted' : 'push_denied');
    if (!granted) {
      await widget.store.writeInviteResumeTs(_cooldownTarget());
    }
    if (context.mounted) _forward(context);
  }

  Future<void> _skip(BuildContext context) async {
    Insight.event('push_invite_skip');
    Insight.tag('notif_permission', 'skipped');
    await widget.store.writeInviteResumeTs(_cooldownTarget());
    if (context.mounted) _forward(context);
  }

  int _cooldownTarget() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 +
      RouteConfig.pushInviteCooldownSeconds;

  void _forward(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WebCanvas(
          link: widget.contentLink,
          store: widget.store,
          alertHub: widget.alertHub,
          linkPulse: widget.linkPulse,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final String bg = landscape
        ? AppAssets.horizontalNotifications
        : AppAssets.verticalNotifications;

    final double acceptWidth = landscape
        ? (size.width * 0.32).clamp(220, 380).toDouble()
        : (size.width * 0.70).clamp(220, 420).toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFF060912),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            bg,
            fit: BoxFit.cover,
            width: size.width,
            height: size.height,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.transparent, Color(0x99000000)],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: size.height * (landscape ? 0.07 : 0.09),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  TrackPillBtn(
                    label: 'Accept',
                    compact: landscape,
                    width: acceptWidth,
                    onTap: () => _accept(context),
                  ),
                  SizedBox(height: landscape ? 10 : 14),
                  TrackGhostBtn(
                    label: 'Skip',
                    compact: landscape,
                    width: acceptWidth,
                    onTap: () => _skip(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
