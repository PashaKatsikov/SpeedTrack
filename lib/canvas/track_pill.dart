import 'package:flutter/material.dart';

/// Primary gradient pill button used across the gray-flow overlay
/// screens (no-wifi, notification opt-in). Intentionally distinct from
/// the native game's neon menu buttons so the two visual languages
/// don't blur together for reviewers.
///
/// Label follows §13 of `gray_part_pitfalls.md`: `height: 1.0` line-
/// height and a hard `CrossAxisAlignment.center` to kill baseline drift.
class TrackPillBtn extends StatefulWidget {
  const TrackPillBtn({
    super.key,
    required this.label,
    required this.onTap,
    this.compact = false,
    this.width,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;
  final double? width;
  final IconData? icon;

  @override
  State<TrackPillBtn> createState() => _TrackPillBtnState();
}

class _TrackPillBtnState extends State<TrackPillBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 90),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (BuildContext ctx, Widget? child) {
            final double glow = 0.35 + _pulse.value * 0.35;
            return Container(
              width: widget.width,
              padding: EdgeInsets.symmetric(
                horizontal: 26,
                vertical: widget.compact ? 12 : 16,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF29B6FF), Color(0xFF0F5FA3)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 2,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF29B6FF).withValues(alpha: glow),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                  const BoxShadow(
                    color: Color(0x55000000),
                    offset: Offset(0, 4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.icon != null) ...<Widget>[
                Icon(
                  widget.icon,
                  color: Colors.white,
                  size: widget.compact ? 18 : 22,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.compact ? 16 : 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  height: 1.0,
                  shadows: const <Shadow>[
                    Shadow(
                      color: Color(0x66000000),
                      offset: Offset(0, 2),
                      blurRadius: 3,
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

/// Secondary "Skip" pill. Same size / radius as [TrackPillBtn] but a
/// dimmer glass fill — never a text-only link (§12 of the pitfalls
/// guide). Weight of Accept > Skip comes from color, never opacity.
class TrackGhostBtn extends StatefulWidget {
  const TrackGhostBtn({
    super.key,
    required this.label,
    required this.onTap,
    this.compact = false,
    this.width,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;
  final double? width;

  @override
  State<TrackGhostBtn> createState() => _TrackGhostBtnState();
}

class _TrackGhostBtnState extends State<TrackGhostBtn> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: widget.width,
          padding: EdgeInsets.symmetric(
            horizontal: 26,
            vertical: widget.compact ? 11 : 15,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.65),
              width: 1.6,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x55000000),
                offset: Offset(0, 3),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.compact ? 15 : 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
