import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/enums.dart';
import 'package:flame/services/classrooms/lan_classroom_sync.dart';
import 'package:flame/services/classrooms/offline_classroom_sync.dart';

/// Transport-level tests for the real LAN sync. Two instances run in the same
/// process over loopback TCP; discovery is injected (no UDP broadcast needed),
/// which keeps the real socket/protocol path under test without flakiness.
void main() {
  LanClassroomSync teacher() => LanClassroomSync(localName: 'teacher');

  LanClassroomSync studentFor(LanClassroomSync t) {
    final info = t.sessionInfo!;
    return LanClassroomSync(
      localName: 'student',
      discoverer: (code) async => code == info['code']
          ? DiscoveredSession(
              host: InternetAddress.loopbackIPv4,
              port: int.parse(info['port']!),
              token: info['token']!,
            )
          : null,
    );
  }

  Future<LanClassroomSync> hostingTeacher() async {
    final t = teacher();
    final status = await t.createSession(
      name: 'Class 3A',
      level: 'Class 3',
      subject: 'EVS',
      teacherName: 'Priya',
      lesson: 'Plants',
      topic: 'How Plants Grow',
    );
    expect(status, ClassroomSyncStatus.hosting);
    return t;
  }

  ClassroomSyncTurn turn(SpeakerRole sp, String text, int ts) =>
      ClassroomSyncTurn(
        speaker: sp,
        text: text,
        sourceLanguage: AppLanguage.hindi,
        targetLanguage: AppLanguage.santhali,
        timestamp: ts,
      );

  tearDown(() async {
    // Individual tests dispose their own instances.
  });

  test('create + join: student joins with valid code and gets metadata',
      () async {
    final t = await hostingTeacher();
    final s = studentFor(t);
    final status = await s.joinSession(t.sessionInfo!['code']!);
    expect(status, ClassroomSyncStatus.joined);
    expect(s.sessionInfo!['name'], 'Class 3A');
    expect(s.sessionInfo!['teacher'], 'Priya');
    expect(s.sessionInfo!['lesson'], 'Plants');
    await pumpEventQueue();
    expect(t.clientCount, 1);
    await s.dispose();
    await t.dispose();
  });

  test('invalid session code is rejected', () async {
    final t = await hostingTeacher();
    final s = studentFor(t);
    final status = await s.joinSession('ZZZZZZ');
    expect(status, ClassroomSyncStatus.error);
    await s.dispose();
    await t.dispose();
  });

  test('invalid token is rejected by the host', () async {
    final t = await hostingTeacher();
    final info = t.sessionInfo!;
    final s = LanClassroomSync(
      discoverer: (code) async => DiscoveredSession(
        host: InternetAddress.loopbackIPv4,
        port: int.parse(info['port']!),
        token: 'WRONGTOKEN12',
      ),
    );
    final status = await s.joinSession(info['code']!);
    expect(status, ClassroomSyncStatus.error);
    await s.dispose();
    await t.dispose();
  });

  test('teacher -> student turn arrives in order', () async {
    final t = await hostingTeacher();
    final s = studentFor(t);
    await s.joinSession(t.sessionInfo!['code']!);
    await pumpEventQueue();

    final received = <ClassroomSyncTurn>[];
    final sub = s.receiveTurn().listen(received.add);

    await t.sendTeacherTurn(turn(SpeakerRole.teacher, 'पहला', 1));
    await t.sendTeacherTurn(turn(SpeakerRole.teacher, 'दूसरा', 2));
    await pumpEventQueue();

    expect(received.length, 2);
    expect(received[0].text, 'पहला');
    expect(received[1].text, 'दूसरा');
    expect(received[0].speaker, SpeakerRole.teacher);
    await sub.cancel();
    await s.dispose();
    await t.dispose();
  });

  test('student -> teacher turn arrives', () async {
    final t = await hostingTeacher();
    final s = studentFor(t);
    await s.joinSession(t.sessionInfo!['code']!);
    await pumpEventQueue();

    final received = <ClassroomSyncTurn>[];
    final sub = t.receiveTurn().listen(received.add);

    await s.sendStudentTurn(turn(SpeakerRole.student, 'सवाल', 10));
    await pumpEventQueue();

    expect(received.length, 1);
    expect(received.single.text, 'सवाल');
    expect(received.single.speaker, SpeakerRole.student);
    await sub.cancel();
    await s.dispose();
    await t.dispose();
  });

  test('two students: teacher relays student turn to the other student',
      () async {
    final t = await hostingTeacher();
    final s1 = studentFor(t);
    final s2 = studentFor(t);
    await s1.joinSession(t.sessionInfo!['code']!);
    await s2.joinSession(t.sessionInfo!['code']!);
    await pumpEventQueue();

    final gotByS2 = <ClassroomSyncTurn>[];
    final sub = s2.receiveTurn().listen(gotByS2.add);
    await s1.sendStudentTurn(turn(SpeakerRole.student, 'प्रश्न', 20));
    await pumpEventQueue();

    expect(gotByS2.length, 1);
    expect(gotByS2.single.text, 'प्रश्न');
    await sub.cancel();
    await s1.dispose();
    await s2.dispose();
    await t.dispose();
  });

  test('host event: started reaches joined students', () async {
    final t = await hostingTeacher();
    final s = studentFor(t);
    await s.joinSession(t.sessionInfo!['code']!);
    await pumpEventQueue();

    final events = <String>[];
    final sub = s.hostEvents().listen(events.add);
    await t.sendHostEvent('started');
    await pumpEventQueue();

    expect(events, contains('started'));
    await sub.cancel();
    await s.dispose();
    await t.dispose();
  });

  test('disconnect: teacher leaving ends the student session', () async {
    final t = await hostingTeacher();
    final s = studentFor(t);
    await s.joinSession(t.sessionInfo!['code']!);
    await pumpEventQueue();

    final events = <String>[];
    final sub = s.hostEvents().listen(events.add);
    await t.leaveSession();
    // The student makes 3 real reconnect attempts (1 s apart, plus socket
    // timeouts) before giving up and broadcasting 'ended'; poll until it
    // settles instead of racing a fixed delay.
    for (var i = 0; i < 80 && s.status != ClassroomSyncStatus.idle; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    expect(events, contains('ended'));
    expect(s.status, ClassroomSyncStatus.idle);
    await sub.cancel();
    await s.dispose();
    await t.dispose();
  });

  test('leaveSession: student disconnects cleanly from the host', () async {
    final t = await hostingTeacher();
    final s = studentFor(t);
    await s.joinSession(t.sessionInfo!['code']!);
    await pumpEventQueue();
    expect(t.clientCount, 1);

    await s.leaveSession();
    await pumpEventQueue();
    expect(t.clientCount, 0);
    expect(s.status, ClassroomSyncStatus.idle);
    await s.dispose();
    await t.dispose();
  });

  test('hosting twice reuses the instance (leave then create)', () async {
    final t = await hostingTeacher();
    final firstCode = t.sessionInfo!['code']!;
    final status = await t.createSession(
      name: 'Class 4B',
      level: 'Class 4',
      subject: 'EVS',
      teacherName: 'Priya',
      lesson: 'Water',
      topic: 'Sources',
    );
    expect(status, ClassroomSyncStatus.hosting);
    expect(t.sessionInfo!['code'], isNot(firstCode));
    await t.dispose();
  });
}
