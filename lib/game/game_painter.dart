import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_assets.dart';
import '../app_theme.dart';
import 'game_layout.dart';
import 'game_world.dart';
import 'sprite_cache.dart';

class GamePainter extends CustomPainter {
  GamePainter(this.world) : super(repaint: world.frames);

  final GameWorld world;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = GameLayout(size);
    _drawBackground(canvas, size);
    _drawRoad(canvas, layout);
    _drawEntities(canvas, layout);
    _drawPlayer(canvas, layout);
    _drawSpeedVignette(canvas, size);
  }

  // ---------------------------------------------------------------------------
  void _drawBackground(Canvas canvas, Size size) {
    final prev = SpriteCache.instance.get(AppAssets.backgrounds[world.prevBgIndex]);
    final curr = SpriteCache.instance.get(AppAssets.backgrounds[world.bgIndex]);
    if (prev != null && world.bgFade < 1.0) {
      _drawImageCover(canvas, prev, size, opacity: 1.0);
    }
    if (curr != null) {
      _drawImageCover(canvas, curr, size, opacity: world.bgFade);
    } else {
      canvas.drawRect(
          Offset.zero & size, Paint()..color = AppColors.bgDeep);
    }
    // Subtle darkening so sprites and HUD stay readable.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
  }

  void _drawImageCover(Canvas canvas, ui.Image img, Size size,
      {double opacity = 1.0}) {
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    final scale = max(size.width / iw, size.height / ih);
    final dw = iw * scale;
    final dh = ih * scale;
    final dx = (size.width - dw) / 2;
    final dy = (size.height - dh) / 2;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0));
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, iw, ih),
      Rect.fromLTWH(dx, dy, dw, dh),
      paint,
    );
  }

  // ---------------------------------------------------------------------------
  void _drawRoad(Canvas canvas, GameLayout l) {
    final rect = Rect.fromLTRB(l.bandLeft, 0, l.bandRight, l.size.height);

    // Darkened translucent asphalt band for lane clarity.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x66050810), Color(0x99050810)],
          stops: [0.0, 0.35, 1.0],
        ).createShader(rect),
    );

    // Neon side rails.
    final railPaint = Paint()
      ..color = AppColors.neonBlue.withValues(alpha: 0.9)
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawLine(Offset(l.bandLeft, 0), Offset(l.bandLeft, l.size.height), railPaint);
    canvas.drawLine(
        Offset(l.bandRight, 0), Offset(l.bandRight, l.size.height), railPaint);
    final railCore = Paint()
      ..color = AppColors.neonCyan
      ..strokeWidth = 2;
    canvas.drawLine(Offset(l.bandLeft, 0), Offset(l.bandLeft, l.size.height), railCore);
    canvas.drawLine(
        Offset(l.bandRight, 0), Offset(l.bandRight, l.size.height), railCore);

    // Scrolling dashed lane dividers.
    final dashLen = 46.0;
    final gap = 34.0;
    final period = dashLen + gap;
    final offset = world.roadScroll % period;
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    for (int divider = 1; divider <= 2; divider++) {
      final x = l.bandLeft + l.laneWidth * divider;
      for (double y = -period + offset; y < l.size.height; y += period) {
        canvas.drawLine(Offset(x, y), Offset(x, y + dashLen), dashPaint);
      }
    }
  }

  // ---------------------------------------------------------------------------
  void _drawEntities(Canvas canvas, GameLayout l) {
    for (final e in world.entities) {
      if (!e.alive || e.image == null) continue;
      final cx = l.laneCenterX(e.lane);
      switch (e.kind) {
        case EntityKind.traffic:
        case EntityKind.police:
          _drawSquareSprite(canvas, e.image!, cx, e.y, l.carSize, shadow: true);
          break;
        case EntityKind.coin:
          _drawCoin(canvas, e, cx, l);
          break;
        case EntityKind.oil:
          _drawGlowSprite(canvas, e.image!, cx, e.y, l.laneWidth * 0.62,
              glow: AppColors.neonCyan);
          break;
      }
    }
  }

  void _drawSquareSprite(Canvas canvas, ui.Image img, double cx, double cy,
      double size,
      {bool shadow = false}) {
    if (shadow) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, cy + size * 0.30),
            width: size * 0.52,
            height: size * 0.16),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.38)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    final dst = Rect.fromCenter(center: Offset(cx, cy), width: size, height: size);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  void _drawCoin(Canvas canvas, GameEntity e, double cx, GameLayout l) {
    final size = l.laneWidth * 0.5;
    final squash = max(0.16, cos(e.spin).abs());
    canvas.save();
    canvas.translate(cx, e.y);
    canvas.scale(squash, 1.0);
    // Glow behind the coin.
    canvas.drawCircle(
      Offset.zero,
      size * 0.62,
      Paint()
        ..color = AppColors.gold.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    final dst = Rect.fromCenter(center: Offset.zero, width: size, height: size);
    canvas.drawImageRect(
      e.image!,
      Rect.fromLTWH(0, 0, e.image!.width.toDouble(), e.image!.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  void _drawGlowSprite(Canvas canvas, ui.Image img, double cx, double cy,
      double size,
      {required Color glow}) {
    canvas.drawCircle(
      Offset(cx, cy),
      size * 0.55,
      Paint()
        ..color = glow.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    final dh = size * (ih / iw);
    final dst = Rect.fromCenter(center: Offset(cx, cy), width: size, height: dh);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, iw, ih),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  // ---------------------------------------------------------------------------
  void _drawPlayer(Canvas canvas, GameLayout l) {
    final img = SpriteCache.instance.get(AppAssets.playerCar);
    if (img == null) return;
    final cx = l.laneCenterXf(world.playerLaneF);
    final cy = l.playerCenterY;
    final size = l.carSize;

    // Ground shadow.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy + size * 0.30),
          width: size * 0.55,
          height: size * 0.17),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // Neon under-glow that reacts to danger (low fuel).
    final glowColor =
        world.fuelPct < 0.25 ? AppColors.neonRed : AppColors.neonBlue;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy + size * 0.20),
          width: size * 0.5,
          height: size * 0.28),
      Paint()
        ..color = glowColor.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(world.playerTilt);
    final dst =
        Rect.fromCenter(center: Offset.zero, width: size, height: size);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  void _drawSpeedVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
          stops: const [0.68, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => false;
}
