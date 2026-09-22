import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/enums.dart';
import 'package:flame/services/translation/corpus_translation_engine.dart';
import 'package:flame/services/translation/educational_phrase_cache.dart';
import 'package:flame/services/translation/offline_translation_engine.dart';
import 'package:flame/services/translation/translation_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const phrases = [
    PhrasePair(
      hindi: 'सब छात्र अपनी सीट पर बैठो',
      santhali: 'सब छात्र अपनी सीट पर बैठो (तर)',
    ),
    PhrasePair(
      hindi: 'पानी कहाँ से आता है',
      santhali: 'दसर बली हाँवा गो',
    ),
  ];

  late EducationalPhraseCache cache;
  late OfflineTranslationEngine engine;

  setUp(() {
    cache = EducationalPhraseCache(phrases: phrases);
    engine = OfflineTranslationEngine(phraseCache: cache);
  });

  group('FlmText normalization', () {
    test('strips trailing question marks and collapses spaces', () {
      expect(FlmText.normalize('  रोशनी क्या है ?  '), 'रोशनी क्या है');
    });

    test('tokens split Devanagari from punctuation', () {
      expect(FlmText.tokens('सीट, पर।'), ['सीट', 'पर']);
    });

    test('looksLikeHindi detects Devanagari', () {
      expect(FlmText.looksLikeHindi('पानी'), isTrue);
      expect(FlmText.looksLikeHindi('hello'), isFalse);
    });
  });

  group('EducationalPhraseCache (exact only)', () {
    test('exact hindi → santhali hit', () {
      expect(
        cache.lookupExact('सब छात्र अपनी सीट पर बैठो', AppLanguage.hindi),
        phrases.first.santhali,
      );
    });

    test('exact santhali → hindi hit', () {
      expect(
        cache.lookupExact(phrases.first.santhali, AppLanguage.santhali),
        phrases.first.hindi,
      );
    });

    test('near-miss returns null — no overlap tier', () {
      // One shared word ("पानी") must NOT select an unrelated sentence.
      expect(
        cache.lookupExact('पानी कहाँ से मिलता है', AppLanguage.hindi),
        isNull,
      );
    });

    test('empty input is never matched', () {
      expect(cache.lookupExact('   ', AppLanguage.hindi), isNull);
    });
  });

  group('OfflineTranslationEngine safety rules', () {
    test('exact classroom phrase translates', () async {
      final res = await engine.translate(
        'सब छात्र अपनी सीट पर बैठो',
        source: AppLanguage.hindi,
        target: AppLanguage.santhali,
      );
      expect(res.quality, TranslationQuality.exact);
      expect(res.canTranslate, isTrue);
      expect(res.targetText, phrases.first.santhali);
    });

    test('unknown classroom sentence → explicit unavailable, never a guess',
        () async {
      final res = await engine.translate(
        'कल रात बहुत ठंड थी और हिमपात हुआ',
        source: AppLanguage.hindi,
        target: AppLanguage.santhali,
      );
      expect(res.canTranslate, isFalse);
      expect(res.quality, TranslationQuality.fallback);
      expect(res.targetText, isEmpty);
    });

    test('overlap-trap sentence returns NO unrelated corpus phrase', () async {
      // `पानी कहाँ से मिलता है` shares the token `पानी` with a corpus pair.
      // It must fail explicitly rather than returning that unrelated sentence.
      final res = await engine.translate(
        'पानी कहाँ से मिलता है',
        source: AppLanguage.hindi,
        target: AppLanguage.santhali,
      );
      expect(res.canTranslate, isFalse);
      expect(res.targetText, isEmpty);
    });

    test('empty input returns explicit unavailable', () async {
      final res = await engine.translate(
        '   ',
        source: AppLanguage.hindi,
        target: AppLanguage.santhali,
      );
      expect(res.canTranslate, isFalse);
      expect(res.targetText, isEmpty);
    });

    test('same-language request is rejected', () async {
      final res = await engine.translate(
        'पानी कहाँ से आता है',
        source: AppLanguage.hindi,
        target: AppLanguage.hindi,
      );
      expect(res.canTranslate, isFalse);
    });

    test('missing model backend fails explicitly (never fakes)', () async {
      expect(engine.hasModelBackend, isFalse);
      final res = await engine.translate(
        'आज हम पौधों के बारे में सीखेंगे',
        source: AppLanguage.hindi,
        target: AppLanguage.santhali,
      );
      expect(res.canTranslate, isFalse);
      expect(res.targetText, isEmpty);
    });

    test('installed backend produces a real model translation', () async {
      final custom = _TestBackend();
      final withBackend = OfflineTranslationEngine(
        phraseCache: cache,
        backend: custom,
      );
      final res = await withBackend.translate(
        'आज हम पौधों के बारे में सीखेंगे',
        source: AppLanguage.hindi,
        target: AppLanguage.santhali,
      );
      expect(res.canTranslate, isTrue);
      expect(res.quality, TranslationQuality.model);
      expect(res.targetText, 'MODEL-OUTPUT');
    });

    test('failing backend falls back to explicit unavailable', () async {
      final failing = _ThrowingBackend();
      final withBackend =
          OfflineTranslationEngine(phraseCache: cache, backend: failing);
      final res = await withBackend.translate(
        'अज्ञात वाक्य',
        source: AppLanguage.hindi,
        target: AppLanguage.santhali,
      );
      expect(res.canTranslate, isFalse);
      expect(res.targetText, isEmpty);
    });

    test('reverse direction sat → hi works via cache', () async {
      final res = await engine.translate(
        phrases.first.santhali,
        source: AppLanguage.santhali,
        target: AppLanguage.hindi,
      );
      expect(res.canTranslate, isTrue);
      expect(res.quality, TranslationQuality.exact);
      expect(res.targetText, phrases.first.hindi);
    });
  });
}

class _TestBackend extends TranslationBackend {
  @override
  bool get isInstalled => true;

  @override
  String get modelName => 'test-backend';

  @override
  Future<TranslationResult> translate(
    String text, {
    required AppLanguage source,
    required AppLanguage target,
  }) async {
    return const TranslationResult(
      sourceText: 'x',
      targetText: 'MODEL-OUTPUT',
      quality: TranslationQuality.model,
      canTranslate: true,
    );
  }
}

class _ThrowingBackend extends TranslationBackend {
  @override
  bool get isInstalled => true;

  @override
  String get modelName => 'throwing-backend';

  @override
  Future<TranslationResult> translate(
    String text, {
    required AppLanguage source,
    required AppLanguage target,
  }) async {
    throw StateError('runtime failure');
  }
}