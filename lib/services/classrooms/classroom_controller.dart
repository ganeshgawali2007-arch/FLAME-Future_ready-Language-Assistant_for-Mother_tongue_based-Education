/// Live classroom state machine + offline broker.
///
/// A classroom has one lifecycle for the teacher and one for each student:
///   teacher: create → waiting → live → ended
///   student: join → waiting → live → ended
///
/// Everything runs locally. The offline broker below keeps teacher and
/// student sessions coherent on one device (demonstration), and is the seam
/// where a LAN/Wi-Fi-Direct sync service plugs in for real device pairing
/// (labelled [OfflineClassroomSyncIntegrationPoint]). No cloud is involved.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/entities.dart';
import '../../models/enums.dart';
import '../audio/audio_queue.dart';
import '../model_manager.dart';
import '../tts/offline_tts.dart';
import '../translation/translation_engine.dart';
import 'offline_classroom_sync.dart';

class ClassroomController extends ChangeNotifier {
  ClassroomController({
    required this.translator,
    required this.tts,
    this.models,
    this.sync,
    AudioQueue? audioQueue,
  }) : _audioQueue = audioQueue ??
            AudioQueue(
              (text, language) => tts.speak(text, language: language),
              interrupt: () => tts.stop(),
            );

  final TranslationEngine translator;
  final OfflineTextToSpeech tts;
  final ModelManagerController? models;

  /// Optional real two-device transport (LAN). When null, the in-process
  /// broker below keeps the single-device demo working exactly as before.
  final OfflineClassroomSync? sync;
  final AudioQueue _audioQueue;

  StreamSubscription<ClassroomSyncTurn>? _syncSub;
  StreamSubscription<String>? _hostSub;
  bool _applyingRemoteTurn = false;

  /// Ordered, non-overlapping speech playback for the session.
  AudioQueue get audioQueue => _audioQueue;

  ClassroomPhase phase = ClassroomPhase.notCreated;
  String? classCode;
  String? className;
  String? classLevel;
  String? subject;
  String? teacherName;
  String lessonTitle = '';
  String topicTitle = '';
  bool isTeacher = false;

  final List<String> _joinedStudents = [];
  final List<Utterance> _transcript = [];

  List<String> get joinedStudents => List.unmodifiable(_joinedStudents);
  List<Utterance> get transcript => List.unmodifiable(_transcript);

  LiveMode activeMode = LiveMode.listening;

  bool get isLive => phase == ClassroomPhase.live;
  bool get isWaiting => phase == ClassroomPhase.waiting;

  /// Teacher: create a session with a fresh code and QR-able identity.
  Future<void> teacherCreatesClass({
    required String name,
    required String level,
    required String subjectName,
    required String teacher,
    required String lesson,
    required String topic,
  }) async {
    className = name;
    classLevel = level;
    subject = subjectName;
    teacherName = teacher;
    lessonTitle = lesson;
    topicTitle = topic;
    isTeacher = true;
    // Real two-device hosting, when a transport is wired in. The LAN
    // transport issues its own session code; adopt it so the broker and the
    // network session share one code (students can join either way).
    var code = _generateCode();
    final s = sync;
    if (s != null) {
      final status = await s.createSession(
        name: className!,
        level: classLevel!,
        subject: subject!,
        teacherName: teacherName!,
        lesson: lessonTitle,
        topic: topicTitle,
      );
      if (status == ClassroomSyncStatus.hosting) {
        final issued = s.sessionInfo?['code'];
        if (issued != null && issued.isNotEmpty) code = issued;
        _listenToSync();
      }
    }
    classCode = code;
    _broker.register(
      classCode!,
      name: className!,
      level: classLevel!,
      subject: subject!,
      teacher: teacherName!,
      lesson: lessonTitle,
      topic: topicTitle,
    );
    phase = ClassroomPhase.waiting;
    notifyListeners();
  }

  /// Student: join an existing session by its visible code.
  bool studentJoins(String code, {required String studentName}) {
    final match = _broker.classroomForCode(code);
    if (match == null) return false;
    classCode = match;
    className = _broker.nameFor(code);
    classLevel = _broker.levelFor(code);
    subject = _broker.subjectFor(code);
    teacherName = _broker.teacherFor(code);
    lessonTitle = _broker.lessonFor(code);
    topicTitle = _broker.topicFor(code);
    // Keep the device's own role: a teacher who simulates a student on the
    // same device stays the teacher (single-device demo), while a fresh
    // student controller keeps isTeacher false.
    phase = ClassroomPhase.waiting;
    _broker.registerStudent(code, studentName);
    _joinedStudents.add(studentName);
    notifyListeners();
    return true;
  }

