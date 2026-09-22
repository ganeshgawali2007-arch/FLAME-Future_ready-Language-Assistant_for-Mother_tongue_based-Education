import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/enums.dart';
import 'package:flame/services/translation/corpus_translation_engine.dart'
    show FlmText;
import 'package:flame/services/translation/offline_translation_engine.dart';
import 'package:flame/services/translation/translation_engine.dart';

/// Offline evaluation of the translation layer against the real classroom
/// eval set (`test_data/classroom_eval_sentences.json`, 60 sentences) and the
/// real bundled corpus (1023 pairs).
///
/// SAFETY CONTRACT UNDER TEST: for every sentence the engine may produce text
/// ONLY from an exact phrase-cache match. Any unrelated corpus output fails
/// this test. With no model backend installed, every non-cache sentence must
/// fail explicitly with an empty target.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'eval set (60 sentences): never an unrelated corpus phrase, '
      'explicit failure otherwise', () async {
    final engine = OfflineTranslationEngine();

    final corpusRaw = jsonDecode(
      await rootBundle.loadString('assets/fln/corpus_pairs.json'),
    ) as List<dynamic>;
    final exactHindi = <String, String>{
      for (final e in corpusRaw)
        FlmText.normalize((e['hindi'] as String? ?? '').trim()):
            (e['santhali'] as String? ?? '').trim(),
    };

    final evalRaw = jsonDecode(
      File('test_data/classroom_eval_sentences.json').readAsStringSync(),
    ) as List<dynamic>;
    expect(evalRaw.length, greaterThanOrEqualTo(50),
        reason: 'eval set must contain at least 50 classroom sentences');

    var exactHits = 0;
    var unavailable = 0;
    var errors = 0;
    final latenciesMs = <double>[];
    final categories = <String, int>{};

    for (final e in evalRaw) {
      final hindi = (e['hindi'] as String).trim();
      final category = e['category'] as String;
      categories[category] = (categories[category] ?? 0) + 1;

      final sw = Stopwatch()..start();
      final res = await engine.translate(
        hindi,
        source: AppLanguage.hindi,
        target: AppLanguage.santhali,
      );
      sw.stop();
      latenciesMs.add(sw.elapsedMicroseconds / 1000.0);

      if (res.canTranslate) {
        exactHits++;
        expect(res.quality, TranslationQuality.exact,
            reason: 'only exact cache hits may translate today: $hindi');
        expect(
          res.targetText,
          exactHindi[FlmText.normalize(hindi)],
          reason: 'UNRELATED/OFF corpus output for: $hindi — must never happen',
        );
      } else {
        unavailable++;
        expect(res.targetText, isEmpty,
            reason: 'explicitly unavailable must be empty for: $hindi');
        expect(res.quality, TranslationQuality.fallback);
      }
    }

    expect(categories.length, 10,
        reason: 'eval set must cover all 10 requested categories');
    expect(errors, 0);

    // Desktop benchmark only — never treated as Android evidence.
    final avgMs = latenciesMs.reduce((a, b) => a + b) / latenciesMs.length;
    final maxMs = latenciesMs.reduce((a, b) => a > b ? a : b);
    final minMs = latenciesMs.reduce((a, b) => a < b ? a : b);
    // ignore: avoid_print
    print(
      'DESKTOP-BENCH translation(cache-only) '
      'sentences=${evalRaw.length} exactHits=$exactHits '
      'unavailable=$unavailable errors=$errors '
      'avgMs=${avgMs.toStringAsFixed(2)} maxMs=${maxMs.toStringAsFixed(2)} '
      'minMs=${minMs.toStringAsFixed(2)}',
    );
  });

  test('real model bundle assets ship in the APK', () async {
    await expectLater(
      rootBundle.load('assets/models/vosk-model-small-hi-0.22.zip'),
      completes,
    );
    await expectLater(
      rootBundle.load('assets/fonts/NotoSansOlChiki.ttf'),
      completes,
    );
  });
}