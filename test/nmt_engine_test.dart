import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/enums.dart';
import 'package:flame/services/translation/nmt_engine.dart';
import 'package:flame/services/translation/nmt_tokenizer.dart';
import 'package:flame/services/translation/offline_translation_engine.dart';
import 'package:flame/services/translation/translation_engine.dart';

const _root = 'D:\\FOREST-FLAME\\Flame apk';

Future<Map<String, String>> _testLoader() async {
  Future<String> load(String path) async =>
      (await File('$_root/$path').readAsString()).trim();
  return {
    'vocab_src': await load('assets/nmt/nmt_vocab_src.txt'),
    'vocab_tgt': await load('assets/nmt/nmt_vocab_tgt.txt'),
    'merges_src': await load('assets/nmt/nmt_merges_src.txt'),
    'merges_tgt': await load('assets/nmt/nmt_merges_tgt.txt'),
    'added_src': await load('assets/nmt/nmt_added_src.txt'),
    'added_tgt': await load('assets/nmt/nmt_added_tgt.txt'),
    'meta': await load('assets/nmt/nmt_meta.json'),
  };
}

/// Replays a recorded host trace and asserts the engine feeds the exact
/// recorded token sequence (decoder-start on step 0, then each accepted id).
class _ReplayRuntime implements NmtRuntime {
  _ReplayRuntime(this._fixture);

  final Map<String, dynamic> _fixture;
  var _stepIdx = -1;
  var ended = false;
  var loaded = false;

  List<dynamic> get _steps => _fixture['steps'] as List;

  @override
  Future<void> load(String modelDir) async {
    loaded = true;
  }

  @override
  bool get isLoaded => loaded;

  @override
  Future<int> startDecode(List<int> inputIds, List<int> attentionMask) async {
    expect(inputIds, _fixture['input_ids']);
    expect(attentionMask, _fixture['attention_mask']);
    _stepIdx = 0;
    return (_steps[0] as Map)['out'] as int;
  }

  @override
  Future<int> step(int nextId) async {
    _stepIdx++;
    expect(_stepIdx, lessThan(_steps.length),
        reason: 'engine fed more steps than the host trace recorded');
    final expected = _steps[_stepIdx] as Map;
    expect(nextId, expected['in'],
        reason: 'step $_stepIdx must feed the previously accepted id');
    return expected['out'] as int;
  }

  @override
  Future<void> endDecode() async {
    ended = true;
  }

  @override
  Future<void> release() async {
    loaded = false;
  }
}

/// Never emits eos — used to pin the max-new-tokens guard.
class _EndlessRuntime implements NmtRuntime {
  var steps = 0;
  var ended = false;

  @override
  Future<void> load(String modelDir) async {}

  @override
  bool get isLoaded => true;

  @override
  Future<int> startDecode(List<int> inputIds, List<int> attentionMask) async =>
      5;

  @override
  Future<int> step(int nextId) async {
    steps++;
    return 5;
  }

  @override
  Future<void> endDecode() async {
    ended = true;
  }

  @override
  Future<void> release() async {}
}

/// Throws mid-decode — used to pin the endDecode-in-finally contract.
class _FailingRuntime implements NmtRuntime {
  var ended = false;

  @override
  Future<void> load(String modelDir) async {}

  @override
  bool get isLoaded => true;

  @override
  Future<int> startDecode(List<int> inputIds, List<int> attentionMask) async =>
      5;

  @override
  Future<int> step(int nextId) async =>
      throw StateError('native session died mid-decode');

  @override
  Future<void> endDecode() async {
    ended = true;
  }

  @override
  Future<void> release() async {}
}

/// Captures the encoder feed and answers eos immediately.
class _CapturingRuntime implements NmtRuntime {
  List<int> seenIds = const [];
  List<int> seenMask = const [];

  @override
  Future<void> load(String modelDir) async {}

  @override
  bool get isLoaded => true;

  @override
  Future<int> startDecode(List<int> inputIds, List<int> attentionMask) async {
    seenIds = List.of(inputIds);
    seenMask = List.of(attentionMask);
    return 2; // eos
  }

  @override
  Future<int> step(int nextId) async => 2;

  @override
  Future<void> endDecode() async {}

  @override
  Future<void> release() async {}
}

