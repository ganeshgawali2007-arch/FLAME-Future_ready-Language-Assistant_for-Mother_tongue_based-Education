/// Greedy-decode inference engine for the IndicTrans2 INT8 ONNX bundle
/// (encoder / decoder / decoder_with_past), a 1:1 port of the verified host
/// reference loop (`run_inference.py`):
///
///   input_ids (clamped to src_dict_size, mask = all ones)
///     -> encoder(input_ids, attention_mask) -> last_hidden_state
///     -> step 0: decoder([decoder_start], enc_hidden, enc_mask)
///     -> step n: decoder_with_past([next], enc_mask, past)
///     -> argmax until eos (inclusive) or max_new_tokens
///
/// The ONNX sessions themselves live behind [NmtRuntime] so the loop is
/// testable on the host against frozen golden fixtures (the Android runtime
/// keeps ORT sessions + past tensors in native memory and exposes only tiny
/// per-step calls over the platform channel).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/enums.dart';
import 'nmt_model_pack.dart';
import 'nmt_tokenizer.dart';
import 'offline_translation_engine.dart';
import 'translation_engine.dart';

/// Native/runtime seam for the three ONNX sessions.
///
/// Contract (mirrors the host reference exactly):
///  * [startDecode] runs the encoder plus decoder step 0 (feeding the
///    decoder-start token) and returns the first greedy token id.
///  * [step] feeds one accepted token into decoder_with_past and returns the
///    next greedy token id.
///  * [endDecode] discards the per-sentence native state (past tensors,
///    encoder outputs). It must be safe to call after any failure.
abstract class NmtRuntime {
  /// Load the three ONNX sessions from [modelDir]. Idempotent.
  Future<void> load(String modelDir);

  /// True only when all three sessions are genuinely loaded.
  bool get isLoaded;

  /// Encoder + decoder step 0. [inputIds] are already clamped to the src
  /// vocab; [attentionMask] is all ones (no padding — single sentence).
  /// Returns the first greedy next-token id.
  Future<int> startDecode(List<int> inputIds, List<int> attentionMask);

  /// decoder_with_past step for one accepted [nextId]. Returns the next
  /// greedy token id.
  Future<int> step(int nextId);

  /// Free the per-sentence native decode state. Never throws.
  Future<void> endDecode();

  /// Release all native sessions so RAM returns to the app (low-end rule).
  Future<void> release();
}

/// Sentence-level greedy decoder. Owns no native state itself.
class NmtEngine {
  NmtEngine({required this.tokenizer, required this.runtime});

  final NmtTokenizer tokenizer;
  final NmtRuntime runtime;

  /// Host reference decodes with max_new_tokens = 128.
  static const int maxNewTokens = 128;

  /// Greedy-decode [inputIds] (src-side, including lang tags + trailing
  /// `</s>`) into tgt-side ids: `[decoder_start, ...generated, eos?]`.
  ///
  /// [requestId] is a diagnostic correlation id printed in the per-stage
  /// NMT_REQUEST → … → NMT_RESULT sequence so a failing step is identifiable
  /// in logcat. It never changes decoding behaviour.
  Future<List<int>> generate(List<int> inputIds, {String requestId = '-'}) async {
    final meta = tokenizer.meta;
    final sw = Stopwatch()..start();
    debugPrint(
        'FLAME_NMT TOKENIZE request=$requestId srcIds=${inputIds.length} '
        'ids=$inputIds '
        'decoderStart=${meta.decoderStartTokenId} eos=${meta.eosTokenId} '
        'maxLen=$maxNewTokens');
    final clamped = [
      for (final id in inputIds)
        id < 0 || id >= meta.srcDictSize ? 3 : id, // <unk> = 3 (host rule)
    ];
    if (clamped != inputIds) {
      debugPrint('FLAME_NMT TOKENIZE request=$requestId CLAMPED ids=$clamped');
    }
    final mask = List<int>.filled(clamped.length, 1);
    final output = <int>[meta.decoderStartTokenId];
    var generated = 0;
    try {
      debugPrint('FLAME_NMT ENCODER request=$requestId start '
          'ids=${clamped.length} mask=${mask.length}');
      var next = await runtime.startDecode(clamped, mask);
      output.add(next);
      generated++;
      debugPrint('FLAME_NMT ENCODER request=$requestId done '
          '(${sw.elapsedMilliseconds}ms)');
      debugPrint('FLAME_NMT DECODER_STEP request=$requestId step=0 '
          'accepted=2 out=$next${next == meta.eosTokenId ? ' EOS(IMMEDIATE)' : ''}');
      while (next != meta.eosTokenId && generated < maxNewTokens) {
        next = await runtime.step(next);
        output.add(next);
        generated++;
        debugPrint(
            'FLAME_NMT DECODER_STEP request=$requestId step=$generated '
            'out=$next${next == meta.eosTokenId ? ' EOS' : ''} '
            '(${sw.elapsedMilliseconds}ms)');
      }
      debugPrint('FLAME_NMT EOS request=$requestId '
          'generated=$generated decodedIds=${output.length} '
          '(${sw.elapsedMilliseconds}ms)');
    } finally {
      await runtime.endDecode();
    }
    return output;
  }
}

/// Real on-device Hindi↔Santhali backend: [NmtTokenizer] for text ↔ ids and
/// [NmtEngine] for the ONNX greedy loop.
///
/// Honesty contract preserved: [isInstalled] is true only after [warmUp]
/// genuinely found the model pack and loaded the native sessions; before
/// that, [translate] throws [TranslationModelNotInstalledException] and the
/// pipeline falls through to the explicit-unavailable state.
class IndicTrans2Backend extends TranslationBackend {
  IndicTrans2Backend({
    required this.tokenizer,
    required this.engine,
    required this.modelDirResolver,
  });

