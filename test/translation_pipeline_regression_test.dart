import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/enums.dart';
import 'package:flame/screens/live_session_screen.dart';
import 'package:flame/services/asr/offline_speech_recognizer.dart';
import 'package:flame/services/classrooms/classroom_controller.dart';
import 'package:flame/services/offline_status_service.dart';
import 'package:flame/services/permissions/permission_service.dart';
import 'package:flame/services/translation/nmt_engine.dart';
import 'package:flame/services/translation/nmt_tokenizer.dart';
import 'package:flame/services/translation/offline_translation_engine.dart';
import 'package:flame/services/translation/translation_engine.dart';
import 'package:flame/services/tts/offline_tts.dart';
import 'package:flame/widgets/sanathali_text.dart';

const _root = 'D:\\FOREST-FLAME\\Flame apk';

Future<Map<String, String>> _assetFileLoader() async {
  Future<String> load(String path) async =>
      (await File('$_root/$path').readAsString()).trim();
  return {
    'vocab_src': await load('assets/nmt/nmt_vocab_src.txt'),
    'vocab_tgt': await load('assets/nmt/nmt_vocab_tgt.txt'),
    'merges_src': await load('assets/nmt/nmt_merges_src.txt'),
    'merges_tgt': await load('assets/nmt/nmt_merges_tgt.txt'),
    'added_src': await load('assets/nmt/nmt_added_src.txt'),
    'added_tgt': await load('assets/nmt/nmt_added_tgt.txt'),
    'meta': await load('assets/nmt/nmt_meta.json'),
  };
}

/// Decoder that returns EOS immediately — pins the honest empty-result path.
class _ImmediateEosRuntime implements NmtRuntime {
  @override
  Future<void> load(String modelDir) async {}

  @override
  bool get isLoaded => true;

  @override
  Future<int> startDecode(List<int> inputIds, List<int> attentionMask) async =>
      2; // eos

  @override
  Future<int> step(int nextId) async => 2;

  @override
  Future<void> endDecode() async {}

  @override
  Future<void> release() async {}
}

/// Decoder that dies mid-decode — pins the honest failure path.
class _DieOnStepRuntime implements NmtRuntime {
  @override
  Future<void> load(String modelDir) async {}

  @override
  bool get isLoaded => true;

  @override
  Future<int> startDecode(List<int> inputIds, List<int> attentionMask) async =>
      699;

  @override
  Future<int> step(int nextId) async =>
      throw StateError('native session died mid-decode');

  @override
  Future<void> endDecode() async {}

  @override
  Future<void> release() async {}
}

class _RecordingTranslator implements TranslationEngine {
  int calls = 0;
  String? lastText;
  AppLanguage? lastSource;
  AppLanguage? lastTarget;
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
    lastSource = source;
    lastTarget = target;
    if (throwOnTranslate) throw StateError('boom');
    return result;
  }
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

class _FakePermissions extends PermissionService {
  _FakePermissions(this.result);
  final MicPermissionState result;

  @override
  Future<MicPermissionState> requestMicrophone() async => result;

  @override
  Future<MicPermissionState> checkMicrophone() async => result;

  @override
  Future<bool> openSettings() async => true;
}

class _FakeRecognizer implements OfflineSpeechRecognizer {
  bool ready = true;
  bool startedListening = false;
  int stopCalls = 0;
  final StreamController<RecognitionResult> _stream =
      StreamController<RecognitionResult>.broadcast();

  @override
  bool get isReady => ready;

  @override
  String get failureReason => 'fake failure';

  @override
  Future<void> warmUp() async {}

