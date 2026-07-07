import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A glowing neon action button used throughout the menus and overlays.
class NeonButton extends StatefulWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color = AppColors.neonBlue,
    this.width = 240,
    this.filled = true,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Color color;
  final double width;
  final bool filled;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: widget.width,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: widget.filled
                ? LinearGradient(
                    colors: [
                      widget.color.withValues(alpha: 0.95),
                      widget.color.withValues(alpha: 0.55),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: widget.filled ? null : Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: widget.color.withValues(alpha: 0.9), width: 2),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _down ? 0.3 : 0.55),
                blurRadius: _down ? 8 : 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
              ],
              Text(
                widget.label.toUpperCase(),
                style: AppText.label(17, weight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small frosted stat chip (used in the HUD and overlays).
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.icon,
    required this.value,
    this.color = AppColors.neonCyan,
    this.label,
  });

  final IconData icon;
  final String value;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != null)
                Text(label!,
                    style: AppText.label(8.5,
                        color: AppColors.textDim, weight: FontWeight.w600)),
              Text(value, style: AppText.label(14, weight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}
