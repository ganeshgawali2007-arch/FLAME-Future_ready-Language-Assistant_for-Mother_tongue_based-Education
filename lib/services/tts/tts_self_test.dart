/// Debug-only, on-device Hindi TTS self-test.
///
/// Triggered by a flag file (`tts_selftest.flag`) in the app-external files
/// dir AND kDebugMode — release builds and normal debug launches are never
/// affected.
///
/// flutter_tts configures ONE shared method channel per process
/// (`MethodChannel('flutter_tts')`), so creating a second [FlutterTts] would
/// overwrite the production instance's event handlers and break every speak
/// callback. This test therefore drives THE PRODUCTION [OfflineTextToSpeech]
/// instance for everything: engine / voice probes AND every speech trial go
/// through the exact object the voice bot, classroom and listen-back use.
///
/// Evidence: engine + hi-IN availability, per-utterance speak outcome with
/// start latency and playback time, stop mid-speech, replay, a five-sentence
/// sequence, the honest v raw readiness contrast, and the explicit Santhali
/// refusal. Every line is written to `tts_selftest_result.txt` in the
/// app-external files dir so the evidence survives adb/USB flakiness and the
/// app process.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/enums.dart';
import 'offline_tts.dart';

class TtsSelfTest {
  TtsSelfTest._();

  static const String flagName = 'tts_selftest.flag';
  static const String resultName = 'tts_selftest_result.txt';

  /// Directive device matrix: T1 short, T2 and T3 directive sentences.
  static const List<String> sentences = [
    'नमस्ते',
    'सुप्रभात बच्चों।',
    'आज हम पौधों के बारे में सीखेंगे।',
  ];

  /// Five sequential-sentence run (matrix T6). T4 uses the long sentence so
  /// the mid-speech stop actually interrupts real playback.
  static const List<String> sequence = [
    'आज हम पौधों के बारे में सीखेंगे।',
    'अपनी किताब खोलो।',
    'ध्यान से सुनो।',
    'यह बहुत अच्छा है।',
    'क्या तुमने पौधे देखे?',
  ];

  static const String stopSentence = 'आज हम पौधों के बारे में सीखेंगे।';

  /// Real Santhali (Ol Chiki) test utterances — every string below is either
  /// a directive phrase (host-verified), a project lexicon entry
  /// (assets/fln/fln_lexicon.json ol_chiki), or verbatim NMT model output
  /// from prior on-device runs. Nothing invented.
  static const List<String> santhaliSentences = [
    'ᱥᱟᱱᱛᱟᱲᱤ',
    'ᱥᱩᱯᱷᱟᱨ ᱵᱤᱨᱟᱹ',
    'ᱛᱮᱦᱮᱧ ᱟᱵᱚ ᱵᱚ ᱵᱮᱱᱟᱣ',
    'ᱛᱤ ᱟᱹᱨᱩᱵ ᱠᱳᱨᱢᱮ ᱡᱚᱢ',
    'ᱫᱩᱲᱩᱵ ᱢᱮ',
  ];

  /// Longest verified NMT output — used for the Santhali mid-speech stop and
  /// as the translation→TTS intermediate (Phase 15: exact NMT output text).
  static const String santhaliLong =
      'ᱛᱮᱦᱮᱧ ᱟᱢ ᱚᱛᱢᱚᱱ ᱨᱮᱭᱟᱜ ᱠᱟᱛᱷᱟ ᱵᱟᱰᱟᱭ ᱧᱟᱢᱼᱟ ᱾';

  static Future<String?> _externalBase() async {
    List<Directory>? dirs;
    try {
      dirs = await getExternalStorageDirectories();
    } catch (_) {
      dirs = const [];
    }
    if (dirs == null || dirs.isEmpty) return null;
    return dirs.first.path;
  }

  static Future<bool> isArmed() async {
    if (!kDebugMode) return false;
    final base = await _externalBase();
    if (base == null) return false;
    return File('$base/$flagName').existsSync();
  }

