import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/repositories/flm_repository.dart';
import 'models/enums.dart';
import 'services/asr/offline_speech_recognizer.dart';
import 'services/classrooms/classroom_controller.dart';
import 'services/classrooms/lan_classroom_sync.dart';
import 'services/education/educational_engine.dart';
import 'services/model_manager.dart';
import 'services/offline_status_service.dart';
import 'services/permissions/permission_service.dart';
import 'services/translation/nmt_engine.dart';
import 'services/translation/nmt_model_pack.dart';
import 'services/translation/nmt_platform_runtime.dart';
import 'services/translation/nmt_self_test.dart';
import 'services/translation/nmt_tokenizer.dart';
import 'services/translation/offline_translation_engine.dart';
import 'services/tts/offline_tts.dart';
import 'services/tts/santhali_tts_engine.dart';
import 'services/tts/tts_self_test.dart';
import 'services/voice/voice_bot_controller.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/ask_flame_screen.dart';
import 'screens/create_class_screen.dart';
import 'screens/home_screen.dart';
import 'screens/join_classroom_screen.dart';
import 'screens/language_screen.dart';
import 'screens/lesson_selection_screen.dart';
import 'screens/my_classes_screen.dart';
import 'screens/offline_setup_screen.dart';
import 'screens/role_screen.dart';
import 'screens/session_summary_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/student_classroom_screen.dart';
import 'screens/student_waiting_room_screen.dart';
import 'screens/teacher_classroom_screen.dart';
import 'screens/welcome_screen.dart';

/// App + shared services. Heavy engines (speech pack, voice bot) are created
/// per-screen, lazily, so 2-4 GB devices hold only what the active screen
/// needs. Nothing here requires internet.
class FlameApp extends StatefulWidget {
  const FlameApp({super.key});

  @override
  State<FlameApp> createState() => _FlameAppState();
}

class _FlameAppState extends State<FlameApp> {
  late final AppState appState;
  late final OfflineStatusService offline;
  late final ModelManagerController models;
  late final PermissionService permissions;
  late final OfflineTranslationEngine translation;
  late final OfflineTextToSpeech tts;
  late final OfflineSanthaliTtsEngine santhaliTts;
  late final SatTtsPack satTtsPack;
  late final NmtTokenizer nmtTokenizer;
  late final IndicTrans2Backend nmtBackend;
  late final NmtModelPack nmtPack;

