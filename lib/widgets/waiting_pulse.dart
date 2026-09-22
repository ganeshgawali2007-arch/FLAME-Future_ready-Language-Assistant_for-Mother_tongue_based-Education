import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Subtle waiting-room animation: a soft expanding ripple behind FLAME's
/// heartbeat flame. Calm, never busy — children find it reassuring.
class WaitingPulse extends StatefulWidget {
  const WaitingPulse({super.key, this.size = 96, this.child});

  final double size;
  final Widget? child;

  @override
  State<WaitingPulse> createState() => _WaitingPulseState();
}

class _WaitingPulseState extends State<WaitingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            _ripple(t, 1),
            _ripple(t, 0.5),
            child!,
          ],
        );
      },
      child: widget.child ??
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: FlameColors.flameGradient,
              boxShadow: [
                BoxShadow(
                  color: FlameColors.ember.withValues(alpha: 0.35),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.local_fire_department,
              color: Colors.white,
              size: 44,
            ),
          ),
    );
  }

  Widget _ripple(double t, double phase) {
    final p = (t + phase) % 1.0;
    return Transform.scale(
      scale: 1 + p * 0.6,
      child: Opacity(
        opacity: (1 - p) * 0.35,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: FlameColors.flame, width: 2),
          ),
        ),
      ),
    );
  }
}