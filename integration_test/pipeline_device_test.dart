import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:flame/app.dart';
import 'package:flame/models/enums.dart';
import 'package:flame/services/asr/offline_speech_recognizer.dart';
import 'package:flame/services/translation/offline_translation_engine.dart';

/// Full on-device pipeline proof (nothing mocked):
///   device Hindi TTS (speaker) -> real Vosk mic capture -> decoded Hindi text
///   -> real OfflineTranslationEngine (existing) -> IndicTrans2 ONNX tier 2
///   -> decoded target; assert the target contains Ol Chiki (U+1C50–U+1C7F).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const phrase = 'नमस्ते आज हम पौधों के बारे में सीखेंगे';

  testWidgets('FLAME on-device: ASR -> NMT -> Ol Chiki end-to-end',
      (tester) async {
    await tester.pumpWidget(const FlameApp());

    await tester.runAsync(() async {
      void log(String m) => debugPrint('FLAME_PIPE $m');

      final rec = VoskRecognizerIntegrationPoint();
      await rec.warmUp().timeout(const Duration(seconds: 60));
      log('asr_ready=${rec.isReady}');
      expect(rec.isReady, isTrue, reason: rec.failureReason);

      final finals = <String>[];
      final errors = <Object>[];
      final sub = rec.listen().listen(
        (r) {
          if (r.isFinal && r.transcript.trim().isNotEmpty) {
            finals.add(r.transcript.trim());
            log('asr_final="${r.transcript.trim()}"');
          }
        },
        onError: errors.add,
      );

      await Future<void>.delayed(const Duration(seconds: 3));
      final tts = FlutterTts();
      await tts.setLanguage('hi-IN').timeout(const Duration(seconds: 8));
      await tts.setSpeechRate(0.45).timeout(const Duration(seconds: 5));
      await tts.setVolume(1.0).timeout(const Duration(seconds: 5));
      final spoke = await tts
          .speak(phrase)
          .timeout(const Duration(seconds: 10), onTimeout: () => 0);
      log('tts_spoke=$spoke');
      await Future<void>.delayed(const Duration(seconds: 10));
      await tts.stop().timeout(const Duration(seconds: 5), onTimeout: () => null);

      final asrDeadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(asrDeadline) && finals.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await rec.stop().timeout(const Duration(seconds: 10), onTimeout: () {});
      await sub.cancel();

      expect(errors, isEmpty, reason: 'ASR errors: $errors');
      expect(finals, isNotEmpty, reason: 'No real Vosk transcript from mic.');
      final heard = finals.first;

      // Real, existing translation engine wired by the app itself.
      final engine = tester
          .element(find.byType(MaterialApp))
          .read<OfflineTranslationEngine>();
      log('engine_backend=${engine.hasModelBackend}');

      final t0 = DateTime.now();
      final result = await engine
          .translate(heard, source: AppLanguage.hindi, target: AppLanguage.santhali)
          .timeout(const Duration(seconds: 180));
      final ms = DateTime.now().difference(t0).inMilliseconds;

      final target = result.targetText;
      final hasOlChiki = target.runes.any((r) => r >= 0x1C50 && r <= 0x1C7F);
      final hasDevanagari = target.runes.any((r) => r >= 0x0900 && r <= 0x097F);

      log('nmt_source="$heard"');
      log('nmt_target="$target"');
      log('nmt_chars=${target.runes.length} canTranslate=${result.canTranslate} '
          'olChiki=$hasOlChiki devanagari=$hasDevanagari ms=$ms');

      expect(result.canTranslate, isTrue,
          reason: 'Translation produced no target (tier-3 fallback).');
      expect(target.isNotEmpty, isTrue,
          reason: 'Empty target text.');
      expect(hasOlChiki, isTrue,
          reason: 'Target did not contain Ol Chiki (U+1C50–U+1C7F).');
    });
  });
}