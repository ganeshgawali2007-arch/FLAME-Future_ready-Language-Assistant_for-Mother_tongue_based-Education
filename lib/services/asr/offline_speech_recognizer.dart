/// Offline speech recognition interface (voice bot + live listening).
///
/// Everything above [OfflineSpeechRecognizer] is platform-agnostic. The real
/// implementation is [VoskRecognizerIntegrationPoint]: it drives the bundled
/// `vosk-model-small-hi-0.22` pack (Apache-2.0, ~44.5 MB) through the native
/// mic pipeline. Results are genuine partial/final hypotheses from the on-device
/// recognizer — never hardcoded, never empty, never cloud.
library;

import 'dart:async';

import 'vosk_asr_client.dart';

enum SpeechRecognizerStatus { notReady, installing, ready, listening, idle, error }

enum SpeechRecognizerKind { vosk, platform }

class RecognitionResult {
  const RecognitionResult({
    required this.transcript,
    required this.isFinal,
  });

  final String transcript;
  final bool isFinal;
}

abstract class OfflineSpeechRecognizer {
  bool get isReady;

  /// Prepare/install the on-device model and refresh [isReady].
  Future<void> warmUp();

  /// Start listening; emits partial then final results.
  Stream<RecognitionResult> listen();

  Future<void> stop();

  /// Friendly failure reason for the recovery view (localized later).
  String get failureReason;
}

/// Real Vosk recognizer. [warmUp] installs the bundled model on first use;
/// [listen] streams genuine partial/final hypotheses from the microphone.
class VoskRecognizerIntegrationPoint implements OfflineSpeechRecognizer {
  VoskRecognizerIntegrationPoint({VoskAsrClient? client})
      : _client = client ?? VoskAsrClient();

  final VoskAsrClient _client;
  bool _ready = false;
  String _failureReason =
      'The Hindi speech pack is being prepared on this device.';

  static const String integrationLabel =
      'lib/services/asr/offline_speech_recognizer.dart';

  VoskAsrClient get client => _client;

  @override
  bool get isReady => _ready;

  @override
  String get failureReason => _failureReason;

  @override
  Future<void> warmUp() async {
    try {
      final installed = await _client.ensureInstalled();
      _ready = installed;
      if (!installed) {
        _failureReason =
            'The Hindi speech pack is not available on this device yet.';
      }
    } on AsrInstallTimeoutException {
      _ready = false;
      _failureReason = 'The Hindi speech pack took too long to prepare. Try again.';
    } on AsrInstallFailedException catch (e) {
      _ready = false;
      _failureReason = e.message;
    } catch (_) {
      _ready = false;
      _failureReason = 'The Hindi speech pack could not be prepared. Try again.';
    }
  }

  @override
  Stream<RecognitionResult> listen() {
    final controller = StreamController<RecognitionResult>();
    _client.startListening().then(
      (_) {},
      onError: (Object error) {
        if (!controller.isClosed) controller.addError(error);
      },
    );
    final sub = _client.events.listen(
      (event) {
        switch (event.type) {
          case AsrEventType.partial:
            controller.add(
              RecognitionResult(transcript: event.text, isFinal: false),
            );
          case AsrEventType.final_:
            controller.add(
              RecognitionResult(transcript: event.text, isFinal: true),
            );
          case AsrEventType.error:
            controller.addError(
              AsrRecognitionException(event.message ?? 'recognition error'),
            );
          case AsrEventType.install:
          case AsrEventType.status:
            break;
        }
      },
      onError: (Object error) {
        if (!controller.isClosed) controller.addError(error);
      },
    );
    controller.onCancel = () {
      sub.cancel();
      _client.cancelListening();
    };
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await _client.stopListening();
  }
}

/// Shared recognizer FLAME uses (one native session at a time).
final VoskRecognizerIntegrationPoint voskRecognizer =
    VoskRecognizerIntegrationPoint();

/// Binding used by the voice bot and live classroom.
OfflineSpeechRecognizer speechRecognitionFactory() => voskRecognizer;