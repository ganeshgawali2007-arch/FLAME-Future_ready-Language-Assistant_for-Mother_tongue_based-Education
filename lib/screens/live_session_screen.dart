import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../models/entities.dart';
import '../models/enums.dart';
import '../services/asr/offline_speech_recognizer.dart';
import '../services/classrooms/classroom_controller.dart';
import '../services/offline_status_service.dart';
import '../services/permissions/permission_service.dart';
import '../services/voice/live_session_mic_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_badge.dart';
import '../widgets/recovery_view.dart';
import '../widgets/sanathali_text.dart';

/// Live classroom modes: Listening / Translating / Speaking.
///
/// Today the pipeline runs a real offline round-trip when the speaker uses the
/// typed input or the microphone: speech → Vosk → final Hindi (or Santhali)
/// transcription → corpus translation → target text (+ system TTS when a voice
/// is present). Speech input is wired to the same seam as the voice bot
/// ([LiveSessionMicController]). No cloud anywhere.
class LiveSessionView extends StatefulWidget {
  const LiveSessionView({
    super.key,
    required this.classroom,
    required this.offline,
    this.permissions,
    this.recognizerFactory,
  });

  final ClassroomController classroom;
  final OfflineStatusService offline;
  final PermissionService? permissions;
  final OfflineSpeechRecognizer Function()? recognizerFactory;

  @override
  State<LiveSessionView> createState() => _LiveSessionViewState();
}

class _LiveSessionViewState extends State<LiveSessionView> {
  final TextEditingController _input = TextEditingController();
  bool _busy = false;
  late final LiveSessionMicController _mic;

  @override
  void initState() {
    super.initState();
    _mic = LiveSessionMicController(
      permissions: widget.permissions ?? PermissionService(),
      recognizerFactory: widget.recognizerFactory,
      onFinal: _handleFinal,
    );
    _mic.addListener(_onMicChanged);
    // Rebuild the status chip on audio-queue transitions so "Speaking" is
    // shown only while real TTS playback is occurring (never a fake state
    // when the voice is unavailable — e.g. Santhali enqueue fails fast).
    widget.classroom.audioQueue.addListener(_onMicChanged);
  }

