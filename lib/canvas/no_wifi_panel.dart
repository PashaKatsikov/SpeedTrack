import 'package:flutter/material.dart';

import '../app_assets.dart';
import 'track_pill.dart';

/// Shown when the device has no connection. Uses the project's
/// dedicated no-wifi artwork (orientation-aware) with a Retry pill
/// overlaid near the bottom. Retry rebuilds whatever screen the caller
/// supplies via [onRetryBuild].
///
/// Landscape: NO SafeArea is applied, and the button is centered on
/// the full screen width (per the SpeedTrack design brief — safe-area
/// insets in landscape would shift the button off the horizontal
/// center of the underlying artwork).
class NoWifiPanel extends StatefulWidget {
  const NoWifiPanel({super.key, required this.onRetryBuild});

  final WidgetBuilder onRetryBuild;

  @override
  State<NoWifiPanel> createState() => _NoWifiPanelState();
}

class _NoWifiPanelState extends State<NoWifiPanel> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.onRetryBuild),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final String bg = landscape
        ? AppAssets.horizontalNoWifi
        : AppAssets.verticalNoWifi;

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
          // Retry button — always centered on the FULL screen width.
          // No SafeArea in landscape: the notch inset would shift the
          // button away from the horizontal center of the artwork.
          Positioned(
            left: 0,
            right: 0,
            bottom: size.height * (landscape ? 0.09 : 0.09),
            child: Center(
              child: _busy
                  ? const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF29B6FF)),
                      ),
                    )
                  : TrackPillBtn(
                      label: 'Retry',
                      icon: Icons.refresh_rounded,
                      width: landscape
                          ? (size.width * 0.30).clamp(220, 360)
                          : (size.width * 0.60).clamp(220, 380),
                      onTap: _retry,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
