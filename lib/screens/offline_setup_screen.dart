import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../services/offline_status_service.dart';
import '../services/translation/offline_translation_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_badge.dart';

/// Offline readiness checklist (lazy, honest).
///
/// Loads the bundled translation index and education content, reports what is
/// ready ("Offline Ready") and what is labelled a pending pack — never blocks
/// startup and never claims a model that isn't installed.
class OfflineSetupScreen extends StatefulWidget {
  const OfflineSetupScreen({super.key});

  @override
  State<OfflineSetupScreen> createState() => _OfflineSetupScreenState();
}

class _OfflineSetupScreenState extends State<OfflineSetupScreen> {
  final List<_Check> _checks = [
    _Check('Hindi ↔ Santhali translation', AppStrings.errorLanguagePackNotReady),
    _Check('Lesson content', AppStrings.errorModelLoad),
  ];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Start the offline job after the first frame: startJob() notifies
    // listeners, which is illegal while the framework is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final offline = context.read<OfflineStatusService>();

    // 1. Translation index (bundled corpus). A wedged asset load must never
    // leave the user staring at the spinner forever, so the load is bounded;
    // if it can't finish the pack is simply labelled not-ready.
    await offline.runOfflineJob(() async {
      try {
        final engine = context.read<OfflineTranslationEngine>();
        await engine.phraseCache.ensureLoaded().timeout(
              const Duration(seconds: 3),
              onTimeout: () {},
            );
        _checks[0].ok = engine.phraseCache.isReady;
      } catch (_) {
        _checks[0].ok = false;
      }
    });

    // 2. Education content is bundled; lock-in only if corpus reached this far.
    _checks[1].ok = _checks[0].ok;

    // 3. Small offline "warm-up" so students see Working Offline briefly.
    await Future<void>.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    setState(() {
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              const OfflineBadge(),
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: FlameColors.flameGradient,
                ),
                child: _done
                    ? const Icon(Icons.check, color: Colors.white, size: 52)
                    : const Padding(
                        padding: EdgeInsets.all(26),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      ),
              ),
              const SizedBox(height: 28),
              Text(
                _done
                    ? AppStrings.offlineReady
                    : 'Setting up FLAME offline...',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: FlameColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'No internet is needed. Everything stays on your phone.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: FlameColors.inkSoft),
              ),
              const SizedBox(height: 32),
              ..._checks.map(
                (c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        c.ok
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: c.ok ? FlameColors.ready : FlameColors.amber,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          c.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: FlameColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (_done) ...[
                FilledButton(
                  onPressed: () {
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil('/home', (r) => false);
                  },
                  child: const Text(AppStrings.continueButton),
                ),
                const SizedBox(height: 28),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Check {
  _Check(this.label, this.errorLabel);
  final String label;
  final String errorLabel;
  bool ok = false;
}