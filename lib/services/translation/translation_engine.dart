/// Abstract translation engine (offline).
///
/// The live-class translation pipeline depends only on this interface, so the
/// implementation can be swapped for an IndicTrans2-on-ONNX engine later
/// without touching classroom code. See [OfflineTranslationEngine] for the
/// bundled offline implementation.
library;

import '../../models/enums.dart';

enum TranslationQuality {
  /// Exact sentence found in the verified phrase cache.
  exact,

  /// Produced by a real on-device translation model.
  model,

  /// No usable target text — explicit "no reliable translation available".
  fallback,
}

class TranslationResult {
  const TranslationResult({
    required this.sourceText,
    required this.targetText,
    required this.quality,
    required this.canTranslate,
  });

  final String sourceText;
  final String targetText;
  final TranslationQuality quality;
  final bool canTranslate;
}

abstract class TranslationEngine {
  /// Translate [text] from [source] to [target]. Never throws.
  Future<TranslationResult> translate(
    String text, {
    required AppLanguage source,
    required AppLanguage target,
  });

  bool get isReady;
}

/// Raised by engines that own a corpus asset but have not loaded it yet.
class TranslationNotReadyException implements Exception {
  const TranslationNotReadyException([this.message = '']);
  final String message;

  @override
  String toString() => 'TranslationNotReadyException: $message';
}