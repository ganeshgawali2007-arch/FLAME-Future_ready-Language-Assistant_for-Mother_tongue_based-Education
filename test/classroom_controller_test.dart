import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/enums.dart';
import 'package:flame/services/audio/audio_queue.dart';
import 'package:flame/services/classrooms/classroom_controller.dart';
import 'package:flame/services/translation/educational_phrase_cache.dart';
import 'package:flame/services/translation/offline_translation_engine.dart';
import 'package:flame/services/tts/offline_tts.dart';

/// Fake TTS that never touches the platform plugin.
class _FakeTts extends OfflineTextToSpeech {
  @override
  Future<bool> speak(
    String text, {
    AppLanguage language = AppLanguage.hindi,
  }) async =>
      true;

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ClassroomController classroom;

  setUp(() {
    classroom = ClassroomController(
      translator: OfflineTranslationEngine(
        phraseCache: EducationalPhraseCache(
          phrases: const [
            PhrasePair(hindi: 'सब छात्र अपनी सीट पर बैठो', santhali: 'तर'),
          ],
        ),
      ),
      tts: _FakeTts(),
    );
  });

  test('teacher lifecycle: create → waiting → live → ended', () {
    expect(classroom.phase, ClassroomPhase.notCreated);

    classroom.teacherCreatesClass(
      name: 'Class 3A',
      level: 'Class 3',
      subjectName: 'EVS',
      teacher: 'Priya Ma\'am',
      lesson: 'Plants',
      topic: 'How Plants Grow',
    );
    expect(classroom.phase, ClassroomPhase.waiting);
    expect(classroom.isTeacher, isTrue);
    expect(classroom.classCode, isNotNull);
    expect(classroom.classCode!.length, 6);

    classroom.startClass();
    expect(classroom.phase, ClassroomPhase.live);
    expect(classroom.isLive, isTrue);

    classroom.endClass();
    expect(classroom.phase, ClassroomPhase.ended);
  });

  test('student joins by code and becomes live coherently', () async {
    await classroom.teacherCreatesClass(
      name: 'Class 3A',
      level: 'Class 3',
      subjectName: 'EVS',
      teacher: 'Priya Ma\'am',
      lesson: 'Plants',
      topic: 'How Plants Grow',
    );

    final ok = classroom.studentJoins(classroom.classCode!, studentName: 'Amit');
    expect(ok, isTrue);
    expect(classroom.joinedStudents, contains('Amit'));
    expect(classroom.phase, ClassroomPhase.waiting);

    classroom.startClass();
    expect(classroom.isLive, isTrue);
  });

  test('wrong join code is rejected honestly', () {
    final ok = classroom.studentJoins('ZZZZZZ', studentName: 'Amit');
    expect(ok, isFalse);
    expect(classroom.phase, ClassroomPhase.notCreated);
  });

  test('transcript records one teacher turn with offline translation', () async {
    await classroom.teacherCreatesClass(
      name: 'Class 3A',
      level: 'Class 3',
      subjectName: 'EVS',
      teacher: 'Priya Ma\'am',
      lesson: 'Plants',
      topic: 'How Plants Grow',
    );
    classroom.startClass();

    await classroom.processTurn(
      text: 'सब छात्र अपनी सीट पर बैठो',
      speaker: SpeakerRole.teacher,
      sourceLanguage: AppLanguage.hindi,
    );

    expect(classroom.transcript, hasLength(1));
    final u = classroom.transcript.first;
    expect(u.speaker, SpeakerRole.teacher);
    expect(u.sourceText, 'सब छात्र अपनी सीट पर बैठो');
    expect(u.targetText, 'तर');
  });

  test('playTurn enqueues the translated line through the audio queue',
      () async {
    await classroom.teacherCreatesClass(
      name: 'Class 3A',
      level: 'Class 3',
      subjectName: 'EVS',
      teacher: 'Priya Ma\'am',
      lesson: 'Plants',
      topic: 'How Plants Grow',
    );
    classroom.startClass();
    await classroom.processTurn(
      text: 'सब छात्र अपनी सीट पर बैठो',
      speaker: SpeakerRole.teacher,
      sourceLanguage: AppLanguage.hindi,
    );
    await classroom.playTurn(classroom.transcript.first);

    await pumpMicrotasks();
    expect(classroom.audioQueue.isSpeaking, isFalse);
    expect(
      classroom.audioQueue.jobs.every((j) => j.state == AudioJobState.done),
      isTrue,
    );
  });

  test('an untranslatable turn enqueues nothing and fails explicitly',
      () async {
    await classroom.teacherCreatesClass(
      name: 'Class 3A',
      level: 'Class 3',
      subjectName: 'EVS',
      teacher: 'Priya Ma\'am',
      lesson: 'Plants',
      topic: 'How Plants Grow',
    );
    classroom.startClass();
    await classroom.processTurn(
      text: 'आज हम पौधों के बारे में सीखेंगे',
      speaker: SpeakerRole.teacher,
      sourceLanguage: AppLanguage.hindi,
    );
    final u = classroom.transcript.first;
    expect(u.targetText, isEmpty);
    await classroom.playTurn(u);
    expect(classroom.audioQueue.jobs, isEmpty);
  });

  test('leave returns to notCreated and is idempotent', () {
    classroom.leaveClass();
    classroom.leaveClass();
    expect(classroom.phase, ClassroomPhase.notCreated);
    expect(classroom.classCode, isNull);
  });

  test('codes use a safe unambiguous alphabet and are 6 characters', () {
    const safe = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    for (var i = 0; i < 25; i++) {
      final c = ClassroomController(
        translator: OfflineTranslationEngine(
          phraseCache: EducationalPhraseCache(
            phrases: const [PhrasePair(hindi: 'x', santhali: 'y')],
          ),
        ),
        tts: _FakeTts(),
      );
      c.teacherCreatesClass(
        name: 'C',
        level: 'Class 3',
        subjectName: 'EVS',
        teacher: 'T',
        lesson: 'L',
        topic: 'P',
      );
      expect(c.classCode, isNotNull);
      expect(c.classCode!.length, 6);
      expect(
        c.classCode!.split('').every(safe.contains),
        isTrue,
        reason: 'code should avoid confusing chars like 0/O/1/I',
      );
    }
  });
}

Future<void> pumpMicrotasks() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}