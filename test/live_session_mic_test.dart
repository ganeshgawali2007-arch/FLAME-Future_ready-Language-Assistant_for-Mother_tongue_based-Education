import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/enums.dart';
import 'package:flame/screens/live_session_screen.dart';
import 'package:flame/services/asr/offline_speech_recognizer.dart';
import 'package:flame/services/classrooms/classroom_controller.dart';
import 'package:flame/services/offline_status_service.dart';
import 'package:flame/services/permissions/permission_service.dart';
import 'package:flame/services/translation/translation_engine.dart';
import 'package:flame/services/tts/offline_tts.dart';
import 'package:flame/services/voice/live_session_mic_controller.dart';
import 'package:flame/widgets/sanathali_text.dart';

/// Regression suite for the live-classroom microphone → recognition →
/// translation pipeline (the physical-device reports showed the mic was not
/// driving any recognizer at all, plus "no Santhali" outputs).
class _FakePermissions extends PermissionService {
  _FakePermissions(this.result);

  MicPermissionState result;
  int requests = 0;

  @override
  Future<MicPermissionState> requestMicrophone() async {
    requests++;
    return result;
  }

  @override
  Future<MicPermissionState> checkMicrophone() async => result;

  @override
  Future<bool> openSettings() async => true;
}

class _FakeRecognizer implements OfflineSpeechRecognizer {
  bool ready = true;
  bool startedListening = false;
  int stopCalls = 0;
  int warmUpCalls = 0;
  final StreamController<RecognitionResult> _events =
      StreamController<RecognitionResult>.broadcast();

  bool get hasListener => _events.hasListener;

  @override
  bool get isReady => ready;

  @override
  String get failureReason => 'fake failure';

  @override
  Future<void> warmUp() async {
    warmUpCalls++;
  }

  @override
  Stream<RecognitionResult> listen() {
    startedListening = true;
    return _events.stream;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  void emitPartial(String transcript) => _events
      .add(RecognitionResult(transcript: transcript, isFinal: false));

  void emitFinal(String transcript) =>
      _events.add(RecognitionResult(transcript: transcript, isFinal: true));
}

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

class _FakeTranslator implements TranslationEngine {
  int calls = 0;
  String lastText = '';
  bool throwOnTranslate = false;
  TranslationResult result = const TranslationResult(
    sourceText: '',
    targetText: '',
    quality: TranslationQuality.fallback,
    canTranslate: false,
  );

  @override
  bool get isReady => true;

  @override
  Future<TranslationResult> translate(
    String text, {
    required AppLanguage source,
    required AppLanguage target,
  }) async {
    calls++;
    lastText = text;
    if (throwOnTranslate) throw StateError('boom');
    return result;
  }
}

Future<void> pumpMicro() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiveSessionMicController', () {
    test('partial hypotheses replace the previous one, never append', () async {
      final rec = _FakeRecognizer();
      final mic = LiveSessionMicController(
        permissions: _FakePermissions(MicPermissionState.granted),
        recognizerFactory: () => rec,
      );
      await mic.start();
      expect(mic.listening, isTrue);

      rec.emitPartial('सुप्रभात');
      await pumpMicro();
      expect(mic.partial, 'सुप्रभात');

      rec.emitPartial('सुप्रभात बच्चों');
      await pumpMicro();
      expect(mic.partial, 'सुप्रभात बच्चों');
      expect(mic.partial.contains('सुप्रभात सुप्रभात'), isFalse);

      mic.dispose();
    });

    test('a final result triggers exactly one onFinal callback', () async {
      int finals = 0;
      String? last;
      final rec = _FakeRecognizer();
      final mic = LiveSessionMicController(
        permissions: _FakePermissions(MicPermissionState.granted),
        recognizerFactory: () => rec,
        onFinal: (text) async {
          finals++;
          last = text;
        },
      );
      await mic.start();
      rec.emitFinal('सुप्रभात बच्चों');
      await pumpMicro();
      expect(finals, 1);
      expect(last, 'सुप्रभात बच्चों');
      expect(mic.listening, isFalse);
      mic.dispose();
    });

    test('duplicate final events do not duplicate the callback', () async {
      int finals = 0;
      final rec = _FakeRecognizer();
      final mic = LiveSessionMicController(
        permissions: _FakePermissions(MicPermissionState.granted),
        recognizerFactory: () => rec,
        onFinal: (_) async {
          finals++;
        },
      );
      await mic.start();
      rec.emitFinal('सुप्रभात बच्चों');
      await pumpMicro();
      rec.emitFinal('सुप्रभात बच्चों');
      await pumpMicro();
      expect(finals, 1);
      mic.dispose();
    });

