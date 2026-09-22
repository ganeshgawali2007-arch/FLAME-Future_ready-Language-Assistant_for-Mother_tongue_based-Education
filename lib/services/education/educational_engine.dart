/// Offline educational engine behind Ask FLAME.
///
/// Pipeline (all local, deterministic, zero cloud):
///   question → normalize → intent → context-aware retrieval over the local
///   knowledge base → pedagogy shaping → target-language render → TTS.
///
/// Retrieval priority:
///   1. Lesson/context knowledge base (current lesson/topic first).
///   2. Local educational vocabulary & preloaded explanations.
///   3. Deterministic pedagogical rules.
///   4. Lightweight local reasoning (keyword + intent heuristics).
///   5. Honest fallback ("I don't know this yet — let's ask teacher together").
library;

import 'dart:async';

import '../../models/entities.dart';
import '../../models/enums.dart';
import '../translation/corpus_translation_engine.dart' show FlmText;
import 'pedagogy_engine.dart';

class LearningContext {
  const LearningContext({
    this.classLevel = 'Class 3',
    this.subject = 'EVS',
    this.lessonTitle = '',
    this.topicTitle = '',
    this.defaultLanguage = AppLanguage.hindi,
  });

  final String classLevel;
  final String subject;
  final String lessonTitle;
  final String topicTitle;
  final AppLanguage defaultLanguage;
}

class OfflineEducationalEngine {
  OfflineEducationalEngine({
    Future<List<KnowledgeEntry>> Function()? entriesLoader,
  }) : _entriesLoader = entriesLoader ?? (() async => const []);

  final Future<List<KnowledgeEntry>> Function() _entriesLoader;
  final PedagogyEngine _pedagogy = const PedagogyEngine();
  List<KnowledgeEntry>? _cache;

  Future<void> ensureLoaded() async {
    _cache ??= await _entriesLoader();
  }

  Future<AskFlameResult> answer(
    String question, {
    LearningContext context = const LearningContext(),
  }) async {
    await ensureLoaded();
    final norm = FlmText.normalize(question);
    final resolved = _resolveContextQuestions(norm, context);
    final entry = _retrieve(resolved, context);
    if (entry == null) {
      return _fallback(question, context);
    }
    final answerHindi = _pedagogy.trimToBudget(entry.answerHindi, entry.classLevel);
    // Santhali renderer: empty until an educator-reviewed Santhali pack is
    // installed or an IndicTrans2 ONNX engine is integrated (see
    // SanthaliResponseRenderer below). We never fabricate target text.
    final answerSanthali = entry.answerSanthali;
    return AskFlameResult(
      question: question.trim(),
      answerHindi: answerHindi,
      answerSanthali: answerSanthali,
      spokenText: answerHindi,
      answerLevel: _pedagogy.levelLabel(entry),
      fromKnowledgeBase: true,
    );
  }

  /// Context-awareness: short/pronoun questions inherit the current topic.
  ///
  /// "Why do they need sunlight?" inside a Plants lesson resolves "they" to
  /// the topic so the student never has to repeat it (spec requirement).
  String _resolveContextQuestions(String norm, LearningContext context) {
    final lower = norm.toLowerCase();
    final pronouns = {
      'they', 'they need', 'they are', 'them', 'their', 'it', 'its',
      'इन्हें', 'उन्हें', 'इनको', 'उनको', 'इसे', 'उसे', 'ये', 'वे',
      'पौधे', 'पौधों',
    };
    final startsWithPronoun = pronouns.any((p) {
      final idx = lower.indexOf(p);
      return idx == 0 || (idx <= 2 && idx >= 0);
    });
    if (!startsWithPronoun) return norm;
    final topic = context.topicTitle.isNotEmpty
        ? context.topicTitle
        : context.lessonTitle;
    if (topic.isEmpty) return norm;
    return '$topic $norm';
  }

  KnowledgeEntry? _retrieve(String norm, LearningContext context) {
    final entries = _cache ?? const [];
    if (entries.isEmpty) return null;

    final questionTokens =
        FlmText.tokens(norm).where((t) => t.length > 2).toSet();

    KnowledgeEntry? best;
    double bestScore = 0;

    for (final e in entries) {
      var score = 0.0;

      // 1a. Context boost — current topic/lesson wins first (spec priority 1).
      if (context.topicTitle.isNotEmpty &&
          e.topicTitle.toLowerCase().contains(context.topicTitle.toLowerCase())) {
        score += 2.0;
      } else if (context.lessonTitle.isNotEmpty &&
          e.topicTitle.toLowerCase().contains(context.lessonTitle.toLowerCase())) {
        score += 1.5;
      }

      // 1b. Keyword overlap between the question and the entry's keyword list.
      final keywordHits = e.keywords
          .where((k) => norm.contains(k.toLowerCase()))
          .length;
      score += keywordHits * 2.0;

      // 1c. Token overlap with the canonical English question.
      final enTokens = FlmText.tokens(e.questionEn).toSet();
      final inter = questionTokens.intersection(enTokens).length;
      score += inter * 1.0;

      // 1d. Devanagari token overlap with the answer (prefix-tolerant so
      // "पौधों" matches "पौधा"). Keeps Hindi questions answerable from local
      // content without any external model.
      final answerTokens = FlmText.tokens(e.answerHindi).toSet();
      var hinHits = 0;
      for (final tq in questionTokens) {
        if (!_isDevanagari(tq)) continue;
        for (final ta in answerTokens) {
          if (_matchesPrefix(tq, ta)) {
            hinHits++;
            break;
          }
        }
      }
      score += hinHits * 1.5;

      if (score > bestScore) {
        bestScore = score;
        best = e;
      }
    }

    if (best == null || bestScore < 1.5) return null;
    return best;
  }

  static bool _isDevanagari(String s) {
    final c = s.codeUnitAt(0);
    return c >= 0x0900 && c <= 0x097F;
  }

  static bool _matchesPrefix(String a, String b) {
    final minLen = a.length < b.length ? a.length : b.length;
    return minLen >= 3 && a.substring(0, minLen) == b.substring(0, minLen);
  }

  AskFlameResult _fallback(String question, LearningContext context) {
    final levelWord = _classWord(context.classLevel);
    return AskFlameResult(
      question: question.trim(),
      answerHindi:
          'अभी मुझे इस सवाल का जवाब नहीं पता है। '
          'चलो, इसके बारे में टीचर मैम से साथ मिलकर पूछें। '
          'आप $levelWord में बहुत अच्छा सीख रहे हैं!',
      answerSanthali: '',
      spokenText:
          'अभी मुझे इस सवाल का जवाब नहीं पता है। चलो टीचर मैम से साथ में पूछें।',
      answerLevel: 'Friendly',
      fromKnowledgeBase: false,
    );
  }

  String _classWord(String classLevel) {
    if (classLevel.endsWith('1') ||
        classLevel.contains('Class 1') ||
        classLevel.contains('कक्षा 1')) {
      return 'पहली कक्षा';
    }
    if (classLevel.contains('Class 2') || classLevel.contains('कक्षा 2')) {
      return 'दूसरी कक्षा';
    }
    return 'तीसरी कक्षा';
  }
}

/// Santhali response renderer — INTEGRATION POINT.
///
/// Replace this with an IndicTrans2-on-ONNX engine or an educator-reviewed
/// Santhali content pack. Until then, Santhali answers come only from content
/// authored with verified sources; the voice reads Hindi (offline system TTS).
class SanthaliResponseRenderer {
  const SanthaliResponseRenderer();

  bool get canRenderSanthali => false;
  final String integrationLabel =
      'lib/services/education/educational_engine.dart';
}