import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../app_assets.dart';
import 'game_layout.dart';
import 'sprite_cache.dart';

enum EntityKind { traffic, police, coin, oil }

class GameEntity {
  GameEntity({
    required this.kind,
    required this.lane,
    required this.y,
    required this.image,
    this.spin = 0,
  });

  final EntityKind kind;
  int lane;
  double y; // center Y in world/screen pixels
  ui.Image? image;
  double spin; // for coin rotation animation
  bool alive = true;

  bool get isSolid => kind == EntityKind.traffic || kind == EntityKind.police;
}

enum GameStatus { running, gameOver }

/// Holds and advances all gameplay state. Rendering reads from here.
class GameWorld {
  GameWorld({required this.onGameOver});

  final void Function() onGameOver;
  final Random _rng = Random();

  /// Ticked every frame so the [CustomPainter] and HUD can repaint.
  final ValueNotifier<int> frames = ValueNotifier<int>(0);
  void notifyFrame() => frames.value++;

  GameStatus status = GameStatus.running;

  // ---- Player ----
  int playerLane = 1;
  double playerLaneF = 1; // interpolated lane position for smooth switching
  double get playerTilt {
    final d = (playerLane - playerLaneF);
    return (d * 0.30).clamp(-0.28, 0.28);
  }

  // ---- Stats ----
  double _distancePx = 0;
  int coins = 0;
  double fuel = 100;
  double get fuelPct => (fuel / 100).clamp(0, 1);
  int get meters => (_distancePx / 14).floor();
  double get roadScroll => _distancePx;
  int get score => meters + coins * 12;
  int get speedKmh => (_worldSpeed / 3.2).round();

  // ---- Speed / difficulty ----
  double _worldSpeed = 340; // px per second (road scroll)
  static const double _minSpeed = 340;
  static const double _maxSpeed = 1020;

  // ---- Fuel burn ----
  static const double _fuelBurnPerSec = 3.4;

  // ---- Spawning ----
  double _distanceSinceRow = 0;
  double _distanceSinceCoin = 0;
  double _distanceSinceOil = 0;

  final List<GameEntity> entities = [];

  // ---- Background staging ----
  int bgIndex = 0;
  int prevBgIndex = 0;
  double bgFade = 1.0; // 1 => fully on bgIndex

  GameLayout? _layout;
  GameLayout? get layout => _layout;

  void reset() {
    status = GameStatus.running;
    playerLane = 1;
    playerLaneF = 1;
    _distancePx = 0;
    coins = 0;
    fuel = 100;
    _worldSpeed = _minSpeed;
    _distanceSinceRow = 0;
    _distanceSinceCoin = 260;
    _distanceSinceOil = 0;
    entities.clear();
    bgIndex = 0;
    prevBgIndex = 0;
    bgFade = 1.0;
  }

  void moveLeft() {
    if (status != GameStatus.running) return;
    if (playerLane > 0) playerLane--;
  }

  void moveRight() {
    if (status != GameStatus.running) return;
    if (playerLane < 2) playerLane++;
  }

  void moveToLane(int lane) {
    if (status != GameStatus.running) return;
    playerLane = lane.clamp(0, 2);
  }

  ui.Image? _img(String path) => SpriteCache.instance.get(path);

  void update(double dt, ui.Size size) {
    _layout = GameLayout(size);
    if (status != GameStatus.running) return;

    // Difficulty ramps up with distance travelled.
    final ramp = (_distancePx / 9000);
    _worldSpeed = (_minSpeed + ramp * 90).clamp(_minSpeed, _maxSpeed);

    final move = _worldSpeed * dt;
    _distancePx += move;
    _distanceSinceRow += move;
    _distanceSinceCoin += move;
    _distanceSinceOil += move;

    // Fuel drains constantly; higher speed burns a touch more.
    fuel -= (_fuelBurnPerSec + _worldSpeed / 900) * dt;
    if (fuel <= 0) {
      fuel = 0;
      _die();
      return;
    }

    // Smoothly interpolate the player toward the target lane.
    final targetLaneF = playerLane.toDouble();
    final diff = targetLaneF - playerLaneF;
    final step = 9.0 * dt;
    if (diff.abs() <= step) {
      playerLaneF = targetLaneF;
    } else {
      playerLaneF += diff.sign * step;
    }

    _updateBackground();
    _spawn(size);

    // Move entities downward and cull off-screen ones.
    for (final e in entities) {
      e.y += move;
      if (e.kind == EntityKind.coin) e.spin += dt * 5.5;
    }
    entities.removeWhere((e) => !e.alive || e.y > size.height + 220);

    _handleCollisions();
  }

  void _updateBackground() {
    final stage = (_distancePx / 5200).floor();
    final desired = stage % AppAssets.backgrounds.length;
    if (desired != bgIndex && bgFade >= 1.0) {
      prevBgIndex = bgIndex;
      bgIndex = desired;
      bgFade = 0.0;
    }
    if (bgFade < 1.0) {
      bgFade = (bgFade + 0.010).clamp(0.0, 1.0);
    }
  }

