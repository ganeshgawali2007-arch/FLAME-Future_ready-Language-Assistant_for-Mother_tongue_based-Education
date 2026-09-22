import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flame/services/asr/offline_speech_recognizer.dart';

/// On-device ASR proof: drives the real Vosk recognizer through the microphone
/// and feeds it genuine acoustic speech by playing a Hindi phrase aloud through
/// the device's own TTS engine (speaker -> mic). Everything is real: the native
/// model load, the AudioRecord capture, and the decoded hypotheses.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const phrase = 'नमस्ते आज हम पौधों के बारे में सीखेंगे';

  testWidgets('FLAME on-device: real Vosk Hindi recognition from mic',
      (tester) async {
    await tester.runAsync(() async {
      void log(String m) => debugPrint('FLAME_ASR $m');

      final rec = VoskRecognizerIntegrationPoint();
      log('step=warmUp');
      await rec.warmUp().timeout(const Duration(seconds: 60));
      log('ready=${rec.isReady} reason="${rec.failureReason}"');
      expect(rec.isReady, isTrue,
          reason: 'Vosk model must install/load: ${rec.failureReason}');

      final partials = <String>[];
      final finals = <String>[];
      final errors = <Object>[];

      log('step=listen');
      final sub = rec.listen().listen(
        (r) {
          if (r.transcript.isEmpty) return;
          if (r.isFinal) {
            finals.add(r.transcript);
            log('FINAL "${r.transcript}"');
          } else {
            partials.add(r.transcript);
            log('PARTIAL "${r.transcript}"');
          }
        },
        onError: (Object e) {
          errors.add(e);
          log('STREAM_ERROR "$e"');
        },
      );

      // Give the native AudioRecord loop a moment, then speak through speaker.
      await Future<void>.delayed(const Duration(seconds: 3));
      log('step=tts');

      String ttsState = 'skipped';
      try {
        final tts = FlutterTts();
        await tts.setLanguage('hi-IN').timeout(const Duration(seconds: 8));
        await tts.setSpeechRate(0.45).timeout(const Duration(seconds: 5));
        await tts.setVolume(1.0).timeout(const Duration(seconds: 5));
        final ok = await tts
            .speak(phrase)
            .timeout(const Duration(seconds: 10), onTimeout: () => 0);
        ttsState = 'speak=$ok';
        log('tts $ttsState');
        // Wait for spoken audio to actually reach the mic.
        await Future<void>.delayed(const Duration(seconds: 10));
        await tts.stop().timeout(const Duration(seconds: 5),
            onTimeout: () => null);
      } catch (e) {
        ttsState = 'error=$e';
        log('tts error $e');
      }

      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (finals.isNotEmpty) break;
      }

      log('step=stop');
      await rec.stop().timeout(const Duration(seconds: 10),
          onTimeout: () {});
      await sub.cancel();

      log('partials=${partials.length} finals=${finals.length} '
          'errors=${errors.length} tts=$ttsState');
      for (final p in partials.take(5)) {
        log('partial="$p"');
      }
      for (final f in finals.take(3)) {
        log('final="$f"');
      }
      for (final e in errors.take(3)) {
        log('error="$e"');
      }

      expect(errors, isEmpty, reason: 'Recognition emitted errors: $errors');
      expect(partials.isNotEmpty || finals.isNotEmpty, isTrue,
          reason: 'No real Vosk hypothesis was produced from the microphone.');
    });
  });
}