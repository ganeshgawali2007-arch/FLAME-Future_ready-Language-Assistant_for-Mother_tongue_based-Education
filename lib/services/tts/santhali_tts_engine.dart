/// Real offline Santhali (Ol Chiki) speech synthesis.
///
/// A Piper-style VITS model (`sat_piper_model.onnx` + config JSON, side-loaded
/// like the NMT pack) runs in ONNX Runtime on Android; audio plays through
/// [AudioTrack] (MUSIC stream, speaker route). This engine NEVER touches
/// flutter_tts or the Hindi system voice: Santhali audio is neural synthesis
/// or an explicit failure — nothing in between.
///
/// Honesty contract mirrors [IndicTrans2Backend]: [isInstalled] is true only
/// after [warmUp] genuinely loaded the native session AND a silent inference
/// probe produced audio-like output. Before that, [synthesize] throws and the
/// pipeline stays on explicit failure.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Side-loaded Santhali voice pack: presence probe + locations.
///
/// NOT bundled in the APK (keeps it lean): the two files (~60.6 MB total) are
/// copied by the user/system into one of the app-accessible directories:
///
///   Android/data/com.flame.flame/files/sat_tts_voice/   (USB / Files / adb)
///   [app files dir]/sat_tts_voice/                      (internal)
///
/// [resolveModelDir] returns a directory only when every required file
/// genuinely exists with a plausible size.
class SatTtsPack {
  SatTtsPack({Future<List<Directory>> Function()? candidateDirs})
      : _candidateDirs = candidateDirs ?? _defaultCandidateDirs;

  final Future<List<Directory>> Function() _candidateDirs;

  static const String dirName = 'sat_tts_voice';

  static const String modelFile = 'sat_piper_model.onnx';
  static const String configFile = 'sat_piper_model.onnx.json';

  /// Minimum plausible sizes: a re-exported pack may differ by bytes, but a
  /// truncated copy is always far below these floors.
  static const Map<String, int> requiredFiles = {
    modelFile: 50 * 1024 * 1024, // ~60.6 MB
    configFile: 1024, // ~3.3 KB JSON
  };

  static const int totalSizeMb = 61;

  static Future<List<Directory>> _defaultCandidateDirs() async {
    final dirs = <Directory>[];
    try {
      final ext = await getExternalStorageDirectories();
      if (ext != null && ext.isNotEmpty) {
        dirs.add(Directory('${ext.first.path}/$dirName'));
      }
    } catch (_) {
      // External app dir unavailable (desktop tests, weird devices).
    }
    try {
      final support = await getApplicationSupportDirectory();
      dirs.add(Directory('${support.path}/$dirName'));
    } catch (_) {
      // Internal dir unavailable.
    }
    return dirs;
  }

  Future<List<Directory>> candidateDirs() => _candidateDirs();

  static List<PackFileAudit> audit(Directory dir) {
    final out = <PackFileAudit>[];
    for (final entry in requiredFiles.entries) {
      final f = File('${dir.path}/${entry.key}');
      var exists = false;
      var size = 0;
      try {
        exists = f.existsSync();
        if (exists) size = f.lengthSync();
      } catch (_) {
        // Unreadable file == not usable.
      }
      out.add(PackFileAudit(
        name: entry.key,
        exists: exists,
        sizeBytes: size,
        minBytes: entry.value,
      ));
    }
    return out;
  }

  static bool isComplete(Directory dir) {
    for (final entry in requiredFiles.entries) {
      final f = File('${dir.path}/${entry.key}');
      if (!f.existsSync()) return false;
      if (f.lengthSync() < entry.value) return false;
    }
    return true;
  }

  Future<String?> resolveModelDir() async {
    for (final dir in await _candidateDirs()) {
      try {
        if (isComplete(dir)) return dir.path;
      } catch (_) {
        // Unreadable dir == not installed; keep probing.
      }
    }
    return null;
  }
}

/// Per-file pack audit record (mirrors the NMT pack audit shape).
class PackFileAudit {
  const PackFileAudit({
    required this.name,
    required this.exists,
    required this.sizeBytes,
    required this.minBytes,
  });

  final String name;
  final bool exists;
  final int sizeBytes;
  final int minBytes;

  bool get ok => exists && sizeBytes >= minBytes;
}