void main() {
  late NmtTokenizer tok;
  late List<dynamic> golden;

  setUpAll(() async {
    tok = NmtTokenizer(assetLoader: _testLoader);
    await tok.load();
    golden = jsonDecode(
            await File('$_root/test_data/nmt_engine_golden.json').readAsString())
        as List;
  });

  group('NmtEngine — golden decode traces (real IndicTrans2 int8)', () {
    test('all traces reproduce exact output ids and text', () async {
      for (final entry in golden.cast<Map<String, dynamic>>()) {
        final runtime = _ReplayRuntime(entry);
        final engine = NmtEngine(tokenizer: tok, runtime: runtime);

        // Full chain: preprocess + encode must match the recorded host ids.
        final prefixed = tok.preprocess(entry['text'] as String,
            srcLang: entry['src'] as String, tgtLang: entry['tgt'] as String);
        expect(prefixed, entry['preprocessed']);
        final inputIds = tok.encode(prefixed, target: false);
        expect(inputIds, entry['input_ids']);

        final outputIds = await engine.generate(inputIds);
        expect(outputIds, entry['output_ids'],
            reason: '${entry['src']}→${entry['tgt']}: ${entry['text']}');
        expect(runtime.ended, isTrue,
            reason: 'endDecode must release native past tensors');

        final decoded = tok.decode(outputIds, target: true);
        expect(decoded, entry['decoded']);
      }
    });

    test('eos terminates the loop with no extra steps', () async {
      for (final entry in golden.cast<Map<String, dynamic>>()) {
        final runtime = _ReplayRuntime(entry);
        final engine = NmtEngine(tokenizer: tok, runtime: runtime);
        final output = await engine.generate(
            (entry['input_ids'] as List).cast<int>());
        final steps = entry['steps'] as List;
        if ((steps.last as Map)['out'] == tok.meta.eosTokenId) {
          expect(output.last, tok.meta.eosTokenId);
          expect(output.length, steps.length + 1); // + decoder start
        }
      }
    });
  });

  group('NmtEngine — loop guards', () {
    test('stops at maxNewTokens when eos never comes', () async {
      final runtime = _EndlessRuntime();
      final engine = NmtEngine(tokenizer: tok, runtime: runtime);
      final output = await engine.generate(const [10, 20, 30, 2]);
      expect(output.length, NmtEngine.maxNewTokens + 1); // start + generated
      expect(runtime.steps, NmtEngine.maxNewTokens - 1);
      expect(runtime.ended, isTrue);
    });

    test('endDecode runs even when a step throws', () async {
      final runtime = _FailingRuntime();
      final engine = NmtEngine(tokenizer: tok, runtime: runtime);
      await expectLater(
        engine.generate(const [10, 20, 30, 2]),
        throwsStateError,
      );
      expect(runtime.ended, isTrue);
    });

    test('out-of-range src ids are clamped to <unk> (host rule)', () async {
      final runtime = _CapturingRuntime();
      final engine = NmtEngine(tokenizer: tok, runtime: runtime);
      await engine.generate(const [999999, -1, 41, 2]);
      expect(runtime.seenIds, const [3, 3, 41, 2]);
      expect(runtime.seenMask, const [1, 1, 1, 1]);
    });
  });

  group('IndicTrans2Backend', () {
    test('not installed -> throws TranslationModelNotInstalledException',
        () async {
      final runtime = _EndlessRuntime();
      final backend = IndicTrans2Backend(
        tokenizer: tok,
        engine: NmtEngine(tokenizer: tok, runtime: runtime),
        modelDirResolver: () async => null,
      );
      expect(backend.isInstalled, isFalse);
      expect(await backend.warmUp(), isFalse);
      expect(
        () => backend.translate('पानी पियो।',
            source: AppLanguage.hindi, target: AppLanguage.santhali),
        throwsA(isA<TranslationModelNotInstalledException>()),
      );
    });

    test('installed -> real model-quality translation', () async {
      final entry = golden.cast<Map<String, dynamic>>().firstWhere(
          (e) => e['src'] == 'hin_Deva' && e['tgt'] == 'sat_Olck');
      final runtime = _ReplayRuntime(entry);
      final backend = IndicTrans2Backend(
        tokenizer: tok,
        engine: NmtEngine(tokenizer: tok, runtime: runtime),
        modelDirResolver: () async => 'C:\\fake\\nmt_model',
      );
      expect(await backend.warmUp(), isTrue);
      expect(backend.isInstalled, isTrue);
      final result = await backend.translate(entry['text'] as String,
          source: AppLanguage.hindi, target: AppLanguage.santhali);
      expect(result.canTranslate, isTrue);
      expect(result.quality, TranslationQuality.model);
      expect(result.targetText, entry['decoded']);
    });

    test('unload drops the installed state', () async {
      final runtime = _EndlessRuntime();
      final backend = IndicTrans2Backend(
        tokenizer: tok,
        engine: NmtEngine(tokenizer: tok, runtime: runtime),
        modelDirResolver: () async => 'C:\\fake\\nmt_model',
      );
      expect(await backend.warmUp(), isTrue);
      await backend.unload();
      expect(backend.isInstalled, isFalse);
    });

    test('wires through OfflineTranslationEngine as tier 2', () async {
      final entry = golden.cast<Map<String, dynamic>>().firstWhere(
          (e) => e['src'] == 'hin_Deva' && e['tgt'] == 'sat_Olck');
      final runtime = _ReplayRuntime(entry);
      final backend = IndicTrans2Backend(
        tokenizer: tok,
        engine: NmtEngine(tokenizer: tok, runtime: runtime),
        modelDirResolver: () async => 'C:\\fake\\nmt_model',
      );
      await backend.warmUp();
      final engine = OfflineTranslationEngine(backend: backend);
      expect(engine.hasModelBackend, isTrue);
      final result = await engine.translate(entry['text'] as String,
          source: AppLanguage.hindi, target: AppLanguage.santhali);
      expect(result.canTranslate, isTrue);
      expect(result.quality, TranslationQuality.model);
      expect(result.targetText, entry['decoded']);
    });

    test('backend failure falls through to explicit unavailable', () async {
      final backend = IndicTrans2Backend(
        tokenizer: tok,
        engine: NmtEngine(tokenizer: tok, runtime: _FailingRuntime()),
        modelDirResolver: () async => 'C:\\fake\\nmt_model',
      );
      await backend.warmUp();
      final engine = OfflineTranslationEngine(backend: backend);
      final result = await engine.translate('पानी पियो।',
          source: AppLanguage.hindi, target: AppLanguage.santhali);
      expect(result.canTranslate, isFalse);
      expect(result.quality, TranslationQuality.fallback);
    });
  });
}
