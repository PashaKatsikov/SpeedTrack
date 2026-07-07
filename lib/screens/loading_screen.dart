import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app_assets.dart';
import '../app_theme.dart';
import '../game/sprite_cache.dart';
import '../storage.dart';
import 'menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _elapsed = 0;

  double _progress = 0;
  bool _assetsReady = false;
  bool _navigated = false;

  // Fill only reaches full right before launch; hold below this until ready.
  static const double _holdCap = 0.9;
  static const double _minSeconds = 2.4;

  @override
  void initState() {
    super.initState();
    _preload();
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _preload() async {
    await Storage.instance.init();
    await SpriteCache.instance.load(AppAssets.allGameplay);
    // Warm up the loading/branding images too.
    if (mounted) {
      await Future.wait([
        precacheImage(const AssetImage(AppAssets.gameName), context),
        precacheImage(const AssetImage(AppAssets.verticalLoading), context),
        precacheImage(const AssetImage(AppAssets.horizontalLoading), context),
      ]);
    }
    _assetsReady = true;
  }

  void _onTick(Duration now) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    _elapsed += dt;

    final ready = _assetsReady && _elapsed >= _minSeconds;
    if (!ready) {
      // Ease toward the hold cap.
      _progress += (_holdCap - _progress) * (dt * 1.4);
      if (_progress > _holdCap) _progress = _holdCap;
    } else {
      // Snap to full right before launching.
      _progress += dt / 0.45;
      if (_progress >= 1.0) {
        _progress = 1.0;
        _launch();
      }
    }
    setState(() {});
  }

  void _launch() {
    if (_navigated) return;
    _navigated = true;
    _ticker.stop();
    // Lock the gameplay to portrait once loading is finished.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, a, _) =>
            FadeTransition(opacity: a, child: const MenuScreen()),
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          final asset = isPortrait
              ? AppAssets.verticalLoading
              : AppAssets.horizontalLoading;
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(asset, fit: BoxFit.cover),
              Container(color: Colors.black.withValues(alpha: 0.12)),
              _buildBottomBar(isPortrait),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomBar(bool isPortrait) {
    final dots = '.' * ((_elapsed * 2).floor() % 4);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: 32,
          right: 32,
          bottom: isPortrait ? 70 : 34,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Loading',
                      style: AppText.label(20, weight: FontWeight.w800)),
                  SizedBox(
                    width: 26,
                    child: Text(
                      dots,
                      style: AppText.label(20, weight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                return Stack(
                  children: [
                    Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.neonBlue.withValues(alpha: 0.5),
                            width: 1.2),
                      ),
                    ),
                    // Left-to-right fill.
                    Container(
                      height: 16,
                      width: (w * _progress).clamp(0.0, w),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.neonBlue, AppColors.neonCyan],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.neonCyan.withValues(alpha: 0.7),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: Text(
                '${(_progress * 100).round()}%',
                style: AppText.label(13,
                    color: AppColors.textDim, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