  @override
  void initState() {
    super.initState();
    appState = AppState();
    offline = OfflineStatusService();
    // Real offline Santhali voice (Piper-style VITS ONNX, side-loaded).
    // Until its pack is genuinely on the device AND probed, the engine
    // reports not-installed and Santhali speech fails explicitly — the Hindi
    // system voice is never used as a substitute.
    satTtsPack = SatTtsPack();
    santhaliTts = OfflineSanthaliTtsEngine(
      pack: satTtsPack,
      modelDirResolver: satTtsPack.resolveModelDir,
    );
    tts = OfflineTextToSpeech(santhaliTts: santhaliTts);

    // Real translation tier: IndicTrans2 INT8 ONNX behind the side-loaded
    // model pack. Until the pack is genuinely on the device, the backend
    // reports not-installed and the pipeline stays on cache + explicit
    // failure (never a guess).
    nmtPack = NmtModelPack();
    nmtTokenizer = NmtTokenizer();
    final nmtRuntime =
        MethodChannelNmtRuntime(metaProvider: () => nmtTokenizer.meta);
    nmtBackend = IndicTrans2Backend(
      tokenizer: nmtTokenizer,
      engine: NmtEngine(tokenizer: nmtTokenizer, runtime: nmtRuntime),
      modelDirResolver: nmtPack.resolveModelDir,
    );

    models = ModelManagerController(
      loaders: {
        FlmModelId.hindiSpeech: () async {
          // Extract/install the bundled Vosk Hindi model, then report the
          // true readiness (never a fabricated "ready").
          await voskRecognizer.warmUp();
          if (!voskRecognizer.isReady) {
            throw StateError(voskRecognizer.failureReason);
          }
        },
        FlmModelId.hindiVoice: () async {
          final readiness = await tts.checkReadiness();
          if (readiness != TtsReadiness.ready) {
            throw StateError('Hindi voice unavailable on this device.');
          }
        },
        FlmModelId.hindiSanthaliTranslation: () async {
          final ok = await nmtBackend.warmUp();
          if (!ok) {
            throw StateError('Translation pack not installed.');
          }
        },
        FlmModelId.santhaliVoice: () async {
          // Silent warm-up (load + silent inference probe): no uninvited
          // audio on session start. Audibility is proven by real usage and
          // the Settings Check/Test Voice path.
          final ok = await santhaliTts.warmUp();
          if (!ok) {
            throw StateError('Santhali voice pack not installed.');
          }
        },
      },
      unloaders: {
        // Free the native model + recognizer so RAM returns to the app.
        FlmModelId.hindiSpeech: () => voskRecognizer.client.release(),
        // Free the ORT sessions (pack data stays on device).
        FlmModelId.hindiSanthaliTranslation: () => nmtBackend.unload(),
        // Free the VITS session (pack data stays on device).
        FlmModelId.santhaliVoice: () => santhaliTts.release(),
      },
      installCheckers: {
        FlmModelId.hindiVoice: () async {
          final readiness = await tts.checkReadiness();
          if (readiness != TtsReadiness.ready) {
            throw StateError('Hindi voice unavailable on this device.');
          }
          // User tapped Check: prove audibility, not just API presence. The
          // short probe utterance must actually start AND complete; a silent
          // engine (muted stream, missing voice data) fails honestly here.
          // Never used at startup or session start — no uninvited audio.
          final heard = await tts.probeSpeakUtterance();
          if (!heard) {
            throw StateError(
                'Hindi voice did not speak '
                '(reason=${tts.lastFailureReason.name}). Check the media '
                'volume and the system TTS voice data, then tap Check again.');
          }
          return true;
        },
        // A genuine runtime probe: "installed" is only claimed after the ORT
        // sessions manifestly initialize, never from file presence alone.
        FlmModelId.hindiSanthaliTranslation: () async {
          final dir = await nmtPack.resolveModelDir();
          if (dir == null) {
            throw StateError('pack not found on device');
          }
          final ok = await nmtBackend.warmUp();
          await nmtBackend.unload();
          if (!ok) {
            throw StateError(
                'runtime init returned not-ready (dir=$dir)');
          }
          return true;
        },
        // Santhali voice Check / Test Voice (user-initiated, so an audible
        // probe is appropriate feedback): the pack must load AND a short
        // Santhali utterance must actually synthesize AND play to completion.
        // File presence alone never flips the state.
        FlmModelId.santhaliVoice: () async {
          final dir = await satTtsPack.resolveModelDir();
          if (dir == null) {
            throw StateError('pack not found on device');
          }
          final ok = await santhaliTts.warmUp();
          if (!ok) {
            throw StateError(
                'voice init failed (dir=$dir). See logcat FLAME_SAT.');
          }
          final r = await santhaliTts.synthesize('ᱥᱟᱱᱛᱟᱲᱤ', play: true);
          if (!r.completed || r.durationMs < 200) {
            throw StateError(
                'voice probe did not play (status=${r.completed ? 'completed' : (r.stopped ? 'stopped' : 'failed')}). '
                'Check the media volume, then tap Check again.');
          }
          return true;
        },
      },
      packPresenceProbes: {
        // Independent "are the files on the device" probe, shown separately
        // from runtime readiness in Settings.
        FlmModelId.hindiSanthaliTranslation: () async =>
            (await nmtPack.resolveModelDir()) != null,
        FlmModelId.santhaliVoice: () async =>
            (await satTtsPack.resolveModelDir()) != null,
      },
    );
    permissions = PermissionService();
    translation = OfflineTranslationEngine(backend: nmtBackend);

    // Probe once at startup so Settings shows the true pack state. The state
    // is "Installed" only when the runtime can genuinely initialize; a pack
    // that is present but fails to load surfaces as Error with the exact
    // probe failure. Pack-on-device is tracked independently.
    //
    // When the debug self-test is armed, the self-test OWNS the shared
    // backend (warmUp -> translate -> status) and the probe must not touch it
    // concurrently — an unload between warmUp and the first startDecode
    // yields the native "sessions not loaded" failure.
    () async {
      final present = await nmtPack.resolveModelDir() != null;
      models.setPackPresence(
          FlmModelId.hindiSanthaliTranslation, present);
      if (await NmtSelfTest.isArmed()) {
        final ok = await NmtSelfTest.run(
          backend: nmtBackend,
          tokenizer: nmtTokenizer,
          pack: nmtPack,
          pipeline: translation,
        );
        if (ok && nmtBackend.isInstalled) {
          models.setProbeNote(FlmModelId.hindiSanthaliTranslation, null);
          models.setState(
              FlmModelId.hindiSanthaliTranslation, EngineStatus.installed);
          await nmtBackend.unload();
        } else {
          models.setProbeNote(
            FlmModelId.hindiSanthaliTranslation,
            'self-test failed (see logcat FLAME_NMT_SELFTEST / '
            'nmt_selftest_result.txt)',
          );
          models.setState(
              FlmModelId.hindiSanthaliTranslation, EngineStatus.error);
        }
        return;
      }
      if (!present) {
        models.setState(FlmModelId.hindiSanthaliTranslation,
            EngineStatus.missing);
        return;
      }
      try {
        final ok = await nmtBackend.warmUp();
        if (ok) {
          models.setProbeNote(FlmModelId.hindiSanthaliTranslation, null);
          models.setState(
              FlmModelId.hindiSanthaliTranslation, EngineStatus.installed);
          await nmtBackend.unload();
        } else {
          models.setProbeNote(FlmModelId.hindiSanthaliTranslation,
              'runtime init returned not-ready');
          models.setState(
              FlmModelId.hindiSanthaliTranslation, EngineStatus.error);
        }
      } catch (e) {
        models.setProbeNote(FlmModelId.hindiSanthaliTranslation, '$e');
        models.setState(
            FlmModelId.hindiSanthaliTranslation, EngineStatus.error);
      }
    }();
    // Santhali voice startup probe: silent warm-up (load + silent inference
    // probe). "Installed" only after genuine inference; the session is parked
    // afterwards (low-end RAM rule) and reloaded on demand. Never any audio
    // at startup, never the Hindi voice as a substitute.
    () async {
      final present = await satTtsPack.resolveModelDir() != null;
      models.setPackPresence(FlmModelId.santhaliVoice, present);
      if (!present) {
        // Keep the seeded honest state (missing + side-load instructions).
        return;
      }
      try {
        final ok = await santhaliTts.warmUp();
        if (ok) {
          models.setProbeNote(FlmModelId.santhaliVoice, null);
          models.setState(
              FlmModelId.santhaliVoice, EngineStatus.installed);
          await santhaliTts.release();
        } else {
          models.setProbeNote(FlmModelId.santhaliVoice,
              'voice init failed (see logcat FLAME_SAT)');
          models.setState(FlmModelId.santhaliVoice, EngineStatus.error);
        }
      } catch (e) {
        models.setProbeNote(FlmModelId.santhaliVoice, '$e');
        models.setState(FlmModelId.santhaliVoice, EngineStatus.error);
      }
    }();
    // Debug-only, flag-gated direct TTS self-test. Uses its own instrumented
    // FlutterTts probe for capability reads plus the production
    // OfflineTextToSpeech for every speech trial; does not touch the NMT
    // backend above.
    () async {
      if (await TtsSelfTest.isArmed()) {
        await TtsSelfTest.run(tts: tts);
      }
    }();
    // Honest Hindi Voice state at startup: Available only after a real probe
    // confirms engine + hi-IN offline data. Never Installed on faith.
    () async {
      final readiness = await tts.checkReadiness();
      if (readiness == TtsReadiness.ready) {
        models.setProbeNote(FlmModelId.hindiVoice, null);
        models.setState(FlmModelId.hindiVoice, EngineStatus.installed);
      } else {
        models.setProbeNote(
          FlmModelId.hindiVoice,
          readiness == TtsReadiness.engineMissing
              ? 'No Android TTS engine found. Install a text-to-speech '
                  'engine in Android device Settings, then tap Check.'
              : 'Hindi voice (hi-IN) is not installed in the Android TTS '
                  'engine. Install it in Android Settings → Text-to-speech, '
                  'then tap Check.',
        );
        models.setState(
            FlmModelId.hindiVoice,
            readiness == TtsReadiness.engineMissing
                ? EngineStatus.error
                : EngineStatus.missing);
      }
    }();
  }

