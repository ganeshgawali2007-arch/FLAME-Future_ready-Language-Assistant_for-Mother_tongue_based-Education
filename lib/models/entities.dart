/// Persistent domain entities (mirror SQLite rows).
library;

import 'enums.dart';

class Teacher {
  Teacher({required this.id, required this.name});

  final int id;
  final String name;

  Map<String, Object?> toMap() => {'id': id, 'name': name};

  factory Teacher.fromMap(Map<String, Object?> m) =>
      Teacher(id: m['id'] as int, name: m['name'] as String);
}

class Classroom {
  Classroom({
    required this.id,
    required this.code,
    required this.name,
    required this.classLevel,
    required this.subject,
    required this.teacherName,
    required this.lessonTitle,
    required this.topicTitle,
    required this.phase,
    this.createdAt,
    this.endedAt,
  });

  final int id;
  final String code;
  final String name;
  final String classLevel;
  final String subject;
  final String teacherName;
  final String lessonTitle;
  final String topicTitle;
  ClassroomPhase phase;
  int? createdAt;
  int? endedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'code': code,
        'name': name,
        'class_level': classLevel,
        'subject': subject,
        'teacher_name': teacherName,
        'lesson_title': lessonTitle,
        'topic_title': topicTitle,
        'phase': phase.name,
        'created_at': createdAt,
        'ended_at': endedAt,
      };

  factory Classroom.fromMap(Map<String, Object?> m) => Classroom(
        id: m['id'] as int,
        code: m['code'] as String,
        name: m['name'] as String,
        classLevel: m['class_level'] as String,
        subject: m['subject'] as String,
        teacherName: m['teacher_name'] as String,
        lessonTitle: m['lesson_title'] as String,
        topicTitle: m['topic_title'] as String,
        phase: ClassroomPhase.values.firstWhere(
          (e) => e.name == m['phase'],
          orElse: () => ClassroomPhase.waiting,
        ),
        createdAt: m['created_at'] as int?,
        endedAt: m['ended_at'] as int?,
      );
}

class Student {
  Student({
    required this.id,
    required this.name,
    required this.classroomCode,
    this.connectedAt,
    this.disconnectedAt,
  });

  final int id;
  final String name;
  final String classroomCode;
  int? connectedAt;
  int? disconnectedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'classroom_code': classroomCode,
        'connected_at': connectedAt,
        'disconnected_at': disconnectedAt,
      };

  factory Student.fromMap(Map<String, Object?> m) => Student(
        id: m['id'] as int,
        name: m['name'] as String,
        classroomCode: m['classroom_code'] as String,
        connectedAt: m['connected_at'] as int?,
        disconnectedAt: m['disconnected_at'] as int?,
      );
}

class Lesson {
  Lesson({
    required this.id,
    required this.title,
    required this.subject,
    required this.classLevel,
  });

  final int id;
  final String title;
  final String subject;
  final String classLevel;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'subject': subject,
        'class_level': classLevel,
      };

  factory Lesson.fromMap(Map<String, Object?> m) => Lesson(
        id: m['id'] as int,
        title: m['title'] as String,
        subject: m['subject'] as String,
        classLevel: m['class_level'] as String,
      );
}

class Topic {
  Topic({
    required this.id,
    required this.lessonId,
    required this.title,
  });

  final int id;
  final int lessonId;
  final String title;

  Map<String, Object?> toMap() => {'id': id, 'lesson_id': lessonId, 'title': title};

  factory Topic.fromMap(Map<String, Object?> m) => Topic(
        id: m['id'] as int,
        lessonId: m['lesson_id'] as int,
        title: m['title'] as String,
      );
}

/// A classroom utterance captured during a live session.
class Utterance {
  Utterance({
    required this.id,
    required this.classroomCode,
    required this.speaker,
    required this.sourceText,
    required this.targetText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.timestamp,
  });

  final int id;
  final String classroomCode;
  final SpeakerRole speaker;
  final String sourceText;
  final String targetText;
  final AppLanguage sourceLanguage;
  final AppLanguage targetLanguage;
  final int timestamp;

  Map<String, Object?> toMap() => {
        'id': id,
        'classroom_code': classroomCode,
        'speaker': speaker.name,
        'source_text': sourceText,
        'target_text': targetText,
        'source_language': sourceLanguage.name,
        'target_language': targetLanguage.name,
        'timestamp': timestamp,
      };

  factory Utterance.fromMap(Map<String, Object?> m) => Utterance(
        id: m['id'] as int,
        classroomCode: m['classroom_code'] as String,
        speaker: SpeakerRole.values.firstWhere(
          (e) => e.name == m['speaker'],
          orElse: () => SpeakerRole.flame,
        ),
        sourceText: m['source_text'] as String,
        targetText: m['target_text'] as String,
        sourceLanguage: AppLanguage.values.firstWhere(
          (e) => e.name == m['source_language'],
        ),
        targetLanguage: AppLanguage.values.firstWhere(
          (e) => e.name == m['target_language'],
        ),
        timestamp: m['timestamp'] as int,
      );
}

/// Voice-bot knowledge entry (question patterns + lesson-aware answers).
class KnowledgeEntry {
  KnowledgeEntry({
    required this.id,
    required this.topicId,
    required this.topicTitle,
    required this.subject,
    required this.classLevel,
    required this.keywords,
    required this.questionEn,
    required this.answerHindi,
    required this.answerSanthali,
  });

  final int id;
  final int topicId;
  final String topicTitle;
  final String subject;
  final String classLevel;
  final List<String> keywords;
  final String questionEn;
  final String answerHindi;
  final String answerSanthali;

  Map<String, Object?> toMap() => {
        'id': id,
        'topic_id': topicId,
        'topic_title': topicTitle,
        'subject': subject,
        'class_level': classLevel,
        'keywords': keywords.join(','),
        'question_en': questionEn,
        'answer_hindi': answerHindi,
        'answer_santhali': answerSanthali,
      };

  factory KnowledgeEntry.fromMap(Map<String, Object?> m) => KnowledgeEntry(
        id: m['id'] as int,
        topicId: m['topic_id'] as int,
        topicTitle: m['topic_title'] as String,
        subject: m['subject'] as String,
        classLevel: m['class_level'] as String,
        keywords: (m['keywords'] as String).split(','),
        questionEn: m['question_en'] as String,
        answerHindi: m['answer_hindi'] as String,
        answerSanthali: m['answer_santhali'] as String,
      );
}

/// A row in the bilingual vocabulary / glossary.
class VocabularyItem {
  VocabularyItem({
    required this.id,
    required this.hindi,
    required this.santhali,
    required this.category,
    required this.classLevel,
  });

  final int id;
  final String hindi;
  final String santhali;
  final String category;
  final String classLevel;

  Map<String, Object?> toMap() => {
        'id': id,
        'hindi': hindi,
        'santhali': santhali,
        'category': category,
        'class_level': classLevel,
      };

  factory VocabularyItem.fromMap(Map<String, Object?> m) => VocabularyItem(
        id: m['id'] as int,
        hindi: m['hindi'] as String,
        santhali: m['santhali'] as String,
        category: m['category'] as String,
        classLevel: m['class_level'] as String,
      );
}