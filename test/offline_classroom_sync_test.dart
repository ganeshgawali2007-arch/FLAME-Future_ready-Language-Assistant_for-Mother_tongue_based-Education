import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/enums.dart';
import 'package:flame/services/classrooms/offline_classroom_sync.dart';

/// The two-device sync surface is intentionally an INTERFACE ONLY in this
/// task. This test pins the contract so a real offline transport (hotspot
/// LAN / Wi-Fi Direct) can be dropped in without touching classroom code.
void main() {
  test('OfflineClassroomSync interface contract holds', () async {
    final sync = _RecordingSync();
    expect(await sync.createSession(
      name: 'Class 3A',
      level: 'Class 3',
      subject: 'EVS',
      teacherName: 'Priya',
      lesson: 'Plants',
      topic: 'How Plants Grow',
    ), isNot(equals(ClassroomSyncStatus.error)));
    expect(await sync.joinSession('ABC234'), ClassroomSyncStatus.joined);

    await sync.sendTeacherTurn(
      const ClassroomSyncTurn(
        speaker: SpeakerRole.teacher,
        text: 'शुभ प्रभात',
        sourceLanguage: AppLanguage.hindi,
        targetLanguage: AppLanguage.santhali,
        timestamp: 0,
      ),
    );

    final turns = <ClassroomSyncTurn>[];
    final sub = sync.receiveTurn().listen(turns.add);
    await sync.sendStudentTurn(
      const ClassroomSyncTurn(
        speaker: SpeakerRole.student,
        text: 'x',
        sourceLanguage: AppLanguage.santhali,
        targetLanguage: AppLanguage.hindi,
        timestamp: 1,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    // FIFO: the earlier pre-queued teacher turn, then the student turn.
    expect(turns, hasLength(2));
    expect(turns.first.speaker, SpeakerRole.teacher);
    expect(turns.last.speaker, SpeakerRole.student);

    await sync.leaveSession();
  });
}

class _RecordingSync implements OfflineClassroomSync {
  final List<ClassroomSyncTurn> _inbound = [];

  @override
  Future<ClassroomSyncStatus> createSession({
    required String name,
    required String level,
    required String subject,
    required String teacherName,
    required String lesson,
    required String topic,
  }) async =>
      ClassroomSyncStatus.hosting;

  @override
  Future<ClassroomSyncStatus> joinSession(String code) async =>
      ClassroomSyncStatus.joined;

  @override
  Future<void> leaveSession() async {}

  @override
  Stream<ClassroomSyncTurn> receiveTurn() async* {
    while (_inbound.isNotEmpty) {
      yield _inbound.removeAt(0);
    }
  }

  @override
  Future<void> sendStudentTurn(ClassroomSyncTurn turn) async =>
      _inbound.add(turn);

  @override
  Future<void> sendTeacherTurn(ClassroomSyncTurn turn) async =>
      _inbound.add(turn);

  @override
  Map<String, String>? get sessionInfo => null;

  @override
  Stream<String> hostEvents() => const Stream<String>.empty();

  @override
  Future<void> sendHostEvent(String event) async {}
}