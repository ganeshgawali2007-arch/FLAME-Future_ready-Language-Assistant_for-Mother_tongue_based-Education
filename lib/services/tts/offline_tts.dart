/// Offline text-to-speech — honest, language-specific status.
///
///  - Hindi (hi-IN): real Android system TTS, works offline when the device
///    has a Hindi voice installed. Device-dependent.
///  - Santhali (Ol Chiki): real offline neural synthesis (Piper-style VITS
///    ONNX + AudioTrack) once the side-loaded voice pack is installed and
///    probed. FLAME will NOT silently read Santhali text with the Hindi
///    voice: without the pack, Santhali requests fail explicitly.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../models/enums.dart';
import 'santhali_tts_engine.dart';

enum TtsReadiness { ready, engineMissing, voiceMissing }

/// Why the last speak failed, in words the UI can show. Empty when the last
/// attempt succeeded.
enum TtsFailure {
  none,
  santhaliVoiceMissing,
  languageUnavailable,
  startFailed,
  engineHang,
  engineError,
  timeout,
}

class OfflineTextToSpeech extends ChangeNotifier {
  OfflineTextToSpeech({OfflineSanthaliTtsEngine? santhaliTts})
      : _santhaliTts = santhaliTts {
    _tts.setStartHandler(() {
      _speaking = true;
      notifyListeners();
    });
    _tts.setCompletionHandler(() {
      _speaking = false;
      _finish(null);
      notifyListeners();
    });
    _tts.setCancelHandler(() {
      // Interrupted playback is orderly (stop()/clear()), not a failure.
      _speaking = false;
      _finish(null);
      notifyListeners();
    });
    _tts.setErrorHandler((message) {
      _speaking = false;
      _lastFailure = TtsFailure.engineError;
      _lastFailureDetail =
          message == null || '$message'.isEmpty ? 'TTS engine error' : '$message';
      _finish(TtsFailure.engineError);
      notifyListeners();
    });
  }

  final FlutterTts _tts = FlutterTts();
  final OfflineSanthaliTtsEngine? _santhaliTts;
  bool _speaking = false;
  Completer<Object?>? _completer;
  TtsFailure _lastFailure = TtsFailure.none;
  String _lastFailureDetail = '';

  bool get isSpeaking => _speaking;
  TtsFailure get lastFailureReason => _lastFailure;
  String get lastFailureDetail => _lastFailureDetail;
  bool get lastAttemptSucceeded => _lastFailure == TtsFailure.none;

/// The underlying platform instance. Exposed for the debug self-test ONLY:
/// flutter_tts configures ONE shared method channel per process, so a
/// second [FlutterTts] instance would steal this instance's event
/// handlers. Self-tests must drive this same instance.
FlutterTts get platformTts => _tts;

  /// True only when the real offline Santhali voice is loaded and probed.
  /// No Android system voice is ever involved: without the side-loaded VITS
  /// pack this is false and Santhali requests fail explicitly.
  bool get isSanthaliReady => _santhaliTts?.isInstalled ?? false;

  /// Ensure the Santhali voice is loaded (silent warm-up when needed).
  /// Used by the self-test gate and any caller that wants readiness without
  /// speaking yet. Never plays audio itself.
  Future<bool> ensureSanthaliReady() async {
    final engine = _santhaliTts;
    if (engine == null) return false;
    return engine.ensureReady();
  }

  /// Honest engine check, verified by the platform, never assumed.
  ///
  ///  - [TtsReadiness.engineMissing] — no TTS engine app on the device.
  ///  - [TtsReadiness.voiceMissing] — an engine exists but hi-IN is not
  ///    usable (language rejected, or no offline voice data installed).
  ///  - [TtsReadiness.ready] — hi-IN accepted AND offline voice data present.
  Future<TtsReadiness> checkReadiness() async {
    try {
      final engines = await _tts.getEngines
          .timeout(const Duration(seconds: 5), onTimeout: () => <Object?>[]);
      if (engines == null || engines.isEmpty) {
        return TtsReadiness.engineMissing;
      }
      final langOk = await _tts.setLanguage('hi-IN')
              .timeout(const Duration(seconds: 5), onTimeout: () => -1);
      if (langOk != 1) {
        return TtsReadiness.voiceMissing;
      }
      final installed = await _tts.isLanguageInstalled('hi-IN')
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (installed != true) {
        return TtsReadiness.voiceMissing;
      }
      return TtsReadiness.ready;
    } catch (_) {
      return TtsReadiness.voiceMissing;
    }
  }

