/// Starter curriculum + knowledge base bundled with FLAME.
///
/// Honesty rule honoured here:
///   "Do not claim an offline AI feature works unless it actually works
///    without internet. If a real model is not yet available, build the
///    interface and abstraction cleanly and label the integration point."
///
/// - Hindi answers below are authored, real curriculum content.
/// - `answerSanthali` is intentionally authored ONLY where a verified
///   bilingual corpus sentence supplies the wording (see entries with
///   `verifiedSanthali: true`). Never fabricated here.
/// - The voice-bot renderer falls back to Hindi speech until a Santhali
///   content pack (educator-reviewed, SCERT-style) or an IndicTrans2-based
///   ONNX engine is installed. That integration point is labelled in
///   [SanthaliResponseRenderer].
library;

import '../../models/entities.dart';

class SeedLessons {
  SeedLessons._();

  static final List<Lesson> lessons = [
    Lesson(id: 1, title: 'Plants', subject: 'EVS', classLevel: 'Class 3'),
    Lesson(id: 2, title: 'Animals', subject: 'EVS', classLevel: 'Class 3'),
    Lesson(id: 3, title: 'Water', subject: 'EVS', classLevel: 'Class 2'),
    Lesson(id: 4, title: 'My Body', subject: 'EVS', classLevel: 'Class 1'),
    Lesson(id: 5, title: 'Food', subject: 'EVS', classLevel: 'Class 2'),
    Lesson(id: 6, title: 'Weather', subject: 'EVS', classLevel: 'Class 3'),
  ];

  static final List<Topic> topics = [
    Topic(id: 101, lessonId: 1, title: 'Parts of a Plant'),
    Topic(id: 102, lessonId: 1, title: 'How Plants Grow'),
    Topic(id: 103, lessonId: 2, title: 'Animals Around Us'),
    Topic(id: 104, lessonId: 3, title: 'Where We Get Water'),
    Topic(id: 105, lessonId: 4, title: 'My Five Senses'),
    Topic(id: 106, lessonId: 5, title: 'Healthy Food'),
    Topic(id: 107, lessonId: 6, title: 'Sun, Rain and Wind'),
  ];

