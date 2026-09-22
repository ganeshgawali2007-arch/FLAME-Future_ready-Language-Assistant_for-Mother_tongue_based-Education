/// Clean interface for offline two-device classroom sync.
///
/// INTERFACE ONLY — deliberately NOT implemented in this task. Requirement:
/// teacher phone ↔ student phone over an offline local transport (hotspot LAN /
/// Wi-Fi Direct). The current in-process demo broker in
/// [lessons/classrooms/classroom_controller.dart] remains single-device and is
/// NOT presented as two-device sync. No cloud is involved in either design.
library;

import '../../models/enums.dart';

enum ClassroomSyncStatus { idle, hosting, joined, error }

/// A single turn exchanged between peers during a live class.
class ClassroomSyncTurn {
  const ClassroomSyncTurn({
    required this.speaker,
    required this.text,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.timestamp,
  });

  final SpeakerRole speaker;
  final String text;
  final AppLanguage sourceLanguage;
  final AppLanguage targetLanguage;
  final int timestamp;
}

/// Contract every future offline transport must satisfy. Implementations can
/// be exchanged without touching classroom code.
abstract class OfflineClassroomSync {
  /// Host a new session; other devices join via [joinSession].
  Future<ClassroomSyncStatus> createSession({
    required String name,
    required String level,
    required String subject,
    required String teacherName,
    required String lesson,
    required String topic,
  });

  Future<ClassroomSyncStatus> joinSession(String code);

  /// Session metadata visible after create/join (code, class name, lesson...).
  /// Null when no session is active.
  Map<String, String>? get sessionInfo;

  Future<void> sendTeacherTurn(ClassroomSyncTurn turn);

  Future<void> sendStudentTurn(ClassroomSyncTurn turn);

  /// Turns arriving from the remote peer.
  Stream<ClassroomSyncTurn> receiveTurn();

  /// Host lifecycle signals broadcast to all peers: `started` when the
  /// teacher begins the class, `ended` when the host closes the session.
  Stream<String> hostEvents();

  /// Teacher: broadcast a lifecycle signal (`started` / `ended`).
  Future<void> sendHostEvent(String event);

  Future<void> leaveSession();
}