  @override
  void dispose() {
    _mic.removeListener(_onMicChanged);
    widget.classroom.audioQueue.removeListener(_onMicChanged);
    _mic.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onMicChanged() {
    if (mounted) setState(() {});
  }

  /// A recognized FINAL transcript is a turn — submitted through the exact
  /// same path as a typed line so translation + playback stay coherent.
  Future<void> _handleFinal(String text) => _submitText(text);

  Future<void> _speak() => _input.text.trim().isEmpty
      ? Future.value()
      : _submitText(_input.text.trim());

  Future<void> _submitText(String text) async {
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);

    final isTeacher = widget.classroom.isTeacher;
    final speaker = isTeacher ? SpeakerRole.teacher : SpeakerRole.student;
    final source = isTeacher
        ? AppLanguage.hindi
        : AppLanguage.santhali;

    await widget.offline.runOfflineJob(
      () => widget.classroom.processTurn(
        text: text,
        speaker: speaker,
        sourceLanguage: source,
      ),
    );

    if (isTeacher) {
      // Teacher plays the translated (Santhali) line back through the
      // session audio queue (ordered, non-overlapping, interruptible).
      final t = widget.classroom.transcript.lastOrNull();
      if (t != null && t.targetText.isNotEmpty) {
        await widget.offline.runOfflineJob(
          () => widget.classroom.playTurn(t),
        );
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final classroom = widget.classroom;
    final mode = classroom.activeMode;
    final transcript = classroom.transcript;

    return Column(
      children: [
        _modeStatusBar(mode),
        Expanded(
          child: transcript.isEmpty
              ? _emptyState(mode, classroom.isTeacher)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  itemCount: transcript.length,
                  itemBuilder: (context, i) => _UtteranceCard(u: transcript[i]),
                ),
        ),
        _micStatusLine(),
        _speakBar(mode, classroom.isTeacher),
      ],
    );
  }

  Widget _modeStatusBar(LiveMode mode) {
    final listening = _mic.listening;
    // Honest playback state: the "Speaking" tab is a user-selected mode, not
    // proof of audio. Show Speaking only while the audio queue genuinely has
    // an utterance playing; otherwise fall back to Translating/Ready so a
    // missing voice (e.g. Santhali) never displays a fake Speaking state.
    final actuallySpeaking = widget.classroom.audioQueue.isSpeaking;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Row(
        children: [
          StatusChip(
            label: _busy
                ? AppStrings.stateTranslating
                : listening
                    ? AppStrings.stateListening
                    : mode == LiveMode.listening
                        ? AppStrings.stateListening
                        : mode == LiveMode.speaking && actuallySpeaking
                            ? AppStrings.stateSpeaking
                            : AppStrings.stateTranslating,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _busy
                  ? AppStrings.workingOffline
                  : listening
                      ? 'Speak your line...'
                      : AppStrings.stateReady,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: listening ? FlameColors.ember : FlameColors.ready,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Live partial hypothesis or an honest mic failure — visible above the
  /// speak bar, never mixed into the transcript (parts are replaced, only the
  /// FINAL event produces a turn).
  Widget _micStatusLine() {
    final error = _mic.errorMessage;
    if (!_mic.listening && error == null) return const SizedBox.shrink();
    final text = error ?? (_mic.partial.isNotEmpty ? _mic.partial : '');
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontStyle: error == null ? FontStyle.italic : FontStyle.normal,
            fontWeight: FontWeight.w600,
            color: error == null ? FlameColors.inkSoft : FlameColors.ember,
          ),
        ),
      ),
    );
  }

  Widget _emptyState(LiveMode mode, bool isTeacher) {
    final hint = mode == LiveMode.listening
        ? (isTeacher
            ? 'Listening to the class... Speak to translate a line.'
            : 'Listening to your teacher...')
        : mode == LiveMode.translating
            ? 'Translations will appear here, instantly and offline.'
            : 'Speak a line and FLAME will say it in the class language.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode == LiveMode.listening
                  ? Icons.hearing
                  : mode == LiveMode.translating
                      ? Icons.translate
                      : Icons.record_voice_over,
              size: 44,
              color: FlameColors.ember,
            ),
            const SizedBox(height: 12),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: FlameColors.inkSoft),
            ),
            const SizedBox(height: 18),
            RecoveryView(
              message: isTeacher
                  ? 'Type a sentence to do a live round-trip.'
                  : 'Ready when your teacher speaks.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _speakBar(LiveMode mode, bool isTeacher) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !_busy,
                onSubmitted: (_) => _speak(),
                decoration: InputDecoration(
                  hintText: isTeacher
                      ? 'Say a line in Hindi...'
                      : 'Say a line in Santhali...',
                  prefixIcon:
                      const Icon(Icons.edit, size: 20, color: FlameColors.ember),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _busy ? null : _mic.pressMic,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: FlameColors.flameGradient,
                ),
                child: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.6,
                        ),
                      )
                    : _mic.listening
                        ? const Icon(Icons.stop, color: Colors.white, size: 26)
                        : const Icon(Icons.mic, color: Colors.white, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UtteranceCard extends StatelessWidget {
  const _UtteranceCard({required this.u});
  final Utterance u;

  @override
  Widget build(BuildContext context) {
    final isTeacher = u.speaker == SpeakerRole.teacher;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FlameColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: isTeacher ? FlameColors.flameGradient : const LinearGradient(
                  colors: [FlameColors.amber, FlameColors.flame]),
              shape: BoxShape.circle,
            ),
            child: Icon(
              u.speaker == SpeakerRole.student
                  ? Icons.child_care
                  : Icons.person,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.speaker == SpeakerRole.teacher ? 'Teacher' : 'Student',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: FlameColors.ember,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  u.sourceText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: FlameColors.ink,
                  ),
                ),
                if (u.targetText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SanathaliText(
                    u.targetText,
                    style: const TextStyle(
                      fontSize: 14,
                      color: FlameColors.inkSoft,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _LastOrNull<T> on List<T> {
  T? lastOrNull() => isEmpty ? null : last;
}