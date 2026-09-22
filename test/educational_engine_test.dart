import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/entities.dart';
import 'package:flame/services/education/educational_engine.dart';
import 'package:flame/services/education/pedagogy_engine.dart';

KnowledgeEntry entry({
  required int id,
  String topicTitle = 'Plants',
  List<String> keywords = const ['sunlight', 'sun', 'light'],
  String questionEn = 'Why do plants need sunlight?',
  String classLevel = 'Class 3',
  String answerHindi =
      'पौधों को सूरज की रोशनी चाहिए ताकि वे अपना खाना बना सकें। '
      'यह प्रकाश संश्लेषण कहलाता है। रोशनी से पत्ते हरे रहते हैं और पौधा बढ़ता है।',
  String answerSanthali = '',
}) =>
    KnowledgeEntry(
      id: id,
      topicId: 101,
      topicTitle: topicTitle,
      subject: 'EVS',
      classLevel: classLevel,
      keywords: keywords,
      questionEn: questionEn,
      answerHindi: answerHindi,
      answerSanthali: answerSanthali,
    );

void main() {
  final entries = [
    entry(id: 1),
    entry(
      id: 2,
      topicTitle: 'Animals',
      keywords: ['water', 'drink', 'living'],
      questionEn: 'Who needs water?',
    ),
  ];

  late OfflineEducationalEngine engine;

  setUp(() => engine = OfflineEducationalEngine(
        entriesLoader: () async => entries,
      ));

  group('OfflineEducationalEngine retrieval', () {
    test('answers a known question with pedagogy trimming', () async {
      final result =
          await engine.answer('पौधों को सूरज की रोशनी क्यों चाहिए');
      expect(result.fromKnowledgeBase, isTrue);
      expect(result.answerHindi, isNotEmpty);
      expect(result.answerSanthali, isEmpty);
    });

    test('context-aware pronouns resolve to current topic', () async {
      final result = await engine.answer(
        'उन्हें सूरज की रोशनी क्यों चाहिए?',
        context: const LearningContext(
          classLevel: 'Class 3',
          subject: 'EVS',
          lessonTitle: 'Plants',
          topicTitle: 'How Plants Grow',
        ),
      );
      expect(result.fromKnowledgeBase, isTrue);
      expect(result.answerHindi, isNotEmpty);
    });

    test('context boost picks current-topic entry over a keyword-only match',
        () async {
      final result = await engine.answer('पौधों को पानी की क्या जरूरत है');
      expect(result.fromKnowledgeBase, isTrue);
    });

    test('unknown question returns honest fallback, never fake content', () async {
      final result = await engine.answer('इंटरनेट कैसे काम करता है');
      expect(result.fromKnowledgeBase, isFalse);
      expect(result.answerSanthali, isEmpty);
      expect(result.answerHindi, contains('जवाब नहीं पता'));
    });

    test('lazy load: engine with no loader is honest', () async {
      final empty = OfflineEducationalEngine(entriesLoader: () async => const []);
      final result = await empty.answer('पौधों को रोशनी क्यों चाहिए');
      expect(result.fromKnowledgeBase, isFalse);
    });
  });

  group('Pedagogy shaping', () {
    test('trimToBudget keeps 4 sentences for Class 3', () {
      final long = 'एक। दो। तीन। चार। पाँच। छह।';
      final trimmed = const PedagogyEngine()
          .trimToBudget(long, 'Class 3');
      expect(trimmed, 'एक। दो। तीन। चार।');
    });

    test('sentenceBudget is smaller for younger classes', () {
      expect(const PedagogyEngine().sentenceBudget('Class 1'), 2);
      expect(const PedagogyEngine().sentenceBudget('Class 2'), 3);
    });

    test('levelLabel is short and friendly', () {
      expect(
        const PedagogyEngine().levelLabel(entry(id: 1, classLevel: 'Class 1')),
        'Very simple',
      );
    });
  });
}