  static Future<bool> run({
    required OfflineTextToSpeech tts,
    String? outputDir,
  }) async {
    final base = outputDir ?? await _externalBase();
    final lines = <String>[];
    void emit(String line) {
      debugPrint('FLAME_TTS_SELFTEST $line');
      lines.add(line);
    }

    Future<void> checkpoint(String label) async {
      emit('CHECKPOINT $label');
      await _write(base, resultName, lines);
    }

    var ok = true;
    void flagIf(bool v) {
      if (!v) ok = false;
    }

    final probe = tts.platformTts;

    // Production speech trial: speaks through OfflineTextToSpeech (the real
    // app path), records the start event latency via isSpeaking transitions.
    // Returns the emitted fragment and pass flag.
    Future<({String detail, bool pass})> productionSpeak(
      String label,
      String text, {
      AppLanguage language = AppLanguage.hindi,
    }) async {
      final sw = Stopwatch()..start();
      int? startTick;
      var startTickUsed = false;
      void onTts() {
        if (!startTickUsed && tts.isSpeaking) {
          startTick = sw.elapsedMilliseconds;
          startTickUsed = true;
        }
      }
      tts.addListener(onTts);
      final okSpeech = await tts.speak(text, language: language);
      sw.stop();
      tts.removeListener(onTts);
      final playMs =
          startTick == null ? null : sw.elapsedMilliseconds - startTick!;
      final detail = '$label ok=$okSpeech elapsedMs=${sw.elapsedMilliseconds} '
          'startLatency=${_ms(startTick)} playMs=${_ms(playMs)} '
          'failure=${tts.lastFailureReason.name} '
          'detail="${tts.lastFailureDetail}" isSpeaking=${tts.isSpeaking}';
      return (detail: detail, pass: okSpeech);
    }

    try {
      emit('START');
      try {
        final defaultEngine = await probe.getDefaultEngine;
        emit('DEFAULT_ENGINE $defaultEngine');
      } catch (e) {
        emit('DEFAULT_ENGINE FAIL exactException="$e"');
      }

      try {
        final sw = Stopwatch()..start();
        final engines = await probe.getEngines;
        sw.stop();
        final list = engines == null ? <String>[] : List<String>.from(engines);
        emit('CHANNEL_WARMUP_MS ${sw.elapsedMilliseconds}');
        emit('ENGINES n=${list.length} ${list.join(',')}');
        flagIf(list.isNotEmpty);
      } catch (e) {
        emit('ENGINES FAIL exactException="$e"');
        flagIf(false);
      }

      var setLanguageResult = -1;
      dynamic isLanguageInstalledResult;
      try {
        setLanguageResult = (await probe.setLanguage('hi-IN')) as int? ?? -1;
        emit('SETLANGUAGE hi-IN result=$setLanguageResult');
      } catch (e) {
        emit('SETLANGUAGE FAIL exactException="$e"');
      }
      try {
        isLanguageInstalledResult = await probe.isLanguageInstalled('hi-IN');
        emit('IS_LANG_INSTALLED hi-IN $isLanguageInstalledResult');
      } catch (e) {
        emit('IS_LANG_INSTALLED FAIL exactException="$e"');
      }
      try {
        final langs = await probe.getLanguages;
        final list = langs == null ? <String>[] : List<String>.from(langs);
        final hi =
            list.where((l) => l.toLowerCase().startsWith('hi')).toList();
        emit('LANGS n=${list.length} hi=${hi.join(',')}');
      } catch (e) {
        emit('LANGS FAIL exactException="$e"');
      }
      try {
        final voices = await probe.getVoices;
        final hi = <String>[];
        if (voices != null) {
          for (final v in voices) {
            final map = (v as Map).cast<String, dynamic>();
            final locale = '${map['locale']}';
            if (locale.toLowerCase().startsWith('hi')) {
              hi.add('{name=${map['name']},locale=$locale,'
                  'quality=${map['quality']},latency=${map['latency']},'
                  'network=${map['network_required']}}');
            }
          }
        }
        emit('VOICES_HI n=${hi.length} ${hi.join(' | ')}');
      } catch (e) {
        emit('VOICES_FAIL exactException="$e"');
      }
      await checkpoint('after-probes');

      // Configure the production path the same way the app does, and surface
      // the honest claimed readiness.
      TtsReadiness claimed;
      try {
        claimed = await tts.checkReadiness();
      } catch (e) {
        claimed = TtsReadiness.voiceMissing;
        emit('CHECK_READINESS exactException="$e"');
      }
      final matches = (claimed == TtsReadiness.ready) ==
          (setLanguageResult == 1 && isLanguageInstalledResult == true);
      emit('HONESTY claimed=$claimed setLanguage=$setLanguageResult '
          'isInstalled=$isLanguageInstalledResult match=$matches');

      // T1-T3: production-path speech.
      for (var i = 0; i < sentences.length; i++) {
        final r = await productionSpeak('T${i + 1}', sentences[i]);
        emit('SPEAK ${r.detail}');
        flagIf(r.pass);
      }

      // T4: stop mid-speech on the long sentence.
      try {
        final sw = Stopwatch()..start();
        int? startTick;
        var startTickUsed = false;
        void onTts() {
          if (!startTickUsed && tts.isSpeaking) {
            startTick = sw.elapsedMilliseconds;
            startTickUsed = true;
          }
        }

        tts.addListener(onTts);
        final pending = tts.speak(stopSentence);
        while (startTick == null && sw.elapsedMilliseconds < 10000) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        final stopStart = sw.elapsedMilliseconds;
        await tts.stop();
        final okStopped = await pending.timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );
        sw.stop();
        tts.removeListener(onTts);
        emit('T4_STOP started=${startTick != null} '
            'stoppedAt=${_ms(stopStart)} speakResolved=$okStopped '
            'resolveLatencyMs=${sw.elapsedMilliseconds - stopStart} '
            'isSpeaking=${tts.isSpeaking}');
        flagIf(startTick != null && okStopped);
      } catch (e) {
        emit('T4_STOP FAIL exactException="$e"');
        flagIf(false);
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));