  // ---------------------------------------------------------------------------
  // Spawning
  // ---------------------------------------------------------------------------
  void _spawn(ui.Size size) {
    final difficulty = (_distancePx / 9000).clamp(0.0, 1.0);

    // Distance between traffic rows shrinks as difficulty rises.
    final rowGap = 430 - difficulty * 150; // 430 -> 280
    if (_distanceSinceRow >= rowGap) {
      _distanceSinceRow = 0;
      _spawnTrafficRow(size, difficulty);
    }

    // Coin clusters.
    if (_distanceSinceCoin >= 620) {
      _distanceSinceCoin = 0;
      if (_rng.nextDouble() < 0.85) _spawnCoinCluster(size);
    }

    // Fuel pickups.
    if (_distanceSinceOil >= 1550) {
      _distanceSinceOil = 0;
      _spawnOil(size);
    }
  }

  /// True if any entity in [lane] overlaps the vertical range
  /// [yStart, yEnd] (inclusive of [margin] padding on both ends). Since every
  /// entity scrolls down at the exact same speed, checking for overlap only
  /// at spawn time is enough to guarantee two entities never collide later.
  bool _laneOccupied(int lane, double yStart, double yEnd,
      {required double margin, bool solidOnly = false}) {
    final lo = min(yStart, yEnd) - margin;
    final hi = max(yStart, yEnd) + margin;
    for (final e in entities) {
      if (!e.alive || e.lane != lane) continue;
      if (solidOnly && !e.isSolid) continue;
      if (e.y >= lo && e.y <= hi) return true;
    }
    return false;
  }

  void _spawnTrafficRow(ui.Size size, double difficulty) {
    // Never block all three lanes: 1 car early, up to 2 later.
    final maxCars = difficulty > 0.45 ? 2 : 1;
    final count = 1 + (_rng.nextDouble() < difficulty * 0.9 ? 1 : 0);
    final n = count.clamp(1, maxCars);
    final margin = size.height * 0.12;

    final lanes = [0, 1, 2]..shuffle(_rng);
    int placed = 0;
    for (final lane in lanes) {
      if (placed >= n) break;
      final spawnY = -size.height * 0.25 - _rng.nextDouble() * 60;
      // Avoid dropping a car on top of anything already waiting in the lane
      // (traffic, coins or fuel cells) so nothing ever visually overlaps.
      if (_laneOccupied(lane, spawnY, spawnY, margin: margin)) continue;

      final bool isPolice = _rng.nextDouble() < 0.14;
      final image = isPolice
          ? _img(AppAssets.policeCar)
          : _img(AppAssets.trafficCars[_rng.nextInt(AppAssets.trafficCars.length)]);
      entities.add(GameEntity(
        kind: isPolice ? EntityKind.police : EntityKind.traffic,
        lane: lane,
        y: spawnY,
        image: image,
      ));
      placed++;
    }
  }

  void _spawnCoinCluster(ui.Size size) {
    final count = 3 + _rng.nextInt(3); // 3..5
    final startY = -size.height * 0.20;
    final gap = size.height * 0.085;
    final endY = startY - (count - 1) * gap;
    final margin = size.height * 0.12;

    // Only ever place coins in a lane that's clear of traffic across the
    // whole cluster span; skip this cycle entirely if all lanes are busy.
    final lanes = [0, 1, 2]..shuffle(_rng);
    int? lane;
    for (final candidate in lanes) {
      if (!_laneOccupied(candidate, startY, endY,
          margin: margin, solidOnly: true)) {
        lane = candidate;
        break;
      }
    }
    if (lane == null) return;

    for (int i = 0; i < count; i++) {
      entities.add(GameEntity(
        kind: EntityKind.coin,
        lane: lane,
        y: startY - i * gap,
        image: _img(AppAssets.coin),
        spin: _rng.nextDouble() * pi,
      ));
    }
  }

  void _spawnOil(ui.Size size) {
    final y = -size.height * 0.22;
    final margin = size.height * 0.12;

    final lanes = [0, 1, 2]..shuffle(_rng);
    int? lane;
    for (final candidate in lanes) {
      if (!_laneOccupied(candidate, y, y, margin: margin, solidOnly: true)) {
        lane = candidate;
        break;
      }
    }
    if (lane == null) return;

    entities.add(GameEntity(
      kind: EntityKind.oil,
      lane: lane,
      y: y,
      image: _img(AppAssets.oil),
    ));
  }

  // ---------------------------------------------------------------------------
  // Collisions
  // ---------------------------------------------------------------------------
  void _handleCollisions() {
    final l = _layout;
    if (l == null) return;

    final px = l.laneCenterXf(playerLaneF);
    final py = l.playerCenterY;
    final carHalfW = l.carSize * 0.22;
    final carHalfH = l.carSize * 0.30;

    for (final e in entities) {
      if (!e.alive) continue;
      final ex = l.laneCenterX(e.lane);
      final ey = e.y;

      if (e.isSolid) {
        final halfW = l.carSize * 0.22;
        final halfH = l.carSize * 0.30;
        final overlapX = (px - ex).abs() < (carHalfW + halfW);
        final overlapY = (py - ey).abs() < (carHalfH + halfH);
        if (overlapX && overlapY) {
          _die();
          return;
        }
      } else {
        // Collectibles: generous pickup radius.
        final r = l.laneWidth * 0.42;
        if ((px - ex).abs() < r && (py - ey).abs() < r) {
          e.alive = false;
          if (e.kind == EntityKind.coin) {
            coins += 1;
          } else if (e.kind == EntityKind.oil) {
            fuel = (fuel + 34).clamp(0, 100);
          }
        }
      }
    }
  }

  void _die() {
    if (status == GameStatus.gameOver) return;
    status = GameStatus.gameOver;
    onGameOver();
  }
}
