import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../theme/app_theme.dart';

/// Friendly error / recovery block.
///
/// Every error in FLAME is:
///   - explained in plain words,
///   - recoverable (Retry / Open Settings / safe alternative),
///   - visibly guaranteed not to crash.
class RecoveryView extends StatelessWidget {
  const RecoveryView({
    super.key,
    required this.message,
    this.hint,
    this.onRetry,
    this.onAlternative,
    this.alternativeLabel,
    this.icon = Icons.sentiment_satisfied_alt,
  });

  final String message;
  final String? hint;
  final VoidCallback? onRetry;
  final VoidCallback? onAlternative;
  final String? alternativeLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FlameColors.errorSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: FlameColors.ember),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: FlameColors.ink,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: FlameColors.inkSoft,
              ),
            ),
          ],
          if (onRetry != null || onAlternative != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(150, 46),
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text(AppStrings.retry),
                  ),
                if (onAlternative != null) ...[
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: onAlternative,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(150, 46),
                    ),
                    child: Text(alternativeLabel ?? 'Go Back'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}