  /// Student: join a real session hosted on another device over the LAN
  /// transport. Returns null when no transport is wired (single-device mode).
  Future<bool?> studentJoinsRemote(String code,
      {required String studentName}) async {
    final s = sync;
    if (s == null) return null;
    final status = await s.joinSession(code);
    if (status != ClassroomSyncStatus.joined) return false;
    final info = s.sessionInfo ?? const {};
    classCode = code.trim().toUpperCase();
    className = info['name'] ?? '';
    classLevel = info['level'] ?? '';
    subject = info['subject'] ?? '';
    teacherName = info['teacher'] ?? '';
    lessonTitle = info['lesson'] ?? '';
    topicTitle = info['topic'] ?? '';
    isTeacher = false;
    phase = ClassroomPhase.waiting;
    _joinedStudents.add(studentName);
    _listenToSync();
    notifyListeners();
    return true;
  }

  void _listenToSync() {
    final s = sync;
    if (s == null || _syncSub != null) return;
    _syncSub = s.receiveTurn().listen(
      _onRemoteTurn,
      onDone: _onSyncClosed,
    );
    _hostSub = s.hostEvents().listen((event) {
      if (event == 'started' && phase == ClassroomPhase.waiting) {
        phase = ClassroomPhase.live;
        _loadSessionModels();
        notifyListeners();
      } else if (event == 'ended') {
        _onSyncClosed();
      }
    });
  }

  Future<void> _onRemoteTurn(ClassroomSyncTurn turn) async {
    if (_applyingRemoteTurn) return;
    _applyingRemoteTurn = true;
    try {
      // Translate locally through the same engine (never trust remote text).
      await processTurn(
        text: turn.text,
        speaker: turn.speaker,
        sourceLanguage: turn.sourceLanguage,
        fromRemote: true,
      );
    } finally {
      _applyingRemoteTurn = false;
    }
  }

  void _onSyncClosed() {
    // Teacher ended the session or the connection dropped for good.
    if (phase == ClassroomPhase.live || phase == ClassroomPhase.waiting) {
      phase = ClassroomPhase.ended;
      audioQueue.clear();
      notifyListeners();
    }
  }

  void startClass() {
    if (!isTeacher || classCode == null) return;
    phase = ClassroomPhase.live;
    _broker.classStarted(classCode!);
    sync?.sendHostEvent('started');
    _loadSessionModels();
    notifyListeners();
  }

  void endClass() {
    if (classCode == null) return;
    phase = ClassroomPhase.ended;
    audioQueue.clear();
    _broker.classEnded(classCode!);
    _teardownSync();
    _releaseSessionModels();
    notifyListeners();
  }

  void leaveClass() {
    if (classCode != null) _broker.studentLeft(classCode!);
    audioQueue.clear();
    _teardownSync();
    phase = ClassroomPhase.notCreated;
    classCode = null;
    _joinedStudents.clear();
    _releaseSessionModels();
    notifyListeners();
  }

  void _teardownSync() {
    _syncSub?.cancel();
    _syncSub = null;
    _hostSub?.cancel();
    _hostSub = null;
    sync?.leaveSession();
  }

  /// Load the models the live session needs (low-end rule: load only what the
  /// active screen uses, release it when the session ends). The Santhali
  /// warm-up is silent (load + silent inference probe, never audio) so the
  /// first translated turn does not stall mid-class; failures stay silent
  /// here and surface per-utterance through the audio queue instead.
  void _loadSessionModels() {
    final m = models;
    if (m == null) return;
    m.loadModel(FlmModelId.hindiSpeech).catchError((Object _) => false);
    m.loadModel(FlmModelId.hindiVoice).catchError((Object _) => false);
    m.loadModel(FlmModelId.santhaliVoice).catchError((Object _) => false);
  }

  void _releaseSessionModels() {
    models?.unloadModel(FlmModelId.hindiSpeech);
    models?.unloadModel(FlmModelId.hindiVoice);
    models?.unloadModel(FlmModelId.santhaliVoice);
  }

  /// Play the translated target line of [utterance] through the audio queue.
  /// Santhali speech fails explicitly (no voice pack) — never a wrong voice.
  Future<void> playTurn(Utterance utterance) async {
    if (utterance.targetText.isEmpty) return;
    audioQueue.enqueue(utterance.targetText, language: utterance.targetLanguage);
  }

