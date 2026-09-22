import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Big central microphone used by Ask FLAME.
class BigMicButton extends StatelessWidget {
  const BigMicButton({
    super.key,
    required this.onTap,
    this.enabled = true,
    this.recording = false,
    this.size = 120,
  });

  final VoidCallback onTap;
  final bool enabled;
  final bool recording;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: recording
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [FlameColors.amber, FlameColors.flame],
                )
              : FlameColors.flameGradient,
          boxShadow: [
            BoxShadow(
              color: (recording ? FlameColors.amber : FlameColors.ember)
                  .withValues(alpha: 0.35),
              blurRadius: recording ? 40 : 22,
              spreadRadius: recording ? 6 : 2,
            ),
          ],
        ),
        child: recording
            ? _Waves()
            : Icon(
                Icons.mic,
                size: size * 0.45,
                color: enabled ? Colors.white : Colors.white60,
              ),
      ),
    );
  }
}

class _Waves extends StatefulWidget {
  @override
  State<_Waves> createState() => _WavesState();
}

class _WavesState extends State<_Waves> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
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
      builder: (context, _) {
        final value = _controller.value;
        final heights = [
          0.35, 0.7, 1.0, 0.7, 0.35,
        ];
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final phase = ((value * 5 + i) / 5) % 1.0;
            return Container(
              width: 6,
              height: 28 * (0.5 + (heights[i] * (0.5 + phase * 0.5))),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }
}