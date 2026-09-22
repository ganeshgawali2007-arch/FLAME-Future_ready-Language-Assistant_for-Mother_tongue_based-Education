import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../models/enums.dart';
import '../theme/app_theme.dart';

/// One consistent offline indicator used on every screen.
///
/// Normal:  "Offline Ready" (green)   — absence of internet is normal.
/// Working: "Working Offline" (green) — an offline job is in progress.
/// Offline is never painted as a failure.
class OfflineBadge extends StatelessWidget {
  const OfflineBadge({
    super.key,
    this.mode = OfflineMode.ready,
    this.compact = false,
  });

  final OfflineMode mode;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = mode == OfflineMode.working
        ? AppStrings.workingOffline
        : AppStrings.offlineReady;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FlameColors.readySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: FlameColors.ready,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: FlameColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 12 : 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status chip used inside live sessions and the voice bot.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, this.animate = false});

  final String label;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final content = Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: FlameColors.flameGradient,
        borderRadius: BorderRadius.circular(999),
      ),
      child: animate
          ? _Pulsing(child: content)
          : content,
    );
  }
}

class _Pulsing extends StatefulWidget {
  const _Pulsing({required this.child});
  final Widget child;

  @override
  State<_Pulsing> createState() => _PulsingState();
}

class _PulsingState extends State<_Pulsing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _controller, child: widget.child);
  }
}