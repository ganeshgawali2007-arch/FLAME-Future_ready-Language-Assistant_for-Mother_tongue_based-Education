/// Local SQLite schema + access. No cloud database is used for classroom
/// operation. Loaded lazily on first screen that needs persistence.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'seed/seed_data.dart';

/// Schema version — bump only with a migration handler.
const int schemaVersion = 1;

class FlmDatabase {
  FlmDatabase._();
  static final FlmDatabase instance = FlmDatabase._();

  Database? _db;

  /// Set a factory for tests (sqflite_common_ffi) via
  /// `databaseFactory = databaseFactoryFfi` before first open.
  Database? get database => _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'flame.db');
    return openDatabase(
      path,
      version: schemaVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database d, int version) async {
    // Teachers & students.
    await d.execute('''
      CREATE TABLE teachers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE students(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        classroom_code TEXT NOT NULL,
        connected_at INTEGER,
        disconnected_at INTEGER
      )
    ''');

    // Classes & curriculum.
    await d.execute('''
      CREATE TABLE classes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        class_level TEXT NOT NULL,
        subject TEXT NOT NULL,
        teacher_name TEXT NOT NULL,
        lesson_title TEXT NOT NULL,
        topic_title TEXT NOT NULL,
        phase TEXT NOT NULL,
        created_at INTEGER,
        ended_at INTEGER
      )
    ''');
    await d.execute('''
      CREATE TABLE lessons(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        subject TEXT NOT NULL,
        class_level TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE topics(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lesson_id INTEGER NOT NULL,
        title TEXT NOT NULL
      )
    ''');

    // Session transcript cache.
    await d.execute('''
      CREATE TABLE translations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        classroom_code TEXT NOT NULL,
        speaker TEXT NOT NULL,
        source_text TEXT NOT NULL,
        target_text TEXT NOT NULL,
        source_language TEXT NOT NULL,
        target_language TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    // Learning content.
    await d.execute('''
      CREATE TABLE vocabulary(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hindi TEXT NOT NULL,
        santhali TEXT NOT NULL,
        category TEXT NOT NULL,
        class_level TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE flashcards(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vocabulary_id INTEGER,
        front TEXT NOT NULL,
        back TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE worksheets(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lesson_id INTEGER,
        title TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE quiz_questions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lesson_id INTEGER NOT NULL,
        question TEXT NOT NULL,
        options TEXT NOT NULL,
        correct_index INTEGER NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE progress(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        lesson_id INTEGER NOT NULL,
        score INTEGER NOT NULL DEFAULT 0,
        completed_at INTEGER
      )
    ''');
    await d.execute('''
      CREATE TABLE knowledge(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        topic_id INTEGER NOT NULL,
        topic_title TEXT NOT NULL,
        subject TEXT NOT NULL,
        class_level TEXT NOT NULL,
        keywords TEXT NOT NULL,
        question_en TEXT NOT NULL,
        answer_hindi TEXT NOT NULL,
        answer_santhali TEXT NOT NULL
      )
    ''');

    // App settings key/value.
    await d.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _seed(d);
  }

  Future<void> _seed(Database d) async {
    final batch = d.batch();

    for (final t in _seedTeachers) {
      batch.insert('teachers', t);
    }
    for (final l in _seedLessons) {
      batch.insert('lessons', l);
    }
    for (final t in _seedTopics) {
      batch.insert('topics', t);
    }
    for (final v in _seedVocabulary) {
      batch.insert('vocabulary', v);
    }
    for (final k in SeedLessons.knowledge) {
      batch.insert('knowledge', k.toMap());
    }

    // Default settings.
    batch.insert(
      'settings',
      {'key': 'onboarded', 'value': 'false'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    batch.insert(
      'settings',
      {'key': 'language_direction', 'value': 'hindiToSanthali'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await batch.commit(noResult: true);
  }

  // ---- seed content en route to SQLite ----

  List<Map<String, Object?>> get _seedTeachers => [
        {'id': 1, 'name': 'Priya Ma\'am'},
      ];

  List<Map<String, Object?>> get _seedLessons => [
        for (final l in SeedLessons.lessons) l.toMap(),
      ];

  List<Map<String, Object?>> get _seedTopics => [
        for (final t in SeedLessons.topics) t.toMap(),
      ];

  List<Map<String, Object?>> get _seedVocabulary => [
        // Verified classroom phrases shipped with the corpus.
        {'id': 1, 'hindi': 'सब छात्र अपनी सीट पर बैठो', 'santhali': 'Sab chhatra apni seat re busa.', 'category': 'Discipline', 'class_level': 'Class 1'},
        {'id': 2, 'hindi': 'अपनी पेंसिल निकालो', 'santhali': 'Aenke apni pencil nikalo.', 'category': 'Instruction', 'class_level': 'Class 1'},
        {'id': 3, 'hindi': 'अब हम कहानी पढ़ेंगे', 'santhali': 'Tehen aab gerek kahani padha.', 'category': 'Activity', 'class_level': 'Class 2'},
        {'id': 4, 'hindi': 'हाथ धोकर खाना खाओ', 'santhali': 'Ti arub korme jom me.', 'category': 'Routine', 'class_level': 'Class 2'},
      ];
}