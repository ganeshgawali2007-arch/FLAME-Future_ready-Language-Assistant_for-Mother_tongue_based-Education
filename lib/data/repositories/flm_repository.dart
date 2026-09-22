/// Repository facade over the local SQLite store.
///
/// All classroom data lives on-device; nothing here requires connectivity.
library;

import 'package:sqflite/sqflite.dart';

import '../../models/entities.dart';
import '../../models/enums.dart';
import '../database.dart';

class FlmRepository {
  FlmRepository(this._db);

  final Database _db;

  static Future<FlmRepository> open() async {
    final db = await FlmDatabase.instance.db;
    return FlmRepository(db);
  }

  // ---------- settings ----------

  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------- classes ----------

  Future<Classroom?> findClassroomByCode(String code) async {
    final rows = await _db.query(
      'classes',
      where: 'code = ?',
      whereArgs: [code.trim().toUpperCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Classroom.fromMap(rows.first);
  }

  Future<Classroom> insertClassroom(Classroom c) async {
    final id = await _db.insert('classes', c.toMap());
    return Classroom(
      id: id,
      code: c.code,
      name: c.name,
      classLevel: c.classLevel,
      subject: c.subject,
      teacherName: c.teacherName,
      lessonTitle: c.lessonTitle,
      topicTitle: c.topicTitle,
      phase: c.phase,
      createdAt: c.createdAt,
      endedAt: c.endedAt,
    );
  }

  Future<void> updateClassroomPhase(String code, ClassroomPhase phase) async {
    final update = <String, Object?>{
      'phase': phase.name,
    };
    if (phase == ClassroomPhase.ended) {
      update['ended_at'] = DateTime.now().millisecondsSinceEpoch;
    }
    await _db.update(
      'classes',
      update,
      where: 'code = ?',
      whereArgs: [code],
    );
  }

  Future<List<Classroom>> recentClasses({int limit = 20}) async {
    final rows = await _db.query(
      'classes',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(Classroom.fromMap).toList();
  }

  Future<List<Utterance>> utterancesFor(String classroomCode) async {
    final rows = await _db.query(
      'translations',
      where: 'classroom_code = ?',
      whereArgs: [classroomCode],
      orderBy: 'timestamp ASC',
    );
    return rows.map(Utterance.fromMap).toList();
  }

  Future<void> insertUtterance(Utterance u) async {
    await _db.insert('translations', u.toMap());
  }

  // ---------- students ----------

  Future<void> addStudent(Student s) async {
    await _db.insert('students', s.toMap());
  }

  Future<List<Student>> studentsIn(String classroomCode) async {
    final rows = await _db.query(
      'students',
      where: 'classroom_code = ?',
      whereArgs: [classroomCode],
      orderBy: 'id ASC',
    );
    return rows.map(Student.fromMap).toList();
  }

  // ---------- lessons & knowledge ----------

  Future<List<Lesson>> lessons({String? classLevel}) async {
    final rows = await _db.query(
      'lessons',
      where: classLevel == null ? null : 'class_level = ?',
      whereArgs: classLevel == null ? null : [classLevel],
      orderBy: 'id ASC',
    );
    return rows.map(Lesson.fromMap).toList();
  }

  Future<List<Topic>> topicsFor(int lessonId) async {
    final rows = await _db.query(
      'topics',
      where: 'lesson_id = ?',
      whereArgs: [lessonId],
      orderBy: 'id ASC',
    );
    return rows.map(Topic.fromMap).toList();
  }

  Future<List<KnowledgeEntry>> knowledgeEntries() async {
    final rows = await _db.query('knowledge');
    return rows.map(KnowledgeEntry.fromMap).toList();
  }

  Future<List<VocabularyItem>> vocabulary() async {
    final rows = await _db.query(
      'vocabulary',
      orderBy: 'class_level ASC, category ASC',
    );
    return rows.map(VocabularyItem.fromMap).toList();
  }

  // ---------- progress ----------

  Future<void> recordProgress(int studentId, int lessonId, int score) async {
    await _db.insert(
      'progress',
      {
        'student_id': studentId,
        'lesson_id': lessonId,
        'score': score,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }
}