  @override
  void dispose() {
    tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: offline),
        ChangeNotifierProvider.value(value: models),
        Provider.value(value: permissions),
        Provider.value(value: translation),
        ChangeNotifierProvider.value(value: tts),
        Provider<Future<FlmRepository>>(
          create: (_) => FlmRepository.open(),
        ),
        ChangeNotifierProvider<ClassroomController>(
          create: (context) => ClassroomController(
            translator: translation,
            tts: tts,
            models: models,
            sync: LanClassroomSync(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'FLAME',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        initialRoute: '/',
        onGenerateRoute: _routes,
      ),
    );
  }
}

Route<dynamic> _routes(RouteSettings settings) {
  switch (settings.name) {
    case '/':
      return _route(const SplashScreen());
    case '/welcome':
      return _route(const WelcomeScreen());
    case '/role':
      return _route(const RoleScreen());
    case '/language':
      return _route(const LanguageScreen());
    case '/offline-setup':
      return _route(const OfflineSetupScreen());
    case '/home':
      return _route(const HomeScreen());
    case '/create-class':
      return _route(const CreateClassScreen());
    case '/lesson-select':
      final args = (settings.arguments as Map<String, Object>? ?? {});
      return _route(
        LessonSelectionScreen(
          classArgs: {
            'name': (args['name'] as String?) ?? 'Class',
            'level': (args['level'] as String?) ?? 'Class 3',
            'subject': (args['subject'] as String?) ?? 'EVS',
          },
        ),
      );
    case '/teacher-classroom':
      return _route(const TeacherClassroomScreen());
    case '/join':
      return _route(const JoinClassroomScreen());
    case '/student-waiting':
      return _route(const StudentWaitingRoomScreen());
    case '/student-classroom':
      return _route(const StudentClassroomScreen());
    case '/summary':
      return _route(const SessionSummaryScreen());
    case '/ask-flame':
      return _route(const AskFlameRoute());
    case '/settings':
      return _route(const SettingsScreen());
    case '/my-classes':
      return _route(const MyClassesScreen());
    default:
      return _route(const HomeScreen());
  }
}

MaterialPageRoute<dynamic> _route(Widget page) =>
    MaterialPageRoute(builder: (_) => page);

/// Ask FLAME is created lazily when the screen is opened and disposed on
/// leaving — it never stays resident in memory (low-end device rule).
class AskFlameRoute extends StatefulWidget {
  const AskFlameRoute({super.key});

  @override
  State<AskFlameRoute> createState() => _AskFlameRouteState();
}

class _AskFlameRouteState extends State<AskFlameRoute> {
  late final VoiceBotController bot;

  @override
  void initState() {
    super.initState();
    bot = VoiceBotController(
      // Loads the local knowledge base from SQLite only when first asked.
      engine: OfflineEducationalEngine(
        entriesLoader: () async {
          final repo = await FlmRepository.open();
          return repo.knowledgeEntries();
        },
      ),
      tts: context.read<OfflineTextToSpeech>(),
      offline: context.read<OfflineStatusService>(),
      permissions: context.read<PermissionService>(),
      models: context.read<ModelManagerController>(),
    );
    bot.init();
  }

  @override
  void dispose() {
    bot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: bot,
      child: const AskFlameScreen(),
    );
  }
}