  final NmtTokenizer tokenizer;
  final NmtEngine engine;

  /// Resolves the on-device model pack directory, or null when absent.
  final Future<String?> Function() modelDirResolver;

  bool _installed = false;
  String? _modelDir;

  @override
  final String modelName = 'IndicTrans2-indic-indic-dist-320M (int8)';

  @override
  bool get isInstalled => _installed;

  /// The resolved pack directory (null until [warmUp] finds it).
  String? get modelDir => _modelDir;

  /// Probe the pack and load tokenizer tables + native sessions.
  /// Returns true when the model is genuinely usable afterwards.
  Future<bool> warmUp() async {
    final sw = Stopwatch()..start();
    debugPrint('FLAME_NMT MODEL_LOADING: start');
    final dir = await modelDirResolver();
    debugPrint('FLAME_NMT MODEL_LOADING: modelDir=${dir ?? "NULL"} (${sw.elapsedMilliseconds}ms)');
    if (dir == null) {
      _installed = false;
      debugPrint('FLAME_NMT MODEL_LOADING: FAIL pack unresolved');
      return false;
    }
    // Requirement: per-file exists / size / readable evidence at runtime. The
    // pack resolver only guarantees "complete enough"; log the concrete audit
    // before any session is created.
    final audit = NmtModelPack.audit(Directory(dir));
    for (final a in audit) {
      debugPrint('FLAME_NMT PACK_AUDIT ${a.name} '
          'exists=${a.exists} bytes=${a.sizeBytes} floor=${a.minBytes} '
          'ok=${a.ok}');
    }
    debugPrint('FLAME_NMT PACK_AUDIT dir=$dir complete=${audit.every((a) => a.ok)}');
    await tokenizer.load();
    debugPrint('FLAME_NMT MODEL_LOADING: tokenizer loaded (${sw.elapsedMilliseconds}ms) '
        'srcDict=${tokenizer.meta.srcDictSize} tgtDict=${tokenizer.meta.tgtDictSize} '
        'decoderStart=${tokenizer.meta.decoderStartTokenId} eos=${tokenizer.meta.eosTokenId} '
        'maxLength=${tokenizer.meta.maxLength}');
    debugPrint('FLAME_NMT ONNX_RUNTIME_INIT_START dir=$dir');
    try {
      await engine.runtime.load(dir);
    } catch (e) {
      debugPrint('FLAME_NMT ONNX_RUNTIME_INIT_FAIL exact="$e"');
      _installed = false;
      _modelDir = dir;
      rethrow;
    }
    debugPrint('FLAME_NMT ONNX_RUNTIME_INIT_SUCCESS '
        '(${sw.elapsedMilliseconds}ms) loaded=${engine.runtime.isLoaded}');
    _modelDir = dir;
    _installed = engine.runtime.isLoaded;
    debugPrint(
        'FLAME_NMT MODEL_READY: installed=$_installed dir=$_modelDir (${sw.elapsedMilliseconds}ms)');
    return _installed;
  }

  /// Release native sessions (data stays on device).
  Future<void> unload() async {
    await engine.runtime.release();
    _installed = false;
  }

  /// Lazy self-initialization: the model loads on the first translate request
  /// after install. No-op (true) once already installed; false when the pack
  /// is absent/unreadable — the pipeline then stays on explicit-unavailable.
  @override
  Future<bool> ensureReady() async {
    if (_installed) return true;
    return warmUp();
  }

  static String floresCode(AppLanguage lang) => switch (lang) {
        AppLanguage.hindi => 'hin_Deva',
        AppLanguage.santhali => 'sat_Olck',
      };

  @override
  Future<TranslationResult> translate(
    String text, {
    required AppLanguage source,
    required AppLanguage target,
  }) async {
    final requestId = '${DateTime.now().microsecondsSinceEpoch}';
    final sw = Stopwatch()..start();
    debugPrint('FLAME_NMT NMT_REQUEST request=$requestId '
        'source=$source target=$target');
    if (!_installed) {
      debugPrint('FLAME_NMT NMT_REQUEST request=$requestId FAIL not installed');
      throw TranslationModelNotInstalledException(modelName);
    }
    final srcLang = floresCode(source);
    final tgtLang = floresCode(target);
    debugPrint('FLAME_NMT LANG_CODES request=$requestId source=$source'
        ' -> srcLang=$srcLang, target=$target -> tgtLang=$tgtLang');
    final prefixed = tokenizer.preprocess(
      text,
      srcLang: srcLang,
      tgtLang: tgtLang,
    );
    debugPrint('FLAME_NMT PREPROCESS request=$requestId '
        'text="${text.length > 60 ? text.substring(0, 60) : text}" ');
    final inputIds = tokenizer.encode(prefixed, target: false);
    final outputIds = await engine.generate(inputIds, requestId: requestId);
    final decoded = tokenizer.decode(outputIds, target: true);
    if (decoded.trim().isEmpty) {
      debugPrint('FLAME_NMT DECODE request=$requestId FAIL empty result '
          'ids=$outputIds');
      throw StateError('IndicTrans2 produced an empty translation');
    }
    debugPrint('FLAME_NMT NMT_RESULT request=$requestId '
        'elapsed=${sw.elapsedMilliseconds}ms '
        'decoded="${decoded.length > 120 ? decoded.substring(0, 120) : decoded}" '
        'chars=${decoded.runes.length}');
    return TranslationResult(
      sourceText: text,
      targetText: decoded,
      quality: TranslationQuality.model,
      canTranslate: true,
    );
  }
}