  void setMode(LiveMode mode) {
    activeMode = mode;
    notifyListeners();
  }

  /// One classroom turn: speak [text] from [speaker], translate offline and
  /// queue the target-language speech. Never throws.
  Future<void> processTurn({
    required String text,
    required SpeakerRole speaker,
    required AppLanguage sourceLanguage,
    bool fromRemote = false,
  }) async {
    final turnId = '${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('FLAME_TURN $turnId START text="${text.length > 40 ? text.substring(0, 40) : text}" speaker=$speaker src=$sourceLanguage');
    if (text.isEmpty) return;
    final target = sourceLanguage == AppLanguage.hindi
        ? AppLanguage.santhali
        : AppLanguage.hindi;
    TranslationResult result;
    try {
      debugPrint('FLAME_TURN $turnId TRANSLATION_REQUEST src=$sourceLanguage tgt=$target');
      result = await translator.translate(
        text,
        source: sourceLanguage,
        target: target,
      );
    } catch (_) {
      result = const TranslationResult(
        sourceText: '',
        targetText: '',
        quality: TranslationQuality.fallback,
        canTranslate: false,
      );
    }
    _transcript.add(
      Utterance(
        id: _transcript.length + 1,
        classroomCode: classCode ?? '-',
        speaker: speaker,
        sourceText: text,
        targetText: result.canTranslate ? result.targetText : '',
        sourceLanguage: sourceLanguage,
        targetLanguage: target,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    debugPrint('FLAME_TURN $turnId NMT_RESULT canTranslate=${result.canTranslate} '
        'quality=${result.quality.name} '
        'target="${result.targetText.substring(0, result.targetText.length > 40 ? 40 : result.targetText.length)}"');
    notifyListeners();

    // Forward locally-originated turns to the remote peer(s). Remote turns
    // are never re-sent (no echo loops).
    final s = sync;
    if (!fromRemote && s != null) {
      final turn = ClassroomSyncTurn(
        speaker: speaker,
        text: text,
        sourceLanguage: sourceLanguage,
        targetLanguage: target,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      if (speaker == SpeakerRole.teacher) {
        await s.sendTeacherTurn(turn);
      } else {
        await s.sendStudentTurn(turn);
      }
    }
  }

  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String _generateCode() {
    final r = DateTime.now().millisecondsSinceEpoch;
    var seed = r;
    final buf = StringBuffer();
    for (var i = 0; i < 6; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      buf.write(_alphabet[seed % _alphabet.length]);
    }
    return buf.toString();
  }
}

/// Offline broker — keeps teacher/student sessions coherent on one device and
/// demos the whole flow with no network. This is the labelled seam where a
/// real offline pairing service (Wi-Fi Direct / hotspot LAN sync, as used by
/// the existing Kotlin prototype) is integrated for two-device classrooms.
class OfflineClassroomSyncIntegrationPoint {
  const OfflineClassroomSyncIntegrationPoint();
  static const String integrationLabel =
      'lib/services/classrooms/classroom_controller.dart';
}

class _Broker {
  final Map<String, String> _name = {};
  final Map<String, String> _teacher = {};
  final Map<String, String> _level = {};
  final Map<String, String> _subject = {};
  final Map<String, String> _lesson = {};
  final Map<String, String> _topic = {};

  void register(
    String code, {
    required String name,
    required String level,
    required String subject,
    required String teacher,
    required String lesson,
    required String topic,
  }) {
    _name[code] = name;
    _level[code] = level;
    _subject[code] = subject;
    _teacher[code] = teacher;
    _lesson[code] = lesson;
    _topic[code] = topic;
  }

  String? classroomForCode(String code) =>
      _name.containsKey(code.trim().toUpperCase()) ? code.trim().toUpperCase() : null;
  String nameFor(String code) => _name[code] ?? '';
  String levelFor(String code) => _level[code] ?? '';
  String subjectFor(String code) => _subject[code] ?? '';
  String teacherFor(String code) => _teacher[code] ?? '';
  String lessonFor(String code) => _lesson[code] ?? '';
  String topicFor(String code) => _topic[code] ?? '';

  void classStarted(String code) {}
  void classEnded(String code) {}
  void registerStudent(String code, String name) {}
  void studentLeft(String code) {}
}

final _Broker _broker = _Broker();