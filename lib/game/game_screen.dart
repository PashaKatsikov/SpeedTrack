import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_theme.dart';
import '../storage.dart';
import '../widgets.dart';
import 'game_painter.dart';
import 'game_world.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameWorld _world;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  bool _paused = false;
  bool _gameOver = false;
  int _countdown = 3;
  bool _started = false;
  int _bestAtStart = 0;

  @override
  void initState() {
    super.initState();
    _bestAtStart = Storage.instance.bestScore;
    _world = GameWorld(onGameOver: _onGameOver);
    _world.reset();
    _ticker = createTicker(_onTick)..start();
    _runCountdown();
  }

  Future<void> _runCountdown() async {
    for (int i = 3; i >= 1; i--) {
      if (!mounted) return;
      setState(() => _countdown = i);
      await Future.delayed(const Duration(milliseconds: 750));
    }
    if (!mounted) return;
    setState(() {
      _countdown = 0;
      _started = true;
    });
  }

  void _onTick(Duration elapsed) {
    final dtRaw = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (!_started || _paused || _gameOver) {
      _world.notifyFrame();
      return;
    }
    final dt = dtRaw.clamp(0.0, 0.05);
    final size = MediaQuery.sizeOf(context);
    _world.update(dt, size);
    _world.notifyFrame();
  }

  Future<void> _onGameOver() async {
    await Storage.instance
        .submitRun(score: _world.score, coins: _world.coins);
    if (!mounted) return;
    setState(() => _gameOver = true);
  }

  void _restart() {
    setState(() {
      _gameOver = false;
      _paused = false;
      _started = false;
      _countdown = 3;
      _bestAtStart = Storage.instance.bestScore;
    });
    _world.reset();
    _runCountdown();
  }

  void _handleTapDown(TapDownDetails d) {
    if (!_started || _paused || _gameOver) return;
    final w = MediaQuery.sizeOf(context).width;
    if (d.localPosition.dx < w / 2) {
      _world.moveLeft();
    } else {
      _world.moveRight();
    }
  }

  void _handleSwipe(DragEndDetails d) {
    if (!_started || _paused || _gameOver) return;
    final v = d.primaryVelocity ?? 0;
    if (v < -120) {
      _world.moveLeft();
    } else if (v > 120) {
      _world.moveRight();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _world.frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onHorizontalDragEnd: _handleSwipe,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: GamePainter(_world)),
              ),
            ),
            _buildHud(),
            if (_countdown > 0 && !_gameOver) _buildCountdown(),
            if (_paused) _buildPauseOverlay(),
            if (_gameOver) _buildGameOver(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _buildHud() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: ValueListenableBuilder<int>(
          valueListenable: _world.frames,
          builder: (context, _, _) {
            final best =
                _world.score > _bestAtStart ? _world.score : _bestAtStart;
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SCORE',
                            style: AppText.label(10,
                                color: AppColors.textDim,
                                weight: FontWeight.w600)),
                        Text('${_world.score}',
                            style: AppText.title(28)),
                        Text('BEST  $best',
                            style: AppText.label(11,
                                color: AppColors.gold,
                                weight: FontWeight.w700)),
                      ],
                    ),
                    const Spacer(),
                    _pauseButton(),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    StatChip(
                      icon: Icons.social_distance,
                      label: 'DISTANCE',
                      value: '${_world.meters} m',
                      color: AppColors.neonBlue,
                    ),
                    const SizedBox(width: 8),
                    StatChip(
                      icon: Icons.monetization_on,
                      label: 'COINS',
                      value: '${_world.coins}',
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 8),
                    StatChip(
                      icon: Icons.speed,
                      label: 'SPEED',
                      value: '${_world.speedKmh}',
                      color: AppColors.neonCyan,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _fuelBar(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _fuelBar() {
    final pct = _world.fuelPct;
    final color = pct < 0.25
        ? AppColors.neonRed
        : (pct < 0.5 ? AppColors.gold : AppColors.neonCyan);
    return Row(
      children: [
        Icon(Icons.local_gas_station, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Container(
                  height: 12,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
                FractionallySizedBox(
                  widthFactor: pct,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withValues(alpha: 0.7), color],
                      ),
                      boxShadow: [
                        BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pauseButton() {
    return GestureDetector(
      onTap: () {
        if (!_started || _gameOver) return;
        setState(() => _paused = true);
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.neonBlue.withValues(alpha: 0.7)),
        ),
        child: const Icon(Icons.pause, color: Colors.white, size: 22),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _buildCountdown() {
    return Center(
      child: Text(
        _countdown.toString(),
        style: AppText.title(120, color: Colors.white),
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return _dimmedOverlay(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('PAUSED', style: AppText.title(40)),
          const SizedBox(height: 28),
          NeonButton(
            label: 'Resume',
            icon: Icons.play_arrow,
            onTap: () => setState(() => _paused = false),
          ),
          const SizedBox(height: 14),
          NeonButton(
            label: 'Main Menu',
            icon: Icons.home,
            color: AppColors.neonPurple,
            filled: false,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOver() {
    final best = Storage.instance.bestScore;
    final isRecord = _world.score >= best && _world.score > 0;
    return _dimmedOverlay(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('GAME OVER', style: AppText.title(38, color: AppColors.neonRed)),
          if (isRecord) ...[
            const SizedBox(height: 8),
            Text('NEW RECORD!',
                style: AppText.label(16, color: AppColors.gold)),
          ],
          const SizedBox(height: 20),
          _resultRow('Score', '${_world.score}', AppColors.neonCyan),
          _resultRow('Distance', '${_world.meters} m', AppColors.neonBlue),
          _resultRow('Coins', '${_world.coins}', AppColors.gold),
          _resultRow('Best', '$best', AppColors.neonPurple),
          const SizedBox(height: 26),
          NeonButton(label: 'Retry', icon: Icons.refresh, onTap: _restart),
          const SizedBox(height: 14),
          NeonButton(
            label: 'Main Menu',
            icon: Icons.home,
            color: AppColors.neonPurple,
            filled: false,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: AppText.label(15, color: AppColors.textDim)),
          ),
          SizedBox(
            width: 110,
            child: Text(value,
                textAlign: TextAlign.right,
                style: AppText.label(18, color: color, weight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _dimmedOverlay({required Widget child}) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.68),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}