  /// Educational content used by the Ask FLAME engine and the live classroom.
  ///
  /// `keywords` are what allow retrieval; the canonical English question keeps
  /// intent matching language-neutral. Answers are age-appropriate for the
  /// target [KnowledgeEntry.classLevel].
  static final List<KnowledgeEntry> knowledge = [
    KnowledgeEntry(
      id: 1,
      topicId: 102,
      topicTitle: 'How Plants Grow',
      subject: 'EVS',
      classLevel: 'Class 3',
      keywords: ['सूरज', 'रोशनी', 'धूप', 'sun', 'sunlight', 'सूर्य', 'पौधे', 'plants'],
      questionEn: 'Why do plants need sunlight?',
      answerHindi:
          'पौधे सूरज की रोशनी की मदद से अपना खाना खुद बनाते हैं। '
          'रोशनी से पत्तियाँ हरी रहती हैं और पौधा बड़ा होकर ताज़ी हवा देता है। '
          'इसलिए हर पौधे को सूरज की रोशनी चाहिए।',
      // Santhali: pending educator-reviewed pack (see file doc comment).
      answerSanthali: '',
    ),
    KnowledgeEntry(
      id: 2,
      topicId: 102,
      topicTitle: 'How Plants Grow',
      subject: 'EVS',
      classLevel: 'Class 3',
      keywords: ['पानी', 'सींचना', 'सूख', 'water', 'सिञ्चन'],
      questionEn: 'Why do plants need water?',
      answerHindi:
          'पौधों को पानी इसलिए चाहिए क्योंकि पानी ही भोजन को जड़ से पत्तियों तक पहुँचाता है। '
          'बिना पानी के पौधे सूख जाते हैं। इसलिए हम पौधों को रोज़ पानी देते हैं।',
      answerSanthali: '',
    ),
    KnowledgeEntry(
      id: 3,
      topicId: 101,
      topicTitle: 'Parts of a Plant',
      subject: 'EVS',
      classLevel: 'Class 3',
      keywords: ['जड़', 'मिट्टी', 'ज़मीन', 'soil', 'जमिन'],
      questionEn: 'Why do plants need soil?',
      answerHindi:
          'पौधे मिट्टी में उगते हैं। मिट्टी से जड़ें पानी और भोजन के कण लेती हैं '
          'और पौधे को ज़मीन पर खड़ा रखती हैं।',
      answerSanthali: '',
    ),
    KnowledgeEntry(
      id: 4,
      topicId: 106,
      topicTitle: 'Healthy Food',
      subject: 'EVS',
      classLevel: 'Class 2',
      keywords: ['खाना', 'भोजन', 'ताकत', 'स्वस्थ', 'food', 'मजबूत'],
      questionEn: 'Why do we need food?',
      answerHindi:
          'खाना खाने से हमें ताकत मिलती है और हमारा शरीर बड़ा होता है। '
          'सब्ज़ियाँ, दूध और फल हमें स्वस्थ रखते हैं।',
      answerSanthali: '',
    ),
    KnowledgeEntry(
      id: 5,
      topicId: 101,
      topicTitle: 'Parts of a Plant',
      subject: 'EVS',
      classLevel: 'Class 1',
      keywords: ['फूल', 'रंग', 'सुंदर', 'मधुमक्खी', 'flower'],
      questionEn: 'Why do flowers have colour?',
      answerHindi:
          'फूलों का रंग उन्हें सुंदर बनाता है और मधुमक्खियाँ फूल पर आकर रस ले जाती हैं।',
      answerSanthali: '',
    ),
    KnowledgeEntry(
      id: 6,
      topicId: 107,
      topicTitle: 'Sun, Rain and Wind',
      subject: 'EVS',
      classLevel: 'Class 3',
      keywords: ['बारिश', 'पानी', 'बादल', 'rain', 'बरसात'],
      questionEn: 'Where does rain come from?',
      answerHindi:
          'सूरज की गर्मी से नदियों और तालाबों का पानी भाप बनकर ऊपर जाता है। '
          'वहाँ ठंड से वह बादल बनता है और बारिश की बूँदें बनकर नीचे आती है।',
      answerSanthali: '',
    ),
    KnowledgeEntry(
      id: 7,
      topicId: 105,
      topicTitle: 'My Five Senses',
      subject: 'EVS',
      classLevel: 'Class 1',
      keywords: ['आँख', 'देख', 'कान', 'सुन', 'नाक', 'सूँघ', 'eyes', 'ears', 'nose'],
      questionEn: 'What do our eyes do?',
      answerHindi:
          'हमारी आँखें देखती हैं, कान सुनते हैं और नाक सूँघती है। '
          'इन्हीं से हम दुनिया को जान पाते हैं।',
      answerSanthali: '',
    ),
    KnowledgeEntry(
      id: 8,
      topicId: 103,
      topicTitle: 'Animals Around Us',
      subject: 'EVS',
      classLevel: 'Class 3',
      keywords: ['जानवर', 'पालतू', 'गाय', 'घर', 'animals', 'animals around us'],
      questionEn: 'Why do some animals live with people?',
      answerHindi:
          'कुछ जानवर हमारे साथ घर पर रहते हैं, जैसे गाय, कुत्ता और मुर्गी। '
          'वे हमें दूध, अंडे और मदद देते हैं, और हम उन्हें खाना और सुरक्षा देते हैं।',
      answerSanthali: '',
    ),
    KnowledgeEntry(
      id: 9,
      topicId: 104,
      topicTitle: 'Where We Get Water',
      subject: 'EVS',
      classLevel: 'Class 2',
      keywords: ['पानी', 'कुआँ', 'नदी', 'नल', 'water', 'river', 'well'],
      questionEn: 'Where do we get water from?',
      answerHindi:
          'पानी कुँए, नदी, तालाब और नल से मिलता है। बारिश इसका सबसे बड़ा स्रोत है।',
      answerSanthali: '',
    ),
  ];
}