  @override
  Stream<RecognitionResult> listen() {
    startedListening = true;
    return _stream.stream;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  void emitFinal(String transcript) =>
      _stream.add(RecognitionResult(transcript: transcript, isFinal: true));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('processTurn — translation request discipline', () {
    late _RecordingTranslator translator;

    setUp(() {
      translator = _RecordingTranslator();
    });

    test('Hindi FINAL text triggers exactly ONE translation request', () async {
      final classroom = ClassroomController(
        translator: translator,
        tts: _FakeTts(),
      );
      await classroom.processTurn(
        text: 'आज हम पौधों के बारे में सीखेंगे',
        speaker: SpeakerRole.teacher,
        sourceLanguage: AppLanguage.hindi,
      );
      expect(translator.calls, 1);
      expect(translator.lastText, 'आज हम पौधों के बारे में सीखेंगे');
      expect(classroom.transcript, hasLength(1));
    });

    test('Hindi→Santhali passes the correct source/target to the engine',
        () async {
      final classroom = ClassroomController(
        translator: translator,
        tts: _FakeTts(),
      );
      await classroom.processTurn(
        text: 'अपनी किताब खोलो।',
        speaker: SpeakerRole.teacher,
        sourceLanguage: AppLanguage.hindi,
      );
      expect(translator.lastSource, AppLanguage.hindi);
      expect(translator.lastTarget, AppLanguage.santhali);
    });

    test('Santhali→Hindi passes the correct reverse source/target', () async {
      final classroom = ClassroomController(
        translator: translator,
        tts: _FakeTts(),
      );
      await classroom.processTurn(
        text: 'ᱫᱚ ᱞᱟᱹᱭ ᱢᱮ',
        speaker: SpeakerRole.student,
        sourceLanguage: AppLanguage.santhali,
      );
      expect(translator.lastSource, AppLanguage.santhali);
      expect(translator.lastTarget, AppLanguage.hindi);
    });

    test('a second recognised sentence creates a second turn, not a dup',
        () async {
      final classroom = ClassroomController(
        translator: translator,
        tts: _FakeTts(),
      );
      await classroom.processTurn(
        text: 'सुप्रभात बच्चों',
        speaker: SpeakerRole.teacher,
        sourceLanguage: AppLanguage.hindi,
      );
      await classroom.processTurn(
        text: 'ध्यान से सुनो।',
        speaker: SpeakerRole.teacher,
        sourceLanguage: AppLanguage.hindi,
      );
      expect(translator.calls, 2);
      expect(classroom.transcript, hasLength(2));
    });

    test('empty translation keeps the source card and asks nothing extra',
        () async {
      final classroom = ClassroomController(
        translator: translator,
        tts: _FakeTts(),
      );
      await classroom.processTurn(
        text: 'कोई मिला नहीं',
        speaker: SpeakerRole.teacher,
        sourceLanguage: AppLanguage.hindi,
      );
      expect(classroom.transcript.single.sourceText, 'कोई मिला नहीं');
      expect(classroom.transcript.single.targetText, isEmpty);
      expect(translator.calls, 1);
    });
  });

  group('IndicTrans2Backend — empty result and NMT failure honesty', () {
    late NmtTokenizer tokenizer;

    setUpAll(() async {
      tokenizer = NmtTokenizer(assetLoader: _assetFileLoader);
      await tokenizer.load();
    });

    test('immediate EOS (empty output) -> StateError -> explicit unavailable',
        () async {
      final backend = IndicTrans2Backend(
        tokenizer: tokenizer,
        engine: NmtEngine(tokenizer: tokenizer, runtime: _ImmediateEosRuntime()),
        modelDirResolver: () async => 'C:\\fake\\nmt_model',
      );
      expect(await backend.warmUp(), isTrue);

      final pipeline = OfflineTranslationEngine(backend: backend);
      final res = await pipeline.translate(
        'आज हम पौधों के बारे में सीखेंगे',
        source: AppLanguage.hindi,
        target: AppLanguage.santhali,
      );
      expect(res.canTranslate, isFalse);
      expect(res.quality, TranslationQuality.fallback);
      expect(res.targetText, isEmpty);
    });

    test('mid-decode NMT failure -> explicit unavailable, never a guess',
        () async {
      final backend = IndicTrans2Backend(
        tokenizer: tokenizer,
        engine: NmtEngine(tokenizer: tokenizer, runtime: _DieOnStepRuntime()),
        modelDirResolver: () async => 'C:\\fake\\nmt_model',
      );
      expect(await backend.warmUp(), isTrue);

      final pipeline = OfflineTranslationEngine(backend: backend);
      final res = await pipeline.translate(
        'पानी कहाँ से मिलता है',
        source: AppLanguage.hindi,
        target: AppLanguage.santhali,
      );
      expect(res.canTranslate, isFalse);
      expect(res.targetText, isEmpty);
    });

    test('model unavailable -> explicit unavailable', () async {
      final backend = IndicTrans2Backend(
        tokenizer: tokenizer,
        engine: NmtEngine(tokenizer: tokenizer, runtime: _ImmediateEosRuntime()),
        modelDirResolver: () async => null,
      );
      expect(await backend.warmUp(), isFalse);
      final pipeline = OfflineTranslationEngine(backend: backend);
      final res = await pipeline.translate(
        'ध्यान से सुनो।',
        source: AppLanguage.hindi,
        target: AppLanguage.santhali,
      );
      expect(res.canTranslate, isFalse);
      expect(res.targetText, isEmpty);
    });
  });

  group('LiveSessionView — typed input drives the same one-shot translation',
      () {
    late _RecordingTranslator translator;

    setUp(() {
      translator = _RecordingTranslator();
    });

    Future<(ClassroomController, _FakeRecognizer)> pumpClassroom(
      WidgetTester tester,
    ) async {
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
              permissions: _FakePermissions(MicPermissionState.granted),
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

    testWidgets('typing Hindi and submitting yields EXACTLY one translation',
        (tester) async {
      translator.result = const TranslationResult(
        sourceText: '',
        targetText: 'ᱛᱷᱭoo',
        quality: TranslationQuality.model,
        canTranslate: true,
      );
      final (classroom, _) = await pumpClassroom(tester);

      await tester.enterText(find.byType(TextField), 'अपनी किताब खोलो।');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      expect(translator.calls, 1);
      expect(translator.lastText, 'अपनी किताब खोलो।');
      expect(translator.lastSource, AppLanguage.hindi);
      expect(translator.lastTarget, AppLanguage.santhali);
      expect(classroom.transcript, hasLength(1));
    });

    testWidgets('recognized FINAL renders the translated Santhali card',
        (tester) async {
      translator.result = const TranslationResult(
        sourceText: '',
        targetText: 'ᱛᱷᱭoo',
        quality: TranslationQuality.model,
        canTranslate: true,
      );
      final (classroom, rec) = await pumpClassroom(tester);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump();
      rec.emitFinal('प्रकाश जरूरी है।');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(translator.calls, 1);
      expect(classroom.transcript, hasLength(1));
      expect(classroom.transcript.single.targetText, isNotEmpty);
      expect(find.byType(SanathaliText), findsOneWidget);
    });

    testWidgets('translation failure shows source-only, no empty Santhali card',
        (tester) async {
      translator.result = const TranslationResult(
        sourceText: '',
        targetText: '',
        quality: TranslationQuality.fallback,
        canTranslate: false,
      );
      final (classroom, rec) = await pumpClassroom(tester);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump();
      rec.emitFinal('ध्यान से सुनो।');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(classroom.transcript, hasLength(1));
      expect(classroom.transcript.single.targetText, isEmpty);
      expect(find.byType(SanathaliText), findsNothing);
    });
  });
}