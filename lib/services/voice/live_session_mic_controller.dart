/// Microphone orchestration for the live classroom speaker.
///
/// Same recognizer seam as the voice bot ([VoiceBotController]) so one native
/// Vosk session is shared. Responsibilities (each enforced here, not in the
/// screen):
///   - permission request first: a denied / permanently-denied state surfaces
///     as an honest message and the mic NEVER enters a fake "listening" state;
///   - partial hypotheses REPLACE the previous one (never appended);
///   - a FINAL result fires exactly one callback ([onFinal]) with the trimmed
  ///     transcript — duplicate finals are ignored;
///   - the previous recognizer subscription is always cancelled before a new
///     one starts, and on [dispose] the active subscription is cancelled.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/enums.dart';
import '../asr/offline_speech_recognizer.dart';
import '../permissions/permission_service.dart';

class LiveSessionMicController extends ChangeNotifier {
  LiveSessionMicController({
    required this.permissions,
    this.onFinal,
    OfflineSpeechRecognizer Function()? recognizerFactory,
  }) : _recognizer = (recognizerFactory ?? speechRecognitionFactory)();

  final PermissionService permissions;
  final OfflineSpeechRecognizer _recognizer;

  /// Invoked exactly once per recognized sentence with the FINAL transcript.
  Future<void> Function(String transcript)? onFinal;

  MicPermissionState mic = MicPermissionState.unknown;
  bool speechReady = false;

  bool _listening = false;
  String _partial = '';
  String? _errorMessage;
  StreamSubscription<RecognitionResult>? _sub;
  bool _finalHandled = false;
  bool _disposed = false;

  /// Notify as long as the controller is still alive (a pending [stop] can
  /// otherwise resume after the owning screen has been disposed).
  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  /// True while capturing audio from the microphone.
  bool get listening => _listening;

  /// Live partial hypothesis (replaces the previous partial, never appends).
  String get partial => _partial;

  /// Friendly reason the mic can't record right now.
  String? get errorMessage => _errorMessage;

  /// One mic press: stop a running capture, otherwise start listening.
  Future<void> pressMic() async {
    if (_listening) {
      await stop();
      return;
    }
    await start();
  }

  /// Surface a real failure instead of a fake listening state.
  void _fail(String message) {
    _listening = false;
    _partial = '';
    _errorMessage = message;
    _emit();
  }

  Future<void> _reachable() async {
    final status = await permissions.requestMicrophone();
    mic = status;
    if (status != MicPermissionState.granted) {
      _fail(_micError(status));
      return;
    }
    _errorMessage = null;
    await _recognizer.warmUp();
    speechReady = _recognizer.isReady;
    if (!_recognizer.isReady) {
      _fail(_recognizer.failureReason);
      return;
    }
  }

  Future<void> start() async {
    await _reachable();
    if (_errorMessage != null && !_listening) return;

    await _sub?.cancel();
    _sub = null;
    _finalHandled = false;
    _listening = true;
    _partial = '';
    _emit();

    _sub = _recognizer.listen().listen(_onEvent, onError: _onError);
  }

  Future<void> stop() async {
    _listening = false;
    _partial = '';
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    unawaited(_recognizer.stop());
    _emit();
  }

  void _onEvent(RecognitionResult event) {
    if (event.isFinal) {
      final text = event.transcript.trim();
      if (text.isEmpty) return;
      // Vosk may re-emit a final for the same utterance; only the first one
      // from a capture session is allowed to produce a turn.
      if (_finalHandled) return;
      _finalHandled = true;
      unawaited(stop());
      final callback = onFinal;
      if (callback != null) unawaited(callback(text));
    } else {
      // Partial hypotheses replace one another — appending them would fake a
      // transcript that never existed.
      if (_partial != event.transcript) {
        _partial = event.transcript;
        _emit();
      }
    }
  }

  void _onError(Object error) {
    _fail("Couldn't hear that clearly. Please try again.");
  }

  @override
  void dispose() {
    _disposed = true;
    final sub = _sub;
    _sub = null;
    sub?.cancel();
    unawaited(_recognizer.stop());
    super.dispose();
  }

  String _micError(MicPermissionState status) => switch (status) {
        MicPermissionState.permanentlyDenied =>
          'Microphone access is turned off for FLAME. Open Android settings to allow it.',
        _ => 'FLAME needs the microphone to hear you. Turn it on to say a line.',
      };
}