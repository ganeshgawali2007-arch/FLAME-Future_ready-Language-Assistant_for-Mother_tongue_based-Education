/// Age-appropriate answer shaping (PedagogyEngine).
///
/// Keeps responses short and concrete for young learners. Grade adaptation is
/// deterministic and local — no generative model involved.
library;

import '../../models/entities.dart';

class PedagogyEngine {
  const PedagogyEngine();

  /// Short human label used for the "answer level" chip.
  String levelLabel(KnowledgeEntry entry) {
    final n = _classNumber(entry.classLevel);
    return switch (n) {
      1 => 'Very simple',
      2 => 'Simple + example',
      _ => 'Detailed for this class',
    };
  }

  int _classNumber(String level) {
    final match = RegExp(r'(\d+)').firstMatch(level);
    if (match == null) return 3;
    return int.tryParse(match.group(1)!) ?? 3;
  }

  /// Number of sentences to keep in an answer for a given class level.
  int sentenceBudget(String classLevel) {
    final n = _classNumber(classLevel);
    return n == 1 ? 2 : (n == 2 ? 3 : 4);
  }

  /// Trims a Hindi/Santhali answer down to [budget] sentences without
  /// ever truncating mid-word.
  String trimToBudget(String answer, String classLevel) {
    final budget = sentenceBudget(classLevel);
    final sentences = answer
        .split(RegExp(r'(?<=[।.?!])\s*'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (sentences.length <= budget) return answer.trim();
    return sentences.take(budget).join(' ').trim();
  }
}