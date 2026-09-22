import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flame/app.dart';
import 'package:flame/models/enums.dart';
import 'package:flame/screens/ask_flame_screen.dart';
import 'package:flame/screens/home_screen.dart';
import 'package:flame/screens/offline_setup_screen.dart';
import 'package:flame/services/classrooms/classroom_controller.dart';
import 'package:flame/services/voice/voice_bot_controller.dart';

import 'tts_channel_mock.dart';

/// End-to-end UI flow validation, pumping the real app plus a real SQLite
/// database (FFI) so every tap really resolves into the next screen.
///
/// Onboarding helper walks: splash → welcome → role → language →
/// offline-setup (bounded 900 ms job) → home.
void main() {
  setUpAll(() async {
    // The real app probes the TTS engine at startup and when the Hindi voice
    // model loads; without an answering native side the bounded watchdog stays
    // pending under fake-async. Mock the channel so the engine answers like a
    // real device.
    installTtsChannelMock();
    installSatTtsChannelMock();
    addTearDown(removeTtsChannelMock);
    addTearDown(removeSatTtsChannelMock);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await databaseFactory.getDatabasesPath();
    final dbFile = File('$dir${Platform.pathSeparator}flame.db');
    if (dbFile.existsSync()) dbFile.deleteSync();
  });

  Future<void> ensureVisibleTap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 250);
    } else {
      await tester.ensureVisible(finder);
    }
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  void noopStreamListen(Object? arguments, MockStreamHandlerEventSink events) {}

  Future<void> realWait(
    WidgetTester tester, [
    Duration d = const Duration(milliseconds: 40),
  ]) async {
    await tester.runAsync(() => Future<void>.delayed(d));
    await tester.pump();
  }

  Future<void> onboardAs(WidgetTester tester, String role) async {
    await tester.pumpWidget(const FlameApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('FLAME'), findsOneWidget); // splash brand
    expect(find.text('Learn in your language.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2)); // splash auto-nav fires
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(role)); // 'Teacher' / 'Student'
    await tester.pumpAndSettle();

    // Language defaults to the pre-selected Hindi → Santhali pair.
    await tester.tap(find.text('Continue'));
    await tester.pump();

    // Offline setup mounts with a real spinner while it runs its offline job
    // (bundled corpus asset load = real I/O, then a bounded delay), so it
    // must not be watched with pumpAndSettle. First wait for the setup
    // screen itself, then advance the fake clock + real-wait until its
    // bounded job reports done and Continue is enabled (whatever real start
    // time the job had).
    for (var i = 0;
        i < 12 && find.text('Setting up FLAME offline...').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await realWait(tester, const Duration(milliseconds: 300));
    }
    final continueOn = find.descendant(
      of: find.byType(OfflineSetupScreen),
      matching: find.text('Continue'),
    );
    for (var i = 0; i < 12 && continueOn.evaluate().isEmpty; i++) {
      await realWait(tester, const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump();
    expect(continueOn, findsOneWidget);
    await ensureVisibleTap(tester, continueOn);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'TEACHER flow: create class no longer hangs; lesson-select loads, '
      'class starts live, ends, summary, home', (tester) async {
    await onboardAs(tester, 'Teacher');

    // Home for teacher: create + my classes.
    expect(find.text('Create Class'), findsOneWidget);
    expect(find.text('My Classes'), findsOneWidget);
    final classroom = Provider.of<ClassroomController>(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    );

    await ensureVisibleTap(tester, find.text('Create Class'));
    await tester.pumpAndSettle();
    expect(find.text('Tell us about the class'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Class 3 • EVS');
    await tester.pump();
    await ensureVisibleTap(tester, find.text('Next'));

    // The lesson library is opened lazily over real SQLite, so wait out the
    // opening I/O instead of pumpAndSettle (the loading spinner animates).
    await tester.pump(const Duration(milliseconds: 300));
    await realWait(tester, const Duration(milliseconds: 400));
    await realWait(tester);
    await tester.pump();

    // Regression: previously the lesson library read the repository
    // synchronously from a Future provider and threw ProviderNotFoundException
    // before mounting — the screen is what the user saw as the infinite
    // "Create Class → loading" hang. Now it must land and load real seeds
    // with no spinner left behind.
    expect(find.text('Choose the lesson'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Plants'), findsOneWidget); // seeded 'Class 3' lesson
    expect(find.text('Parts of a Plant'), findsOneWidget); // seeded topic

    await ensureVisibleTap(tester, find.text('Create Classroom'));
    await tester.pumpAndSettle();

    // Teacher-waiting: shows the shareable class code and Start button.
    expect(find.text('Share this code with your class'), findsOneWidget);
    expect(classroom.classLevel, 'Class 3');
    expect(classroom.lessonTitle, 'Plants');
    expect(classroom.topicTitle, 'Parts of a Plant');
    expect(classroom.classCode, isNotNull);

    await ensureVisibleTap(tester, find.text('Start Class'));
    await tester.pumpAndSettle();

    // Live control view: mode buttons + End Class.
    expect(find.text('Live Listening'), findsOneWidget);
    expect(find.text('End Class'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'End Class'));
    // End Class must never hang on a wedged speech engine: the stop call is
    // bounded, so advance the clock past the bound then settle the route.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Session summary then Done → home.
    expect(find.text('Session Complete'), findsOneWidget);
    await ensureVisibleTap(tester, find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Create Class'), findsOneWidget);
  });

  testWidgets(
      'STUDENT flow: wrong code is an honest recovery state; valid code joins, '
      'waits, goes live, ends, summary, home', (tester) async {
    await onboardAs(tester, 'Student');

    expect(find.text('Join Class'), findsOneWidget);
    final classroom = Provider.of<ClassroomController>(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    );
    await ensureVisibleTap(tester, find.text('Join Class'));
    await tester.pumpAndSettle();

    // Wrong code → RecoveryView, not a silent hang.
    await tester.enterText(find.byType(TextField), 'ZZZZZZ');
    await tester.pump();
    // With the LAN transport wired, a wrong code falls through to real
    // network discovery (real sockets + a real 3 s timeout), which the
    // fake-async zone cannot service — drive the tap and the wait on the
    // real event loop instead.
    final joinButton = find.widgetWithText(FilledButton, 'Join Class');
    await tester.ensureVisible(joinButton);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(joinButton);
      await Future<void>.delayed(const Duration(seconds: 4));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining("couldn't find"), findsOneWidget);
    // Retry clears the error so the student can correct the code.
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.textContaining("couldn't find"), findsNothing);

    // A real classroom is opened (same on-device lifecycle as a second
    // device demo) and the student joins with the code.
    await classroom.teacherCreatesClass(
      name: 'Class 3 • EVS',
      level: 'Class 3',
      subjectName: 'EVS',
      teacher: 'Priya Ma\'am',
      lesson: 'Plants',
      topic: 'Parts of a Plant',
    );
    await tester.enterText(find.byType(TextField), classroom.classCode!);
    await tester.pump();
    await ensureVisibleTap(tester, find.widgetWithText(FilledButton, 'Join Class'));
    // Waiting room pulses continuously, so settle with explicit pumps.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Waiting room while the teacher has not started.
    expect(find.text('Waiting for your teacher to start...'), findsOneWidget);

    // Teacher starts the class → poll navigates to the live student room.
    classroom.startClass();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Ask FLAME'), findsOneWidget);

    // Teacher ends the class → poll navigates to the summary.
    classroom.endClass();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Session Complete'), findsOneWidget);

    await ensureVisibleTap(tester, find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Join Class'), findsOneWidget);
  });

  testWidgets(
      'ASK FLAME flow: typed question resolves offline to an answer card',
      (tester) async {
    // Emulate the native bridge: mic granted, Vosk already installed, and a
    // quiet events stream so the real VoiceBot pipeline runs end to end.
    const perms = MethodChannel('flame/permissions');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(perms, (call) async => 'granted');
    const asr = MethodChannel('flame/asr');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(asr,
        (call) async => call.method == 'install' ? 'ready' : null);
    const asrEvents = EventChannel('flame/asr/events');
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      asrEvents,
      MockStreamHandler.inline(onListen: noopStreamListen),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(perms, null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(asr, null);
      tester.binding.defaultBinaryMessenger
          .setMockStreamHandler(asrEvents, null);
    });

    await onboardAs(tester, 'Student');

    await ensureVisibleTap(tester, find.text('Ask FLAME'));
    await tester.pumpAndSettle();

    // The voice bot init is async; give its real jobs time to finish.
    await realWait(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Type your question'), findsOneWidget);
    await ensureVisibleTap(tester, find.text('Type your question'));
    await tester.pumpAndSettle();

    expect(find.text('Ask FLAME'), findsWidgets); // dialog title
    await tester.enterText(find.byType(TextField).last, 'पौधे कैसे बढ़ते हैं');
    await tester.pump();
    await tester.tap(find.text('Ask'));
    await tester.pump();

    // Understanding → answering → done (real engine over the real DB).
    for (var i = 0; i < 5; i++) {
      await realWait(tester, const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final bot = Provider.of<VoiceBotController>(
      tester.element(find.byType(AskFlameScreen)),
      listen: false,
    );
    expect(bot.phase, VoiceBotPhase.done);
    expect(bot.result, isNotNull);
    expect(bot.result!.answerHindi, isNotEmpty);
    expect(find.text('Your Question'), findsOneWidget);
    expect(find.text('Listen'), findsOneWidget);

    // Queue playback is attempted through a channel that has no native side;
    // flush the bounded stop timers so the test tears down cleanly.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });
}