      // T5: replay.
      final r5 = await productionSpeak('T5_REPLAY', sentences[1]);
      emit('SPEAK ${r5.detail}');
      flagIf(r5.pass);

      // T6: five sequential sentences.
      try {
        final sw = Stopwatch()..start();
        var seqPass = true;
        for (var i = 0; i < sequence.length; i++) {
          final r = await productionSpeak('T6_$i', sequence[i]);
          emit('SPEAK ${r.detail}');
          if (!r.pass) seqPass = false;
        }
        sw.stop();
        emit('T6_SEQUENCE n=${sequence.length} totalMs=${sw.elapsedMilliseconds}');
        flagIf(seqPass);
      } catch (e) {
        emit('T6_SEQUENCE FAIL exactException="$e"');
        flagIf(false);
      }

      // Santhali: real neural voice when the pack is installed and probed;
      // explicit refusal (never a wrong-voice read-aloud) otherwise. The
      // voice lazy-loads here exactly like production use does.
      final satReady = await tts.ensureSanthaliReady();
      emit('SANTHALI engine=${satReady ? 'ready' : 'missing'}');
      if (satReady) {
        for (var i = 0; i < santhaliSentences.length; i++) {
          final r = await productionSpeak(
            'SAT_$i',
            santhaliSentences[i],
            language: AppLanguage.santhali,
          );
          emit('SPEAK ${r.detail}');
          flagIf(r.pass);
        }
        // Negative: Devanagari through the Santhali path must be refused,
        // never synthesized as garbage.
        final negOk = await tts.speak('नमस्ते', language: AppLanguage.santhali);
        emit('SAT_NEGDEV ok=$negOk failure=${tts.lastFailureReason.name} '
            'detail="${tts.lastFailureDetail}"');
        flagIf(!negOk);
        // Stop mid-PLAYBACK (not just mid-inference) on the long NMT output:
        // wait until inference is done (~150ms) and audible playback is
        // underway, then stop and require an orderly, fast resolution.
        try {
          final sw = Stopwatch()..start();
          int? startTick;
          var startTickUsed = false;
          void onTts() {
            if (!startTickUsed && tts.isSpeaking) {
              startTick = sw.elapsedMilliseconds;
              startTickUsed = true;
            }
          }
          tts.addListener(onTts);
          final pending =
              tts.speak(santhaliLong, language: AppLanguage.santhali);
          while (startTick == null && sw.elapsedMilliseconds < 10000) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          // Inference takes ~150ms for this sentence; 800ms lands inside the
          // ~1900ms audible playback.
          while (sw.elapsedMilliseconds < 800) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          final stopStart = sw.elapsedMilliseconds;
          await tts.stop();
          final okStopped = await pending.timeout(
            const Duration(seconds: 5),
            onTimeout: () => false,
          );
          sw.stop();
          tts.removeListener(onTts);
          emit('SAT_STOP started=${startTick != null} '
              'stoppedAt=${_ms(stopStart)} speakResolved=$okStopped '
              'resolveLatencyMs=${sw.elapsedMilliseconds - stopStart} '
              'isSpeaking=${tts.isSpeaking}');
          flagIf(startTick != null && okStopped);
        } catch (e) {
          emit('SAT_STOP FAIL exactException="$e"');
          flagIf(false);
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final replay = await productionSpeak(
          'SAT_REPLAY',
          santhaliLong,
          language: AppLanguage.santhali,
        );
        emit('SPEAK ${replay.detail}');
        flagIf(replay.pass);
      } else {
        final saOk = await tts.speak('सरमा', language: AppLanguage.santhali);
        emit('SANTHALI engine=missing ok=$saOk '
            'failure=${tts.lastFailureReason.name} '
            'detail="${tts.lastFailureDetail}"');
        flagIf(!saOk);
      }

      emit('DONE ok=$ok');
    } catch (e) {
      ok = false;
      emit('DONE ok=false exactException="$e"');
    } finally {
      await _write(base, resultName, lines);
    }
    return ok;
  }

  static String _ms(int? v) => v == null ? 'n/a' : '$v ms';

  static Future<void> _write(
      String? dir, String name, List<String> lines) async {
    if (dir == null) {
      debugPrint('FLAME_TTS_SELFTEST RESULT_WRITE_SKIP no external dir');
      return;
    }
    try {
      final f = File('$dir/$name');
      await f.writeAsString('${lines.join('\n')}\n');
      debugPrint('FLAME_TTS_SELFTEST WROTE $dir/$name (${lines.length} lines)');
    } catch (e) {
      debugPrint('FLAME_TTS_SELFTEST RESULT_WRITE_FAILED exact="$e"');
    }
  }
}