/// Outcome of one native synthesis (+ optional playback) call.
class SanthaliAudioResult {
  const SanthaliAudioResult({
    required this.completed,
    required this.stopped,
    required this.sampleRate,
    required this.durationMs,
    required this.synthMs,
    required this.playMs,
  });

  final bool completed;
  final bool stopped;
  final int sampleRate;
  final int durationMs;
  final int synthMs;
  final int playMs;

  /// True when real audio was produced (played, or deliberately stopped).
  bool get producedAudio => (completed || stopped) && durationMs > 0;

  factory SanthaliAudioResult.fromMap(Map<Object?, Object?> map) =>
      SanthaliAudioResult(
        completed: map['status'] == 'completed',
        stopped: map['status'] == 'stopped',
        sampleRate: (map['sampleRate'] as num?)?.toInt() ?? 0,
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        synthMs: (map['synthMs'] as num?)?.toInt() ?? 0,
        playMs: (map['playMs'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() =>
      'SanthaliAudioResult(completed=$completed stopped=$stopped '
      'sr=$sampleRate durMs=$durationMs synthMs=$synthMs playMs=$playMs)';
}

/// Raised when synthesis is requested but the voice is not installed.
class SanthaliVoiceNotInstalledException implements Exception {
  const SanthaliVoiceNotInstalledException();

  @override
  String toString() =>
      'SanthaliVoiceNotInstalledException: side-load sat_tts_voice pack';
}

/// Raised when the text carries no synthesizable Ol Chiki content.
class SanthaliNoSpeechContentException implements Exception {
  const SanthaliNoSpeechContentException(this.reason);

  final String reason;

  @override
  String toString() => 'SanthaliNoSpeechContentException: $reason';
}

/// Neural Santhali voice over the `flame/sat_tts` platform channel.
class OfflineSanthaliTtsEngine {
  OfflineSanthaliTtsEngine({
    required this.pack,
    required this.modelDirResolver,
    MethodChannel? channel,
  }) : channel = channel ?? const MethodChannel('flame/sat_tts');

  final SatTtsPack pack;
  final Future<String?> Function() modelDirResolver;
  final MethodChannel channel;

  bool _installed = false;
  String? _modelDir;

  bool get isInstalled => _installed;
  String? get modelDir => _modelDir;

  static const String modelName = 'sat-piper-tts (VITS, 16 kHz)';

  /// Ol Chiki block U+1C50–U+1C7F (letters, digits, mu-gahlā marks).
  static bool isOlChikiRune(int rune) => rune >= 0x1C50 && rune <= 0x1C7F;

  /// True when [text] carries at least one Ol Chiki character. Everything
  /// else (Devanagari, Latin, digits outside the block) is refused BEFORE any
  /// inference so the model can never be fed script it was not trained on.
  static bool hasSpeechContent(String text) {
    for (final r in text.runes) {
      if (isOlChikiRune(r)) return true;
    }
    return false;
  }

  /// Probe the pack and load the native session, then prove inference with a
  /// SILENT probe synthesis (no AudioTrack, no uninvited audio). Returns true
  /// only when the model is genuinely usable afterwards.
  Future<bool> warmUp() async {
    final sw = Stopwatch()..start();
    debugPrint('FLAME_SAT WARMUP start');
    final dir = await modelDirResolver();
    debugPrint('FLAME_SAT WARMUP modelDir=${dir ?? "NULL"} '
        '(${sw.elapsedMilliseconds}ms)');
    if (dir == null) {
      _installed = false;
      debugPrint('FLAME_SAT WARMUP FAIL pack unresolved');
      return false;
    }
    for (final a in SatTtsPack.audit(Directory(dir))) {
      debugPrint('FLAME_SAT PACK_AUDIT ${a.name} '
          'exists=${a.exists} bytes=${a.sizeBytes} floor=${a.minBytes} '
          'ok=${a.ok}');
    }
    try {
      final state = await channel.invokeMethod<String>('load', {
        'modelDir': dir,
      }).timeout(const Duration(seconds: 60));
      debugPrint('FLAME_SAT WARMUP native load -> $state '
          '(${sw.elapsedMilliseconds}ms)');
      if (state != 'ready') {
        _installed = false;
        return false;
      }
      // Silent inference probe: proves the session synthesizes without
      // playing anything. Bypasses the installed-guard (warm-up is what
      // establishes it).
      final probe = await _probeText();
      final r = await _synthesizeRaw(probe, play: false);
      debugPrint('FLAME_SAT WARMUP probe $r (${sw.elapsedMilliseconds}ms)');
      if (!r.completed || r.durationMs < 200) {
        debugPrint('FLAME_SAT WARMUP FAIL probe produced no audio');
        _installed = false;
        return false;
      }
    } catch (e) {
      debugPrint('FLAME_SAT WARMUP FAIL exact="$e"');
      _installed = false;
      return false;
    }
    _modelDir = dir;
    _installed = true;
    debugPrint('FLAME_SAT WARMUP READY dir=$dir (${sw.elapsedMilliseconds}ms)');
    return true;
  }

  /// Lazy self-initialization: the voice loads on the first speak request
  /// (mirrors [TranslationBackend.ensureReady]). No-op (true) once already
  /// installed; false when the pack is absent/unreadable.
  Future<bool> ensureReady() async {
    if (_installed) return true;
    return warmUp();
  }

  Future<String> _probeText() async {
    try {
      final t = await channel.invokeMethod<String>('probeText')
          .timeout(const Duration(seconds: 5));
      if (t != null && t.isNotEmpty) return t;
    } catch (_) {
      // Fall through to the built-in fallback.
    }
    return 'ᱥᱟᱱᱛᱟᱲᱤ';
  }

  /// Synthesize [text] and, when [play] is true, play it on the speaker.
  /// Returns when playback completes or is stopped. Throws
  /// [SanthaliVoiceNotInstalledException] when not installed and
  /// [SanthaliNoSpeechContentException] when the text has no Ol Chiki.
  Future<SanthaliAudioResult> synthesize(
    String text, {
    bool play = true,
  }) async {
    if (!_installed) {
      throw const SanthaliVoiceNotInstalledException();
    }
    return _synthesizeRaw(text, play: play);
  }

  /// Shared synthesis path without the installed-guard (used by the warm-up
  /// probe, which is what establishes readiness).
  Future<SanthaliAudioResult> _synthesizeRaw(
    String text, {
    bool play = true,
  }) async {
    if (text.trim().isEmpty) {
      throw const SanthaliNoSpeechContentException('empty text');
    }
    if (!hasSpeechContent(text)) {
      throw const SanthaliNoSpeechContentException(
          'no Ol Chiki content (refusing non-Santhali script)');
    }
    final sw = Stopwatch()..start();
    debugPrint('FLAME_SAT SYNTH start chars=${text.length} play=$play');
    try {
      final map = await channel.invokeMethod<Map<Object?, Object?>>(
        'synthesize',
        {'text': text, 'play': play},
      ).timeout(const Duration(seconds: 120), onTimeout: () {
        unawaited(stop());
        throw TimeoutException('Santhali synthesis timed out');
      });
      if (map == null) {
        throw StateError('sat_tts synthesize returned null');
      }
      final r = SanthaliAudioResult.fromMap(map);
      debugPrint('FLAME_SAT SYNTH done $r (channelMs=${sw.elapsedMilliseconds})');
      return r;
    } on PlatformException catch (e) {
      debugPrint('FLAME_SAT SYNTH FAIL ${e.code} ${e.message}');
      throw StateError('Santhali synthesis failed (${e.code}): ${e.message}');
    }
  }

  /// Best-effort stop of an in-flight utterance. Bounded; never throws.
  Future<void> stop() async {
    try {
      await channel.invokeMethod<void>('stop')
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    } catch (_) {
      // Teardown path: nothing to report.
    }
  }

  /// Immediate best-effort stop for teardown paths. Unlike [stop] it never
  /// schedules a timeout timer (unmounting the tree must not leave fake-async
  /// timers behind in widget tests; on a real device both behave the same).
  Future<void> stopNow() async {
    try {
      await channel.invokeMethod<void>('stop');
    } catch (_) {
      // Teardown: nothing to report.
    }
  }

  /// Release the native session (pack data stays on device).
  Future<void> release() async {
    try {
      await channel.invokeMethod<void>('release')
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (_) {
      // Best-effort release; native teardown is idempotent.
    }
    _installed = false;
  }
}
