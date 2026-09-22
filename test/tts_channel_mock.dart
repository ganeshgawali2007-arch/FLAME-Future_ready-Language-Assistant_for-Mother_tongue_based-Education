import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registers a fake implementation of the `flutter_tts` platform channel so
/// widget tests can pump the real app without the bounded probes/timeouts in
/// [OfflineTextToSpeech] leaking pending timers under fake-async — on a real
/// device the native side answers these calls immediately.
///
/// Mirrors the device truth from the Motorola Edge 60 Pro: Google TTS engine,
/// hi-IN accepted, and an installed offline Hindi voice. `speak` also
/// synthesizes the `speak.onStart` / `speak.onComplete` channel events the
/// real engine sends, so the speak future resolves like real playback.
void installTtsChannelMock() {
  final codec = const StandardMethodCodec();
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
          (call) async {
    switch (call.method) {
      case 'getEngines':
        return <dynamic>['com.google.android.tts'];
      case 'getDefaultEngine':
        return 'com.google.android.tts';
      case 'getLanguages':
        return <dynamic>['hi-IN', 'en-US'];
      case 'setLanguage':
        return 1;
      case 'isLanguageAvailable':
        return true;
      case 'isLanguageInstalled':
        return true;
      case 'getVoices':
        return <dynamic>[
          <String, dynamic>{
            'name': 'hi-in-x-hia-local',
            'locale': 'hi-IN',
            'quality': 400,
            'latency': 200,
            'network_required': false,
          },
        ];
      case 'getDefaultVoice':
        return <String, String>{'name': 'hi-in-x-hia-local', 'locale': 'hi-IN'};
      case 'setSpeechRate':
      case 'setPitch':
      case 'setVolume':
      case 'setQueueMode':
      case 'setEngine':
        return 1;
      case 'stop':
        return null;
      case 'speak':
        // Real engine: playback starts then completes. Deliver both channel
        // events so the app's completion handler resolves its speak future.
        final messenger =
            TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
        unawaited(messenger.handlePlatformMessage(
          'flutter_tts',
          codec.encodeMethodCall(const MethodCall('speak.onStart')),
          (_) {},
        ));
        unawaited(messenger.handlePlatformMessage(
          'flutter_tts',
          codec.encodeMethodCall(const MethodCall('speak.onComplete')),
          (_) {},
        ));
        return 1;
      default:
        return null;
    }
  });
}

void removeTtsChannelMock() {
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
}

/// Fake `flame/sat_tts` platform channel so widget tests can mount the real
/// app (whose classroom teardown calls the Santhali engine's bounded
/// stop/release) without leaking watchdog timers under fake-async — on a
/// real device the native side answers immediately.
void installSatTtsChannelMock() {
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flame/sat_tts'),
          (call) async {
    switch (call.method) {
      case 'status':
        return 'missing';
      case 'probeText':
        return 'ᱥᱟᱱᱛᱟᱲᱤ';
      case 'load':
        return 'ready';
      case 'synthesize':
        return <String, Object?>{
          'status': 'completed',
          'sampleRate': 16000,
          'durationMs': 900,
          'synthMs': 120,
          'playMs': 800,
        };
      case 'stop':
      case 'release':
        return null;
      default:
        return null;
    }
  });
}

void removeSatTtsChannelMock() {
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flame/sat_tts'), null);
}