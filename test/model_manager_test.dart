import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/enums.dart';
import 'package:flame/services/model_manager.dart';

void main() {
  group('ModelManager lifecycle', () {
    test('bundled hindi speech is installed but not loaded initially', () {
      final m = ModelManagerController();
      expect(m.isInstalled(FlmModelId.hindiSpeech), isTrue);
      expect(m.statusOf(FlmModelId.hindiSpeech), EngineStatus.installed);
    });

    test('loads a bundled model through its loader (installed → ready)', () async {
      var loaded = false;
      var unloaded = false;
      final m = ModelManagerController(
        loaders: {
          FlmModelId.hindiSpeech: () async => loaded = true,
        },
        unloaders: {
          FlmModelId.hindiSpeech: () async => unloaded = true,
        },
      );

      final ok = await m.loadModel(FlmModelId.hindiSpeech);
      expect(ok, isTrue);
      expect(loaded, isTrue);
      expect(m.statusOf(FlmModelId.hindiSpeech), EngineStatus.ready);

      await m.unloadModel(FlmModelId.hindiSpeech);
      expect(unloaded, isTrue);
      expect(m.statusOf(FlmModelId.hindiSpeech), EngineStatus.installed,
          reason: 'data stays on device after RAM release');
    });

    test('missing model refuses to load — no fabricated ready state', () async {
      final m = ModelManagerController();
      expect(m.statusOf(FlmModelId.hindiSanthaliTranslation),
          EngineStatus.missing);
      expect(
        () => m.loadModel(FlmModelId.hindiSanthaliTranslation),
        throwsA(isA<ModelNotInstalledException>()),
      );
      expect(m.statusOf(FlmModelId.hindiSanthaliTranslation),
          EngineStatus.missing);
    });

    test('failed loader lands in error, not ready', () async {
      final m = ModelManagerController(
        loaders: {
          FlmModelId.hindiVoice: () async => throw StateError('boom'),
        },
      );
      expect(m.statusOf(FlmModelId.hindiVoice), EngineStatus.unverified,
          reason: 'system voice is never Installed until a real probe runs');
      expect(m.isInstalled(FlmModelId.hindiVoice), isFalse);
      final ok = await m.loadModel(FlmModelId.hindiVoice);
      expect(ok, isFalse);
      expect(m.statusOf(FlmModelId.hindiVoice), EngineStatus.error);
    });

    test('storage accounting only counts missing packs', () {
      final m = ModelManagerController();
      expect(m.storageRequiredMbFor(FlmModelId.hindiSanthaliTranslation), 312);
      expect(m.storageRequiredMbFor(FlmModelId.santhaliVoice), 61);
      expect(m.storageRequiredMbFor(FlmModelId.hindiSpeech), isNull);
      expect(m.totalStorageRequiredMb(), 373);
    });

    test('no-op default loaders still move installed → ready', () async {
      final m = ModelManagerController();
      expect(await m.loadModel(FlmModelId.educationalContent), isTrue);
      expect(m.statusOf(FlmModelId.educationalContent), EngineStatus.ready);
    });

    test('recheckInstall flips missing → installed only when probe finds pack',
        () async {
      var present = false;
      final m = ModelManagerController(
        installCheckers: {
          FlmModelId.hindiSanthaliTranslation: () async => present,
        },
      );
      expect(m.hasInstallChecker(FlmModelId.hindiSanthaliTranslation), isTrue);
      expect(m.hasInstallChecker(FlmModelId.hindiSpeech), isFalse);

      await m.recheckInstall(FlmModelId.hindiSanthaliTranslation);
      expect(m.statusOf(FlmModelId.hindiSanthaliTranslation),
          EngineStatus.missing);

      present = true;
      await m.recheckInstall(FlmModelId.hindiSanthaliTranslation);
      expect(m.statusOf(FlmModelId.hindiSanthaliTranslation),
          EngineStatus.installed);
    });

    test('recheckInstall without a checker is a no-op', () async {
      final m = ModelManagerController();
      await m.recheckInstall(FlmModelId.hindiSanthaliTranslation);
      expect(m.statusOf(FlmModelId.hindiSanthaliTranslation),
          EngineStatus.missing);
    });

    test('a later success clears a stale probe note', () async {
      var fail = true;
      final m = ModelManagerController(
        packPresenceProbes: {
          FlmModelId.hindiSanthaliTranslation: () async => true,
        },
        installCheckers: {
          FlmModelId.hindiSanthaliTranslation: () async {
            if (fail) throw StateError('boom');
            return true;
          },
        },
      );
      await m.recheckInstall(FlmModelId.hindiSanthaliTranslation);
      expect(m.statusOf(FlmModelId.hindiSanthaliTranslation),
          EngineStatus.error);
      expect(m.infoFor(FlmModelId.hindiSanthaliTranslation).probeNote,
          contains('boom'));
      fail = false;
      await m.recheckInstall(FlmModelId.hindiSanthaliTranslation);
      expect(m.statusOf(FlmModelId.hindiSanthaliTranslation),
          EngineStatus.installed);
      expect(m.infoFor(FlmModelId.hindiSanthaliTranslation).probeNote,
          isNull);
    });
  });

  test('Santhali voice is honestly missing everywhere', () {
    final m = ModelManagerController();
    expect(m.statusOf(FlmModelId.santhaliVoice), EngineStatus.missing);
    expect(m.isInstalled(FlmModelId.santhaliVoice), isFalse);
    expect(
      () => m.loadModel(FlmModelId.santhaliVoice),
      throwsA(isA<ModelNotInstalledException>()),
    );
  });
}