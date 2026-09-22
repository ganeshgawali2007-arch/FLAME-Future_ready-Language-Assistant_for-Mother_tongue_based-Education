/// The real offline translation engine.
///
/// Pipeline (all local, zero network, never throws):
///   1. Exact classroom phrase → [EducationalPhraseCache] hit.
///   2. Otherwise → real on-device model via [TranslationBackend] (if installed).
///   3. Otherwise → explicit failure: "No reliable translation available".
///
/// There is NO overlap/guess tier: an unknown sentence never produces an
/// unrelated corpus phrase. Safety over coverage.
library;

import 'package:flutter/foundation.dart';

import '../../models/enums.dart';
import 'corpus_translation_engine.dart' show FlmText;
import 'educational_phrase_cache.dart';
import 'translation_engine.dart';

/// Raised when a real model backend is asked to translate but is not installed.
class TranslationModelNotInstalledException implements Exception {
  const TranslationModelNotInstalledException(this.modelName);
  final String modelName;

  @override
  String toString() => 'TranslationModelNotInstalledException: $modelName';
}

/// A real on-device translation model (e.g. IndicTrans2 ONNX INT8 once shipped).
abstract class TranslationBackend {
  /// True only when the model is genuinely installed on the device.
  bool get isInstalled;

  /// Ensure the backend is ready to translate (lazy-loads its model pack when
  /// needed). Returns true when [isInstalled] afterwards. Default impl is a
  /// no-op for backends that load eagerly (e.g. the not-installed backend).
  Future<bool> ensureReady() async => isInstalled;

  String get modelName;

  /// Perform real inference. Must throw [TranslationModelNotInstalledException]
  /// when [isInstalled] is false.
  Future<TranslationResult> translate(
    String text, {
    required AppLanguage source,
    required AppLanguage target,
  });
}

/// A backend that is not installed. It exists so the pipeline can be honest:
/// requesting a translation returns the explicit unavailable state, never a guess.
class NotInstalledTranslationBackend extends TranslationBackend {
  NotInstalledTranslationBackend(this.modelName);

  @override
  final String modelName;

  @override
  bool get isInstalled => false;

  @override
  Future<TranslationResult> translate(
    String text, {
    required AppLanguage source,
    required AppLanguage target,
  }) {
    throw TranslationModelNotInstalledException(modelName);
  }
}

class OfflineTranslationEngine implements TranslationEngine {
  OfflineTranslationEngine({
    EducationalPhraseCache? phraseCache,
    TranslationBackend? backend,
  })  : _phraseCache = phraseCache ?? EducationalPhraseCache(),
        _backend = backend ?? _defaultBackend;

  final EducationalPhraseCache _phraseCache;
  final TranslationBackend _backend;

  static final TranslationBackend _defaultBackend =
      NotInstalledTranslationBackend('IndicTrans2-indic-indic-dist-320M (int8)');

  bool get hasModelBackend => _backend.isInstalled;

  /// The exact-match phrase cache backing tier 1 of the pipeline.
  EducationalPhraseCache get phraseCache => _phraseCache;

  @override
  bool get isReady => true;

  @override
  Future<TranslationResult> translate(
    String text, {
    required AppLanguage source,
    required AppLanguage target,
  }) async {
    final pipeStart = DateTime.now();
    final norm = FlmText.normalize(text);
    debugPrint('FLAME_PIPE translate source=$source target=$target '
        'raw="${text.length > 60 ? text.substring(0, 60) : text}" '
        'norm="${norm.length > 60 ? norm.substring(0, 60) : norm}"');
    if (norm.isEmpty) {
      debugPrint('FLAME_PIPE REJECT empty norm');
      return _explicitUnavailable(text);
    }
    if (source == target) {
      debugPrint('FLAME_PIPE REJECT source==target');
      return _explicitUnavailable(text);
    }
    if (source != AppLanguage.hindi && source != AppLanguage.santhali) {
      debugPrint('FLAME_PIPE REJECT unsupported source=$source');
      return _explicitUnavailable(text);
    }
    if (target != AppLanguage.hindi && target != AppLanguage.santhali) {
      debugPrint('FLAME_PIPE REJECT unsupported target=$target');
      return _explicitUnavailable(text);
    }

    // Tier 1: exact classroom phrase cache hit.
    try {
      await _phraseCache.ensureLoaded();
    } catch (_) {
      // Cache unreadable is not fatal — continue to model / explicit failure.
    }
    final exact = _phraseCache.lookupExact(norm, source);
    debugPrint('FLAME_PIPE CACHE_LOOKUP exact=${exact == null ? "MISS" : "HIT"}');
    if (exact != null && exact.isNotEmpty) {
      debugPrint('FLAME_PIPE CACHE_HIT -> "${exact.length > 60 ? exact.substring(0, 60) : exact}"');
      return TranslationResult(
        sourceText: text,
        targetText: exact,
        quality: TranslationQuality.exact,
        canTranslate: true,
      );
    }

    // Tier 2: real on-device model. The backend self-initializes lazily on the
    // first request after the pack is installed (nothing else loads it).
    try {
      debugPrint(
          'FLAME_PIPE TIER2 ensureReady backend="${_backend.modelName}" '
          'installedBefore=${_backend.isInstalled}');
      final ready = await _backend.ensureReady();
      debugPrint('FLAME_PIPE TIER2 ensureReady -> ready=$ready');
      if (ready) {
        final r = await _backend.translate(
            text, source: source, target: target);
        debugPrint(
            'FLAME_PIPE TIER2 model result quality=${r.quality.name} '
            'canTranslate=${r.canTranslate} '
            'targetChars=${r.targetText.runes.length}');
        return r;
      }
      debugPrint('FLAME_PIPE TIER2 SKIPPED (not installed)');
    } catch (e) {
      debugPrint('FLAME_PIPE TIER2 FAILED: $e');
      // Fall through to the explicit unavailable state — never a guess.
    }

    // Tier 3: explicit failure. Never an unrelated sentence.
    debugPrint(
        'FLAME_PIPE TIER3 explicit-unavailable elapsedMs=${DateTime.now().difference(pipeStart).inMilliseconds}');
    return _explicitUnavailable(text);
  }

  TranslationResult _explicitUnavailable(String text) =>
      TranslationResult(
        sourceText: text,
        targetText: '',
        quality: TranslationQuality.fallback,
        canTranslate: false,
      );
}