    test('dispose cancels the active recognizer subscription', () async {
      final rec = _FakeRecognizer();
      final mic = LiveSessionMicController(
        permissions: _FakePermissions(MicPermissionState.granted),
        recognizerFactory: () => rec,
      );
      await mic.start();
      expect(rec.hasListener, isTrue);
      mic.dispose();
      await pumpMicro();
      expect(rec.hasListener, isFalse);
      expect(rec.stopCalls, greaterThanOrEqualTo(1));
    });

    test('starting a new capture cancels the previous subscription', () async {
      final rec = _FakeRecognizer();
      final mic = LiveSessionMicController(
        permissions: _FakePermissions(MicPermissionState.granted),
        recognizerFactory: () => rec,
      );
      await mic.start();
      await mic.stop();
      expect(rec.hasListener, isFalse);
      await mic.start();
      expect(rec.hasListener, isTrue);
      mic.dispose();
    });

    test('denied mic never enters a fake listening state', () async {
      final rec = _FakeRecognizer();
      final mic = LiveSessionMicController(
        permissions: _FakePermissions(MicPermissionState.denied),
        recognizerFactory: () => rec,
      );
      await mic.start();
      expect(mic.listening, isFalse);
      expect(mic.errorMessage, isNotNull);
      expect(rec.startedListening, isFalse);
      mic.dispose();
    });

    test('permanently denied mic shows the settings message, not listening',
        () async {
      final rec = _FakeRecognizer();
      final mic = LiveSessionMicController(
        permissions: _FakePermissions(MicPermissionState.permanentlyDenied),
        recognizerFactory: () => rec,
      );
      await mic.start();
      expect(mic.listening, isFalse);
      expect(mic.errorMessage, contains('Open Android settings'));
      expect(rec.startedListening, isFalse);
      mic.dispose();
    });
  });

  group('LiveSessionView voice round-trip', () {
    late _FakeTranslator translator;

    setUp(() {
      translator = _FakeTranslator();
    });

    Future<(ClassroomController, _FakeRecognizer)> pumpLiveClassroom(
      WidgetTester tester, {
      MicPermissionState permission = MicPermissionState.granted,
    }) async {
      final classroom = ClassroomController(
        translator: translator,
        tts: _FakeTts(),
      );
      final rec = _FakeRecognizer();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveSessionView(
              classroom: classroom,
              offline: OfflineStatusService(),
              permissions: _FakePermissions(permission),
              recognizerFactory: () => rec,
            ),
          ),
        ),
      );
      await classroom.teacherCreatesClass(
        name: 'Class 3 EVS',
        level: 'Class 3',
        subjectName: 'EVS',
        teacher: 'Priya Ma\'am',
        lesson: 'Plants',
        topic: 'Parts of a Plant',
      );
      classroom.startClass();
      await tester.pump();
      return (classroom, rec);
    }

    testWidgets(
        'speaking a final transcript produces EXACTLY one translated turn',
        (tester) async {
      translator.result = const TranslationResult(
        sourceText: '',
        targetText: 'सुप्रभात बच्चों',
        quality: TranslationQuality.exact,
        canTranslate: true,
      );
      final (classroom, rec) = await pumpLiveClassroom(tester);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump();
      expect(rec.startedListening, isTrue);

      rec.emitFinal('सुप्रभात बच्चों');
      await tester.pump();
      await tester.pump();

      expect(classroom.transcript, hasLength(1));
      final turn = classroom.transcript.single;
      expect(turn.sourceText, 'सुप्रभात बच्चों');
      expect(translator.calls, 1);
      expect(translator.lastText, 'सुप्रभात बच्चों');
    });

    testWidgets('empty translation renders the source with NO Santhali line',
        (tester) async {
      translator.result = const TranslationResult(
        sourceText: '',
        targetText: '',
        quality: TranslationQuality.fallback,
        canTranslate: false,
      );
      final (classroom, rec) = await pumpLiveClassroom(tester);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump();
      rec.emitFinal('आज हम पौधों के बारे में सीखेंगे');
      await tester.pump();
      await tester.pump();

      expect(classroom.transcript, hasLength(1));
      expect(classroom.transcript.single.targetText, isEmpty);
      expect(tester.takeException(), isNull);
      expect(find.byType(SanathaliText), findsNothing);
      expect(find.text('आज हम पौधों के बारे में सीखेंगे'), findsOneWidget);
    });

    testWidgets('translation failure never crashes and stays honest',
        (tester) async {
      translator.throwOnTranslate = true;
      final (classroom, rec) = await pumpLiveClassroom(tester);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump();
      rec.emitFinal('सुप्रभात बच्चों');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(classroom.transcript, hasLength(1));
      expect(classroom.transcript.single.targetText, isEmpty);
    });
  });
}