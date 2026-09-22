/// High-confidence preloaded classroom phrase cache.
///
/// This is a *cache*, not a translation engine. It answers EXACT, normalized
/// bilingual phrase matches only — there is deliberately no fuzzy/overlap tier.
/// A sentence that is not in the cache goes to the real on-device model
/// ([TranslationBackend]) or fails explicitly. The educational app must prefer
/// "No reliable translation available" over an unrelated guess.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/enums.dart';
import 'corpus_translation_engine.dart' show FlmText;

class PhrasePair {
  const PhrasePair({required this.hindi, required this.santhali});

  final String hindi;
  final String santhali;
}

class EducationalPhraseCache {
  EducationalPhraseCache({List<PhrasePair>? phrases}) {
    if (phrases != null) {
      _indexFromPairs(phrases);
    }
  }

  Map<String, String> _hindiIndex = {};
  Map<String, String> _santhaliIndex = {};
  int _pairCount = 0;
  bool _loading = false;

  bool get isReady => _hindiIndex.isNotEmpty;
  int get pairCount => _pairCount;

  Future<void> ensureLoaded() async {
    if (isReady || _loading) return;
    _loading = true;
    try {
      final raw =
          await rootBundle.loadString('assets/fln/corpus_pairs.json');
      final list = jsonDecode(raw) as List<dynamic>;
      _indexFromPairs([
        for (final e in list)
          PhrasePair(
            hindi: (e['hindi'] as String? ?? '').trim(),
            santhali: (e['santhali'] as String? ?? '').trim(),
          ),
      ]);
    } catch (_) {
      _loading = false;
      rethrow;
    }
    _loading = false;
  }

  void _indexFromPairs(List<PhrasePair> pairs) {
    _hindiIndex = {
      for (final p in pairs.where((p) => p.hindi.isNotEmpty))
        FlmText.normalize(p.hindi): p.santhali,
    };
    _santhaliIndex = {
      for (final p in pairs.where((p) => p.santhali.isNotEmpty))
        FlmText.normalize(p.santhali): p.hindi,
    };
    _pairCount = pairs.length;
  }

  /// Exact normalized lookup only. Returns null when the sentence is not in
  /// the cache. Never performs approximate/overlap matching.
  String? lookupExact(String text, AppLanguage source) {
    final norm = FlmText.normalize(text);
    if (norm.isEmpty) return null;
    final index = source == AppLanguage.hindi ? _hindiIndex : _santhaliIndex;
    return index[norm];
  }
}