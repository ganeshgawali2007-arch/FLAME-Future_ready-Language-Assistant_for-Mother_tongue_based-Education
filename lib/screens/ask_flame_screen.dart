import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../models/enums.dart';
import '../services/voice/voice_bot_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/big_mic_button.dart';
import '../widgets/mic_permission.dart';
import '../widgets/offline_badge.dart';
import '../widgets/recovery_view.dart';
import '../widgets/sanathali_text.dart';
import '../widgets/waiting_pulse.dart';

/// Ask FLAME — the offline educational voice bot.
///
/// Extremely simple for children. Technical terms are never shown:
/// phases are Listening / Understanding / Answering / Speaking.
class AskFlameScreen extends StatelessWidget {
  const AskFlameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bot = context.watch<VoiceBotController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.askFlame),
        backgroundColor: FlameColors.deepEmber,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            bot.stopAudio();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            const OfflineBadge(),
            const SizedBox(height: 18),
            const Text(
              AppStrings.askFlameSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: FlameColors.inkSoft,
              ),
            ),
            const SizedBox(height: 24),
            _body(context, bot),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, VoiceBotController bot) {
    switch (bot.phase) {
      case VoiceBotPhase.idle:
        return _IdleView(bot: bot);
      case VoiceBotPhase.listening:
        return const _ListeningView();
      case VoiceBotPhase.understanding:
      case VoiceBotPhase.answering:
      case VoiceBotPhase.speaking:
        return _ThinkingView(bot: bot);
      case VoiceBotPhase.done:
        return _AnswerView(bot: bot);
      case VoiceBotPhase.error:
        return _ErrorView(bot: bot);
    }
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.bot});
  final VoiceBotController bot;

  @override
  Widget build(BuildContext context) {
    if (bot.mic != MicPermissionState.granted) {
      // "Let FLAME hear you" explainer before the mic ever starts. Typing a
      // question must stay available without a microphone, so the typed entry
      // point is deliberately OUTSIDE the gate.
      return Column(
        children: [
          MicPermissionGate(
            onGranted: () {
              bot.onMicGranted();
            },
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () => _askTyped(context, bot),
            icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
            label: const Text(AppStrings.typeQuestion),
            style: TextButton.styleFrom(foregroundColor: FlameColors.inkSoft),
          ),
        ],
      );
    }
    return Column(
      children: [
        BigMicButton(
          onTap: () => bot.startListening(),
          enabled: true,
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => bot.startListening(),
          icon: const Icon(Icons.mic),
          label: const Text(AppStrings.tapAndSpeak),
          style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: () => _askTyped(context, bot),
          icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
          label: const Text(AppStrings.typeQuestion),
          style: TextButton.styleFrom(foregroundColor: FlameColors.inkSoft),
        ),
        const SizedBox(height: 10),
        if (!bot.speechRecognitionAvailable)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Speaking by voice is being added on this device. '
              'You can type any question now.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: FlameColors.inkSoft),
            ),
          ),
      ],
    );
  }
}

class _ListeningView extends StatelessWidget {
  const _ListeningView();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Center(child: WaitingPulse()),
        SizedBox(height: 24),
        StatusChipInline(label: 'Listening...'),
      ],
    );
  }
}

class _ThinkingView extends StatelessWidget {
  const _ThinkingView({required this.bot});
  final VoiceBotController bot;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        StatusChipInline(label: bot.phase.statusText),
      ],
    );
  }
}

class _AnswerView extends StatelessWidget {
  const _AnswerView({required this.bot});
  final VoiceBotController bot;

  @override
  Widget build(BuildContext context) {
    final result = bot.result;
    if (result == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LabeledCard(
          label: AppStrings.yourQuestion,
          icon: Icons.help_outline,
          child: Text(
            result.question,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: FlameColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _LabeledCard(
          label: 'FLAME',
          icon: Icons.local_fire_department,
          accent: FlameColors.ember,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              result.answerSanthali.isNotEmpty
                    ? SanathaliText(
                        result.answerSanthali,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: FlameColors.ink,
                        ),
                      )
                    : Text(
                        result.answerHindi,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: FlameColors.ink,
                        ),
                      ),
              if (result.answerSanthali.isEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '${result.answerHindi} (हिन्दी)',
                  style: const TextStyle(
                    fontSize: 13,
                    color: FlameColors.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: bot.replay,
          icon: const Icon(Icons.play_arrow),
          label: Text(AppStrings.listenBack),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: bot.askAgain,
                child: const Text(AppStrings.askAgain),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  bot.stopAudio();
                  Navigator.of(context).pop();
                },
                child: const Text(AppStrings.backToLesson),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.bot});
  final VoiceBotController bot;

  @override
  Widget build(BuildContext context) {
    final micDenied = bot.mic != MicPermissionState.granted;
    return RecoveryView(
      message: bot.errorMessage ??
          'FLAME could not hear you. Please try again.',
      hint: micDenied ? 'FLAME needs the microphone.' : null,
      icon: micDenied ? Icons.mic_off : Icons.sentiment_satisfied_alt,
      onRetry: micDenied
          ? null
          : () => bot.askAgain(),
      onAlternative: () => bot.askAgain(),
      alternativeLabel: micDenied ? AppStrings.typeQuestion : AppStrings.newQuestion,
    );
  }
}

Future<void> _askTyped(BuildContext context, VoiceBotController bot) async {
  final controller = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ask FLAME'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Type your question'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('Ask'),
        ),
      ],
    ),
  );
  if (text != null && text.trim().isNotEmpty) {
    await bot.answer(text.trim());
  }
}

class _LabeledCard extends StatelessWidget {
  const _LabeledCard({
    required this.label,
    required this.icon,
    required this.child,
    this.accent = FlameColors.ember,
  });

  final String label;
  final IconData icon;
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FlameColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class StatusChipInline extends StatelessWidget {
  const StatusChipInline({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        gradient: FlameColors.flameGradient,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}