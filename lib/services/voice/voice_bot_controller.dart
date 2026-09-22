/// Ask FLAME controller — orchestrates the offline voice-bot pipeline.
///
///   idle → listening → understanding → answering → speaking → done
///
/// Speech entry uses [OfflineSpeechRecognizer] (real Vosk Hindi model bundled
/// and extracted on first use). [warmUp] installs the speech pack at init; if
/// it is genuinely unavailable the bot still answers typed questions fully
/// offline and shows the friendly recovery state — never a crash, never a
/// cloud call.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/enums.dart';
import '../asr/offline_speech_recognizer.dart';
import '../audio/audio_queue.dart';
import '../education/educational_engine.dart';
import '../model_manager.dart';
import '../offline_status_service.dart';
import '../permissions/permission_service.dart';
import '../tts/offline_tts.dart';

class VoiceBotController extends ChangeNotifier {
  VoiceBotController({
    required this.engine,
    required this.tts,
    required this.offline,
    required this.permissions,
    this.models,
    OfflineSpeechRecognizer Function()? recognizerFactory,
  }) : _recognizer = (recognizerFactory ?? speechRecognitionFactory)() {
    _queue = AudioQueue(
      (text, language) => tts.speak(text, language: language),
      interrupt: () => tts.stopQuiet(),
    );
  }

  final OfflineEducationalEngine engine;
  final OfflineTextToSpeech tts;
  final OfflineStatusService offline;
  final PermissionService permissions;
  final ModelManagerController? models;
  final OfflineSpeechRecognizer _recognizer;
  late final AudioQueue _queue;
  StreamSubscription<RecognitionResult>? _sub;

  VoiceBotPhase phase = VoiceBotPhase.idle;
  MicPermissionState mic = MicPermissionState.unknown;
  AskFlameResult? result;
  String? questionText;
  String? errorMessage;
  bool speechReady = false;

  bool get speechRecognitionAvailable => _recognizer.isReady;

  AudioQueue get audioQueue => _queue;

  Future<void> init() async {
    mic = await permissions.checkMicrophone();
    // Install/extract the real Hindi speech model and reflect its true state.
    await _recognizer.warmUp();
    await models?.loadModel(FlmModelId.hindiSpeech).catchError((Object _) => false);
    await models?.loadModel(FlmModelId.hindiVoice).catchError((Object _) => false);
    speechReady = _recognizer.isReady;
    notifyListeners();
  }

  /// The in-app permission explainer has confirmed a real grant (the Android
  /// runtime dialog was answered positively). Reflect it immediately so the
  /// voice entry point unlocks on first tap — no restart needed.
  void onMicGranted() {
    mic = MicPermissionState.granted;
    speechReady = _recognizer.isReady;
    notifyListeners();
  }

  /// Push typed / recognized question through the offline pipeline.
  Future<void> answer(String question) async {
    if (question.isEmpty) return;
    questionText = question;
    result = null;
    errorMessage = null;
    phase = VoiceBotPhase.understanding;
    notifyListeners();

    try {
      result = await offline.runOfflineJob(
        () => engine.answer(question, context: offlineContext),
      );
      phase = VoiceBotPhase.answering;
      notifyListeners();
      await speakResult();
    } catch (_) {
      phase = VoiceBotPhase.error;
      errorMessage = 'Couldn\'t prepare an answer. Please try again.';
      notifyListeners();
    }
  }

  LearningContext get offlineContext => const LearningContext(
        classLevel: 'Class 3',
        subject: 'EVS',
        lessonTitle: 'Plants',
        topicTitle: 'How Plants Grow',
      );

  /// Microphone flow. If the on-device speech pack is missing, surfaces the
  /// friendly recovery state instead of a crash.
  Future<void> startListening() async {
    final status = await permissions.requestMicrophone();
    mic = status;
    if (status != MicPermissionState.granted) {
      phase = VoiceBotPhase.error;
      errorMessage = _micError(status);
      notifyListeners();
      return;
    }
    await _recognizer.warmUp();
    speechReady = _recognizer.isReady;
    if (!_recognizer.isReady) {
      phase = VoiceBotPhase.error;
      errorMessage = _recognizer.failureReason;
      notifyListeners();
      return;
    }
    phase = VoiceBotPhase.listening;
    notifyListeners();
    await _sub?.cancel();
    _sub = _recognizer.listen().listen((event) async {
      if (event.isFinal && event.transcript.trim().isNotEmpty) {
        await _sub?.cancel();
        await answer(event.transcript.trim());
      }
    });
  }

  String _micError(MicPermissionState status) => switch (status) {
        MicPermissionState.permanentlyDenied =>
          'Microphone access is turned off for FLAME. Open Android settings to allow it.',
        _ => 'FLAME needs the microphone to hear you. Turn it on to continue.',
      };

  Future<void> speakResult() async {
    final current = result;
    if (current == null) return;
    phase = VoiceBotPhase.speaking;
    notifyListeners();
    _queue.enqueue(current.spokenText);
    // Playback is queued and non-blocking; a playback failure is a
    // recoverable, non-crashing state.
    phase = VoiceBotPhase.done;
    notifyListeners();
  }

  Future<void> replay() async {
    final current = result;
    if (current == null) return;
    phase = VoiceBotPhase.speaking;
    notifyListeners();
    _queue.enqueue(current.spokenText);
    phase = VoiceBotPhase.done;
    notifyListeners();
  }

  Future<void> askAgain() async {
    await _queue.clear();
    questionText = null;
    result = null;
    errorMessage = null;
    phase = VoiceBotPhase.idle;
    notifyListeners();
  }

  Future<void> stopAudio() async {
    await _queue.clear();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _queue.clear();
    tts.stopQuiet();
    super.dispose();
  }
}