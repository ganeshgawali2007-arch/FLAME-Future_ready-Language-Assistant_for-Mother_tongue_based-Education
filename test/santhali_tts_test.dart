import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/enums.dart';
import 'package:flame/services/audio/audio_queue.dart';
import 'package:flame/services/tts/offline_tts.dart';
import 'package:flame/services/tts/santhali_tts_engine.dart';

/// Unit coverage for the real offline Santhali voice (Phase 17):
/// pack audit, script validation, engine state machine over a mocked
/// `flame/sat_tts` channel, routing in [OfflineTextToSpeech] (including the
/// explicit-refusal path that never touches the Hindi voice), and AudioQueue
/// integration for sequential Santhali playback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const satChannel = MethodChannel('flame/sat_tts');

  Map<String, Object?> okResult({
    String status = 'completed',
    int durationMs = 900,
  }) =>
      <String, Object?>{
        'status': status,
        'sampleRate': 16000,
        'durationMs': durationMs,
        'synthMs': 120,
        'playMs': 800,
      };

  void mockSat(Future<Object?> Function(MethodCall call) handler) {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(satChannel, handler);
  }

  void unmockSat() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(satChannel, null);
  }

  Future<Object?> healthyHandler(MethodCall call) async {
    switch (call.method) {
      case 'load':
        return 'ready';
      case 'probeText':
        return 'ᱥᱟᱱᱛᱟᱲᱤ';
      case 'synthesize':
        return okResult();
      case 'stop':
      case 'release':
        return null;
      default:
        return null;
    }
  }

  OfflineSanthaliTtsEngine engineWith({
    Future<String?> Function()? resolver,
    SatTtsPack? pack,
  }) =>
      OfflineSanthaliTtsEngine(
        pack: pack ?? SatTtsPack(candidateDirs: () async => <Directory>[]),
        modelDirResolver: resolver ?? (() async => null),
      );

  /// Plausible-size config JSON (the real one is ~3.3 KB; floors reject
  /// anything under 1 KB like a truncated copy would be).
  final realisticConfig = '{"phoneme_id_map":{},"pad":"${'x' * 2048}"}';

  group('SatTtsPack', () {
    test('complete pack passes audit', () async {
      final dir =
          await Directory.systemTemp.createTemp('sat_pack_complete');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/${SatTtsPack.modelFile}')
          .writeAsBytes(List<int>.filled(52 * 1024 * 1024, 7));
      await File('${dir.path}/${SatTtsPack.configFile}')
          .writeAsString(realisticConfig);
      final audit = SatTtsPack.audit(dir);
      expect(audit.every((a) => a.ok), isTrue);
      expect(SatTtsPack.isComplete(dir), isTrue);
    });

    test('missing file fails audit', () async {
      final dir = await Directory.systemTemp.createTemp('sat_pack_missing');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/${SatTtsPack.modelFile}')
          .writeAsBytes(List<int>.filled(52 * 1024 * 1024, 7));
      expect(SatTtsPack.isComplete(dir), isFalse);
      final audit = SatTtsPack.audit(dir);
      expect(audit.where((a) => a.ok).length, 1);
    });

    test('truncated model fails audit', () async {
      final dir = await Directory.systemTemp.createTemp('sat_pack_trunc');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/${SatTtsPack.modelFile}')
          .writeAsBytes(List<int>.filled(1024, 7));
      await File('${dir.path}/${SatTtsPack.configFile}')
          .writeAsString(realisticConfig);
      expect(SatTtsPack.isComplete(dir), isFalse);
    });

    test('resolver picks the complete candidate', () async {
      final bad = await Directory.systemTemp.createTemp('sat_cand_bad');
      final good = await Directory.systemTemp.createTemp('sat_cand_good');
      addTearDown(() => bad.delete(recursive: true));
      addTearDown(() => good.delete(recursive: true));
      await File('${good.path}/${SatTtsPack.modelFile}')
          .writeAsBytes(List<int>.filled(52 * 1024 * 1024, 7));
      await File('${good.path}/${SatTtsPack.configFile}')
          .writeAsString(realisticConfig);
      final pack = SatTtsPack(candidateDirs: () async => [bad, good]);
      expect(await pack.resolveModelDir(), good.path);
    });

    test('resolver returns null when nothing is complete', () async {
      final pack = SatTtsPack(candidateDirs: () async => <Directory>[]);
      expect(await pack.resolveModelDir(), isNull);
    });
  });

  group('script validation', () {
    test('Ol Chiki accepted, boundaries exact', () {
      expect(OfflineSanthaliTtsEngine.isOlChikiRune(0x1C50), isTrue);
      expect(OfflineSanthaliTtsEngine.isOlChikiRune(0x1C7F), isTrue);
      expect(OfflineSanthaliTtsEngine.isOlChikiRune(0x1C4F), isFalse);
      expect(OfflineSanthaliTtsEngine.isOlChikiRune(0x1C80), isFalse);
      expect(OfflineSanthaliTtsEngine.isOlChikiRune(0x0939), isFalse);
      expect(OfflineSanthaliTtsEngine.hasSpeechContent('ᱥᱟᱱᱛᱟᱲᱤ'),
          isTrue);
      expect(OfflineSanthaliTtsEngine.hasSpeechContent('ᱥᱩᱯᱷᱟᱨ ᱵᱤᱨᱟᱹ'),
          isTrue);
    });

    test('non-Ol Chiki refused', () {
      expect(OfflineSanthaliTtsEngine.hasSpeechContent('नमस्ते'), isFalse);
      expect(OfflineSanthaliTtsEngine.hasSpeechContent('hello 123'), isFalse);
      expect(OfflineSanthaliTtsEngine.hasSpeechContent('   '), isFalse);
      expect(OfflineSanthaliTtsEngine.hasSpeechContent(''), isFalse);
    });
  });

  group('OfflineSanthaliTtsEngine', () {
    test('warmUp succeeds on healthy native side', () async {
      mockSat(healthyHandler);
      addTearDown(unmockSat);
      final e = engineWith(resolver: () async => '/fake/dir');
      expect(await e.warmUp(), isTrue);
      expect(e.isInstalled, isTrue);
      expect(e.modelDir, '/fake/dir');
    });

    test('warmUp false when pack unresolved', () async {
      var calls = 0;
      mockSat((call) async {
        calls++;
        return null;
      });
      addTearDown(unmockSat);
      final e = engineWith(resolver: () async => null);
      expect(await e.warmUp(), isFalse);
      expect(e.isInstalled, isFalse);
      expect(calls, 0);
    });

    test('warmUp false when native load fails', () async {
      mockSat((call) async {
        if (call.method == 'load') {
          throw PlatformException(code: 'LOAD_ERROR', message: 'nope');
        }
        return null;
      });
      addTearDown(unmockSat);
      final e = engineWith(resolver: () async => '/fake/dir');
      expect(await e.warmUp(), isFalse);
      expect(e.isInstalled, isFalse);
    });

    test('warmUp false when probe produces no audio', () async {
      mockSat((call) async {
        switch (call.method) {
          case 'load':
            return 'ready';
          case 'probeText':
            return 'ᱥᱟᱱᱛᱟᱲᱤ';
          case 'synthesize':
            return okResult(durationMs: 0);
          default:
            return null;
        }
      });
      addTearDown(unmockSat);
      final e = engineWith(resolver: () async => '/fake/dir');
      expect(await e.warmUp(), isFalse);
      expect(e.isInstalled, isFalse);
    });

    test('synthesize parses result and stop/release call channel',
        () async {
      final seen = <String>[];
      mockSat((call) async {
        seen.add(call.method);
        return healthyHandler(call);
      });
      addTearDown(unmockSat);
      final e = engineWith(resolver: () async => '/fake/dir');
      expect(await e.warmUp(), isTrue);
      final r = await e.synthesize('ᱥᱟᱱᱛᱟᱲᱤ');
      expect(r.completed, isTrue);
      expect(r.stopped, isFalse);
      expect(r.sampleRate, 16000);
      expect(r.durationMs, 900);
      expect(r.producedAudio, isTrue);
      await e.stop();
      await e.release();
      expect(e.isInstalled, isFalse);
      expect(seen, containsAll(['load', 'synthesize', 'stop', 'release']));
    });

    test('synthesize throws when not installed', () async {
      unmockSat();
      final e = engineWith(resolver: () async => null);
      expect(
        () => e.synthesize('ᱥᱟᱱᱛᱟᱲᱤ'),
        throwsA(isA<SanthaliVoiceNotInstalledException>()),
      );
    });

    test('ensureReady warms lazily and is a no-op when installed', () async {
      mockSat(healthyHandler);
      addTearDown(unmockSat);
      final e = engineWith(resolver: () async => '/fake/dir');
      expect(await e.ensureReady(), isTrue);
      expect(e.isInstalled, isTrue);
      expect(await e.ensureReady(), isTrue);
    });

    test('synthesize refuses empty and non-Ol Chiki text', () async {
      mockSat(healthyHandler);
      addTearDown(unmockSat);
      final e = engineWith(resolver: () async => '/fake/dir');
      expect(await e.warmUp(), isTrue);
      expect(
        () => e.synthesize('   '),
        throwsA(isA<SanthaliNoSpeechContentException>()),
      );
      expect(
        () => e.synthesize('नमस्ते'),
        throwsA(isA<SanthaliNoSpeechContentException>()),
      );
    });

    test('SanthaliAudioResult.fromMap handles stopped + producedAudio',
        () {
      final stopped = SanthaliAudioResult.fromMap(<Object?, Object?>{
        'status': 'stopped',
        'sampleRate': 16000,
        'durationMs': 400,
        'synthMs': 100,
        'playMs': 350,
      });
      expect(stopped.stopped, isTrue);
      expect(stopped.completed, isFalse);
      expect(stopped.producedAudio, isTrue);
      final silent = SanthaliAudioResult.fromMap(<Object?, Object?>{
        'status': 'completed',
        'sampleRate': 16000,
        'durationMs': 0,
        'synthMs': 50,
        'playMs': 0,
      });
      expect(silent.producedAudio, isFalse);
    });
  });

  group('OfflineTextToSpeech Santhali routing', () {
    test('refuses explicitly without an engine (never Hindi)', () async {
      final tts = OfflineTextToSpeech();
      addTearDown(tts.dispose);
      expect(tts.isSanthaliReady, isFalse);
      final ok =
          await tts.speak('ᱥᱟᱱᱛᱟᱲᱤ', language: AppLanguage.santhali);
      expect(ok, isFalse);
      expect(tts.lastFailureReason, TtsFailure.santhaliVoiceMissing);
      expect(tts.isSpeaking, isFalse);
    });

    test('routes to the neural engine when installed', () async {
      mockSat(healthyHandler);
      addTearDown(unmockSat);
      final engine = engineWith(resolver: () async => '/fake/dir');
      expect(await engine.warmUp(), isTrue);
      final tts = OfflineTextToSpeech(santhaliTts: engine);
      addTearDown(tts.dispose);
      expect(tts.isSanthaliReady, isTrue);
      final ok =
          await tts.speak('ᱥᱟᱱᱛᱟᱲᱤ', language: AppLanguage.santhali);
      expect(ok, isTrue);
      expect(tts.lastFailureReason, TtsFailure.none);
      expect(tts.isSpeaking, isFalse);
    });

    test('engine failure surfaces as engineError, not Hindi audio',
        () async {
      // Warm-up probe (play=false) succeeds so the engine installs; the
      // later audible synthesis fails like a wedged runtime would.
      var calls = 0;
      mockSat((call) async {
        switch (call.method) {
          case 'load':
            return 'ready';
          case 'probeText':
            return 'ᱥᱟᱱᱛᱟᱲᱤ';
          case 'synthesize':
            calls++;
            if ((call.arguments as Map)['play'] == false) {
              return okResult();
            }
            throw PlatformException(code: 'SYNTH_ERROR', message: 'boom');
          default:
            return null;
        }
      });
      addTearDown(unmockSat);
      final engine = engineWith(resolver: () async => '/fake/dir');
      expect(await engine.warmUp(), isTrue);
      final tts = OfflineTextToSpeech(santhaliTts: engine);
      addTearDown(tts.dispose);
      final ok =
          await tts.speak('ᱥᱟᱱᱛᱟᱲᱤ', language: AppLanguage.santhali);
      expect(ok, isFalse);
      expect(tts.lastFailureReason, TtsFailure.engineError);
    });
  });

  group('AudioQueue with Santhali speaker', () {
    test('two Santhali utterances play sequentially, no overlap', () async {
      final spoken = <String>[];
      var concurrent = 0;
      var maxConcurrent = 0;
      final queue = AudioQueue((text, language) async {
        expect(language, AppLanguage.santhali);
        concurrent++;
        maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        spoken.add(text);
        concurrent--;
        return true;
      });
      addTearDown(queue.dispose);
      queue.enqueue('ᱥᱟᱱᱛᱟᱲᱤ', language: AppLanguage.santhali);
      queue.enqueue('ᱥᱩᱯᱷᱟᱨ ᱵᱤᱨᱟᱹ', language: AppLanguage.santhali);
      for (var i = 0; i < 100 && queue.hasPending; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(spoken, ['ᱥᱟᱱᱛᱟᱲᱤ', 'ᱥᱩᱯᱷᱟᱨ ᱵᱤᱨᱟᱹ']);
      expect(maxConcurrent, 1);
      expect(queue.hasPending, isFalse);
    });

    test('failed Santhali job is marked with a message', () async {
      final queue = AudioQueue((text, language) async => false);
      addTearDown(queue.dispose);
      queue.enqueue('ᱥᱟᱱᱛᱟᱲᱤ', language: AppLanguage.santhali);
      for (var i = 0; i < 100 && queue.hasPending; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(queue.jobs.single.state, AudioJobState.failed);
      expect(queue.jobs.single.failureMessage, isNotEmpty);
    });

    test('clear interrupts and cancels queued jobs', () async {      var interrupts = 0;
      final queue = AudioQueue(
        (text, language) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return true;
        },
        interrupt: () async {
          interrupts++;
        },
      );
      addTearDown(queue.dispose);
      queue.enqueue('ᱥᱟᱱᱛᱟᱲᱤ', language: AppLanguage.santhali);
      queue.enqueue('ᱥᱩᱯᱷᱟᱨ ᱵᱤᱨᱟᱹ', language: AppLanguage.santhali);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await queue.clear();
      expect(interrupts, 1);
      expect(
        queue.jobs
            .where((j) => j.state == AudioJobState.queued)
            .isEmpty,
        isTrue,
      );
    });

    test('classroom wiring: queue drains through real tts.speak', () async {
      // Exactly how ClassroomController and VoiceBotController build their
      // queues: (text, language) => tts.speak(text, language: language).
      mockSat(healthyHandler);
      addTearDown(unmockSat);
      final engine = engineWith(resolver: () async => '/fake/dir');
      expect(await engine.warmUp(), isTrue);
      final tts = OfflineTextToSpeech(santhaliTts: engine);
      addTearDown(tts.dispose);
      final queue = AudioQueue(
        (text, language) => tts.speak(text, language: language),
        interrupt: () => tts.stopQuiet(),
      );
      addTearDown(queue.dispose);
      queue.enqueue('ᱥᱟᱱᱛᱟᱲᱤ', language: AppLanguage.santhali);
      queue.enqueue('ᱥᱩᱯᱷᱟᱨ ᱵᱤᱨᱟᱹ', language: AppLanguage.santhali);
      for (var i = 0; i < 200 && queue.hasPending; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(queue.hasPending, isFalse);
      expect(
        queue.jobs.every((j) => j.state == AudioJobState.done),
        isTrue,
      );
    });
  });
}