  /// Speaks [text] in [language].
  ///
  /// Santhali goes exclusively through the real offline neural voice
  /// ([OfflineSanthaliTtsEngine]) — never the Hindi system voice. When no
  /// voice pack is installed the request fails explicitly with
  /// [TtsFailure.santhaliVoiceMissing]. Returns true only when real audio
  /// was produced AND completed (or was deliberately interrupted). Bounded:
  /// a wedged engine can never freeze the calling queue — every await
  /// carries a timeout and the UI state stays truthful.
  Future<bool> speak(
    String text, {
    AppLanguage language = AppLanguage.hindi,
  }) async {
    if (language == AppLanguage.santhali) {
      return _speakSanthali(text);
    }

    final completer = Completer<Object?>();
    _lastFailure = TtsFailure.none;
    _lastFailureDetail = '';

    try {
      // Keep the shared completer detached until the old utterance is fully
      // flushed: a cancel/done from the stop() below must not resolve the
      // future of the utterance we are about to start.
      _completer = null;
      await _tts.stop().timeout(
            const Duration(seconds: 3),
            onTimeout: () => null,
          );
      final langOk = await _tts.setLanguage('hi-IN').timeout(
            const Duration(seconds: 5),
            onTimeout: () => -1,
          );
      if (langOk != 1) {
        _lastFailure = TtsFailure.languageUnavailable;
        _lastFailureDetail =
            'Hindi voice (hi-IN) is not available on this device. '
            'Open Android Settings → Text-to-speech → Install voice data, '
            'then tap Retry.';
        _speaking = false;
        notifyListeners();
        return false;
      }
      _completer = completer;
      final ok = await _tts.speak(text).timeout(
            const Duration(seconds: 15),
            onTimeout: () => 0,
          );
      if (ok != 1) {
        _lastFailure = TtsFailure.startFailed;
        _lastFailureDetail = 'The TTS engine did not start speaking.';
        _speaking = false;
        notifyListeners();
        return false;
      }
      final result = await completer.future
          .timeout(const Duration(seconds: 30), onTimeout: () {
        if (_completer == completer) {
          _completer = null;
        }
        return TtsFailure.engineHang;
      });
      if (result != null) {
        _lastFailure = result as TtsFailure;
        if (_lastFailure == TtsFailure.engineHang) {
          _lastFailureDetail =
              'The TTS engine accepted the request but produced no audio; '
              'playback stopped. Tap Retry to speak again.';
        }
        _speaking = false;
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      _lastFailure = TtsFailure.timeout;
      _lastFailureDetail =
          e is TimeoutException ? 'TTS call timed out.' : '$e';
      _speaking = false;
      notifyListeners();
      return false;
    }
  }

  /// Real Santhali speech via the offline neural voice. Deliberate
  /// interruption (stop/clear) is orderly success, matching the Hindi path.
  /// The voice lazy-loads on first use (like the NMT backend), so a parked
  /// session after the startup probe never blocks real usage.
  Future<bool> _speakSanthali(String text) async {
    _lastFailure = TtsFailure.none;
    _lastFailureDetail = '';
    final engine = _santhaliTts;
    if (engine == null) {
      _lastFailure = TtsFailure.santhaliVoiceMissing;
      _lastFailureDetail =
          'The Santhali voice pack is not installed on this device. '
          'FLAME never reads Santhali text with the Hindi voice.';
      _speaking = false;
      notifyListeners();
      return false;
    }
    final ready = await engine.ensureReady();
    if (!ready) {
      _lastFailure = TtsFailure.santhaliVoiceMissing;
      _lastFailureDetail =
          'The Santhali voice pack is not installed on this device. '
          'FLAME never reads Santhali text with the Hindi voice.';
      _speaking = false;
      notifyListeners();
      return false;
    }
    _speaking = true;
    notifyListeners();
    try {
      final r = await engine.synthesize(text, play: true);
      _speaking = false;
      if (!r.producedAudio) {
        _lastFailure = TtsFailure.engineError;
        _lastFailureDetail =
            'The Santhali voice produced no audio. Tap Retry to speak again.';
        notifyListeners();
        return false;
      }
      notifyListeners();
      return true;
    } on SanthaliNoSpeechContentException catch (e) {
      _lastFailure = TtsFailure.languageUnavailable;
      _lastFailureDetail = '$e';
      _speaking = false;
      notifyListeners();
      return false;
    } on TimeoutException {
      _lastFailure = TtsFailure.timeout;
      _lastFailureDetail = 'Santhali synthesis timed out.';
      _speaking = false;
      notifyListeners();
      return false;
    } catch (e) {
      _lastFailure = TtsFailure.engineError;
      _lastFailureDetail = '$e';
      _speaking = false;
      notifyListeners();
      return false;
    }
  }

  /// Short audible runtime probe for the Settings "Check" path ONLY — never
  /// used at startup or session start, so the app never blurts audio
  /// uninvited. Speaks "नमस्ते" through the full production path and returns
  /// true only when the engine actually starts AND completes the utterance.
  /// A muted stream or missing voice data fails honestly (see
  /// [lastFailureReason]) instead of a silent false-Ready.
  Future<bool> probeSpeakUtterance() =>
      speak('नमस्ते', language: AppLanguage.hindi);

  /// Best-effort stop. The platform channel can be unavailable (or wedged);
  /// playback must never block navigation, so the call is bounded. Stops
  /// both the Hindi system voice and an in-flight Santhali utterance.
  Future<void> stop() async {
    try {
      await _tts.stop().timeout(
            const Duration(seconds: 1),
            onTimeout: () => null,
          );
    } catch (_) {
      _lastFailure = TtsFailure.engineError;
    }
    try {
      await _santhaliTts?.stop();
    } catch (_) {
      // Best-effort; native stop never throws.
    }
    _speaking = false;
    notifyListeners();
  }

  /// Resolves the pending completion future exactly once, if one exists.
  void _finish(Object? error) {
    final c = _completer;
    if (c != null && !c.isCompleted) {
      c.complete(error);
    }
    _completer = null;
  }

  @override
  void dispose() {
    // Teardown path: no timers, no notify; best effort only.
    stopQuiet();
    super.dispose();
  }

  /// Immediate best-effort stop for teardown / queue-interrupt paths.
  ///
  /// Unlike [stop] it never schedules a timeout timer, so unmounting the tree
  /// cannot leave fake-async timers behind. On a real device both behave the
  /// same; here the platform channel may be absent and the call simply never
  /// settles (which is fine — nothing awaits a teardown).
  Future<void> stopQuiet() async {
    try {
      await _tts.stop().catchError((Object _) {});
    } catch (_) {
      // Teardown: nothing to report.
    }
    try {
      await _santhaliTts?.stopNow();
    } catch (_) {
      // Teardown: nothing to report.
    }
  }
}