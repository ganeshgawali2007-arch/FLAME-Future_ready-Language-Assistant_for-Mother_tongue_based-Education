/// Native bridge for the real on-device Vosk recognizer.
///
/// Talks to `MainActivity.kt` over `flame/asr` (method) and `flame/asr/events`
/// (streaming). The model asset (`assets/models/vosk-model-small-hi-0.22.zip`)
/// is extracted to app storage on first use; every event in [AsrEvent] reports
/// a real recognition state from the mic — this class never fabricates text.
library;

import 'dart:async';

import 'package:flutter/services.dart';

enum AsrState { missing, installing, ready, listening, idle, error }

enum AsrEventType { partial, final_, error, install, status }

class AsrEvent {
  const AsrEvent({
    required this.type,
    this.text = '',
    this.state = '',
    this.message,
  });

  final AsrEventType type;
  final String text;
  final String state;
  final String? message;

  factory AsrEvent.fromMap(Map<Object?, Object?> map) {
    final type = map['type'] as String? ?? '';
    final AsrEventType parsed = switch (type) {
      'partial' => AsrEventType.partial,
      'final' => AsrEventType.final_,
      'error' => AsrEventType.error,
      'install' => AsrEventType.install,
      _ => AsrEventType.status,
    };
    return AsrEvent(
      type: parsed,
      text: (map['text'] as String? ?? '').trim(),
      state: map['state'] as String? ?? '',
      message: map['message'] as String?,
    );
  }
}

class AsrInstallTimeoutException implements Exception {
  const AsrInstallTimeoutException();
}

class AsrInstallFailedException implements Exception {
  const AsrInstallFailedException(this.message);
  final String message;

  @override
  String toString() => 'AsrInstallFailedException: $message';
}

class AsrRecognitionException implements Exception {
  const AsrRecognitionException(this.message);
  final String message;

  @override
  String toString() => 'AsrRecognitionException: $message';
}

class VoskAsrClient {
  VoskAsrClient();

  static const MethodChannel _method = MethodChannel('flame/asr');
  static const EventChannel _events = EventChannel('flame/asr/events');

  final StreamController<AsrEvent> _controller =
      StreamController<AsrEvent>.broadcast();
  StreamSubscription<dynamic>? _sub;
  bool _subscribed = false;

  AsrState _state = AsrState.missing;

  AsrState get state => _state;

  /// Broadcast stream of native recognition events.
  Stream<AsrEvent> get events => _controller.stream;

  static AsrState _parseState(String? s) => switch (s) {
        'ready' => AsrState.ready,
        'installing' => AsrState.installing,
        'listening' => AsrState.listening,
        'idle' => AsrState.idle,
        'error' => AsrState.error,
        _ => AsrState.missing,
      };

  Future<void> _ensureEventLoop() async {
    if (_subscribed) return;
    _subscribed = true;
    _sub = _events.receiveBroadcastStream().listen(
          (dynamic raw) {
            if (raw is Map) {
              final event =
                  AsrEvent.fromMap(raw.cast<Object?, Object?>());
              _state = _parseState(event.state);
              _controller.add(event);
            }
          },
          onError: (Object error) => _controller.addError(error),
        );
  }

  Future<void> _teardownEventLoop() async {
    await _sub?.cancel();
    _sub = null;
    _subscribed = false;
  }

  /// Ensure the model is installed (idempotent). Completes true when the model
  /// directory is on device. Waits up to 90s for the extraction to finish.
  Future<bool> ensureInstalled() async {
    await _ensureEventLoop();
    final initial =
        _parseState(await _method.invokeMethod<String>('install'));
    if (initial == AsrState.ready) return true;

    final completer = Completer<bool>();
    late StreamSubscription<AsrEvent> sub;
    final timer = Timer(const Duration(seconds: 90), () {
      sub.cancel();
      if (!completer.isCompleted) {
        completer.completeError(const AsrInstallTimeoutException());
      }
    });
    sub = _controller.stream.listen((event) {
      if (event.type != AsrEventType.install) return;
      sub.cancel();
      timer.cancel();
      if (!completer.isCompleted) {
        if (event.state == 'error') {
          completer.completeError(
            AsrInstallFailedException(
              event.message ??
                  'The speech pack could not be prepared on this device.',
            ),
          );
        } else {
          completer.complete(event.state == 'installed');
        }
      }
    });
    return completer.future;
  }

  /// Begin streaming recognition. Returns when the native loop started.
  Future<void> startListening() async {
    await _method.invokeMethod<void>('startListening');
  }

  /// Stop recording. True if it was listening.
  Future<bool> stopListening() async {
    return (await _method.invokeMethod<bool>('stopListening')) ?? false;
  }

  Future<void> cancelListening() async {
    await _method.invokeMethod<void>('cancelListening');
  }

  /// Free the native model + recognizer (memory release for low-end devices).
  Future<void> release() async {
    await _method.invokeMethod<void>('release');
    await _teardownEventLoop();
  }
}