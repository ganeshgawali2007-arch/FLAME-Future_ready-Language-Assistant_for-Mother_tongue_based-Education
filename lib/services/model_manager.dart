/// Offline component inventory and lifecycle (ModelManager).
///
/// Per model: data may be *installed* (on device), *ready* (loaded into RAM),
/// *loading*, *missing* (needs the pack), or *error*.
///
/// Honesty contract: a model is [EngineStatus.ready] only when it is genuinely
/// loaded and usable on-device. If a pack is not bundled, [loadModel] throws
/// [ModelNotInstalledException] — it never pretends.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/enums.dart';

enum FlmModelId {
  hindiSpeech,
  hindiSanthaliTranslation,
  santhaliVoice,
  hindiVoice,
  educationalContent,
}

class ModelNotInstalledException implements Exception {
  const ModelNotInstalledException(this.id);
  final FlmModelId id;

  @override
  String toString() => 'ModelNotInstalledException: $id';
}

class FlmModelInfo {
  const FlmModelInfo({
    required this.name,
    required this.state,
    this.storageRequiredMb,
    this.detail,
    required this.integrationPoint,
    this.packPresent,
    this.probeNote,
  });

  final String name;
  final EngineStatus state;

  /// Storage FLAME would need before this component can be installed.
  final int? storageRequiredMb;
  final String? detail;

  /// Where the real implementation plugs in (empty when bundled & ready).
  final String integrationPoint;

  /// For side-loadable packs: whether the model files are on the device at
  /// all — independent of whether the runtime can actually load them.
  final bool? packPresent;

  /// Dynamic note from the last probe (e.g. the exact runtime init failure).
  final String? probeNote;

  FlmModelInfo copyWith({
    EngineStatus? state,
    bool? packPresent,
    String? probeNote,
  }) =>
      FlmModelInfo(
        name: name,
        state: state ?? this.state,
        storageRequiredMb: storageRequiredMb,
        detail: detail,
        integrationPoint: integrationPoint,
        packPresent: packPresent ?? this.packPresent,
        probeNote: probeNote ?? this.probeNote,
      );
}

class ModelManagerController extends ChangeNotifier {
  ModelManagerController({
    Map<FlmModelId, Future<void> Function()>? loaders,
    Map<FlmModelId, Future<void> Function()>? unloaders,
    Map<FlmModelId, Future<bool> Function()>? installCheckers,
    Map<FlmModelId, Future<bool> Function()>? packPresenceProbes,
  })  : _loaders = loaders ?? const {},
        _unloaders = unloaders ?? const {},
        _installCheckers = installCheckers ?? const {},
        _packPresenceProbes = packPresenceProbes ?? const {};

  final Map<FlmModelId, Future<void> Function()> _loaders;
  final Map<FlmModelId, Future<void> Function()> _unloaders;
  final Map<FlmModelId, Future<bool> Function()> _installCheckers;

  /// Independent "are the files physically on the device" probes, used to
  /// show Pack-on-device separately from runtime readiness.
  final Map<FlmModelId, Future<bool> Function()> _packPresenceProbes;

  Future<bool> _resolverFor(FlmModelId id) async {
    final probe = _packPresenceProbes[id];
    return probe != null && (await probe());
  }

  final Map<FlmModelId, FlmModelInfo> _models = {
    FlmModelId.hindiSpeech: const FlmModelInfo(
      name: 'Hindi Speech',
      state: EngineStatus.installed,
      detail: 'vosk-model-small-hi-0.22 (44.5 MB, Apache-2.0) bundled; '
          'extracted once to app storage and streamed on-device.',
      integrationPoint: '',
    ),
    FlmModelId.hindiSanthaliTranslation: const FlmModelInfo(
      name: 'Hindi ↔ Santhali Translation',
      state: EngineStatus.missing,
      storageRequiredMb: 312,
      detail: 'IndicTrans2 indic-indic-dist-320M INT8 ONNX (MIT, covers '
          'sat_Olck). Side-load pack: copy the 5 model files to '
          'Android/data/com.flame.flame/files/nmt_model/ (USB, Files app or '
          'adb), then tap "Check for pack".',
      integrationPoint:
          'OfflineTranslationEngine -> IndicTrans2Backend (ONNX Runtime)',
    ),
    FlmModelId.santhaliVoice: const FlmModelInfo(
      name: 'Santhali Voice',
      state: EngineStatus.missing,
      storageRequiredMb: 61,
      detail: 'Offline neural Santhali voice (Piper-style VITS ONNX, 16 kHz, '
          'MIT). Side-load pack: copy sat_piper_model.onnx + '
          'sat_piper_model.onnx.json to '
          'Android/data/com.flame.flame/files/sat_tts_voice/ (USB, Files app '
          'or adb), then tap "Check". No system voice is ever substituted.',
      integrationPoint:
          'OfflineTextToSpeech -> OfflineSanthaliTtsEngine (ONNX Runtime)',
    ),
    FlmModelId.hindiVoice: const FlmModelInfo(
      name: 'Hindi Voice',
      state: EngineStatus.unverified,
      detail: 'Android system TTS, hi-IN voice (offline at runtime, '
          'device-dependent). Shown as Available only after a real probe '
          'confirms the engine and voice data.',
      integrationPoint: '',
    ),
    FlmModelId.educationalContent: const FlmModelInfo(
      name: 'Educational Content',
      state: EngineStatus.installed,
      detail: 'Bundled SQLite knowledge base: Class 1-3 EVS lessons, topics '
          'and question-answer content.',
      integrationPoint: '',
    ),
  };

  List<FlmModelInfo> get models => _models.values.toList();

  FlmModelInfo infoFor(FlmModelId id) => _models[id]!;

  EngineStatus statusOf(FlmModelId id) => _models[id]!.state;

  /// True when the model's data is on the device (installed/loading/ready).
  bool isInstalled(FlmModelId id) {
    final s = _models[id]!.state;
    return s == EngineStatus.installed ||
        s == EngineStatus.loading ||
        s == EngineStatus.ready;
  }

  int? storageRequiredMbFor(FlmModelId id) => _models[id]!.storageRequiredMb;

  /// True when this model has a side-load probe the UI can re-run.
  bool hasInstallChecker(FlmModelId id) => _installCheckers.containsKey(id);

  /// Re-probe whether a side-loaded pack has appeared on the device.
  /// Installed packs flip to [EngineStatus.installed]; absent ones stay
  /// [EngineStatus.missing]. Never fabricates a state. A checker that throws
  /// (e.g. model files found but the runtime cannot initialize) surfaces the
  /// exact failure via [FlmModelInfo.probeNote] and the error state when the
  /// pack is physically present.
  Future<void> recheckInstall(FlmModelId id) async {
    final checker = _installCheckers[id];
    if (checker == null) return;
    final present = await _resolverFor(id);
    setPackPresence(id, present);
    setState(id, EngineStatus.loading);
    try {
      final found = await checker();
      setProbeNote(id, null);
      setState(id, found ? EngineStatus.installed : EngineStatus.missing);
    } catch (e) {
      setProbeNote(id, '$e');
      setState(id, present ? EngineStatus.error : EngineStatus.missing);
    }
  }

  /// Load a model into RAM. Throws [ModelNotInstalledException] when the data
  /// is not packaged (we do not fabricate a ready state).
  Future<bool> loadModel(FlmModelId id) async {
    final current = _models[id]!;
    if (current.state == EngineStatus.ready ||
        current.state == EngineStatus.loading) {
      return true;
    }
    if (current.state == EngineStatus.missing) {
      throw ModelNotInstalledException(id);
    }
    setState(id, EngineStatus.loading);
    final loader = _loaders[id];
    if (loader == null) {
      setState(id, EngineStatus.ready);
      return true;
    }
    try {
      await loader();
      setState(id, EngineStatus.ready);
      return true;
    } catch (_) {
      setState(id, EngineStatus.error);
      return false;
    }
  }

  /// Release a model from RAM. The data stays on device, so the state returns
  /// to [EngineStatus.installed] (low-end RAM rule: only the active screen's
  /// models stay loaded).
  Future<void> unloadModel(FlmModelId id) async {
    final unloader = _unloaders[id];
    if (unloader != null) {
      try {
        await unloader();
      } catch (_) {
        // Best-effort release; native session teardown is idempotent.
      }
    }
    final current = _models[id]!;
    if (current.state == EngineStatus.ready ||
        current.state == EngineStatus.loading ||
        current.state == EngineStatus.installed) {
      setState(id, EngineStatus.installed);
    }
  }

  void setState(FlmModelId id, EngineStatus state) {
    _models[id] = _models[id]!.copyWith(state: state);
    notifyListeners();
  }

  /// Record whether the pack files are physically on the device (independent
  /// of whether the runtime can initialize them).
  void setPackPresence(FlmModelId id, bool? present) {
    _models[id] = _models[id]!.copyWith(packPresent: present);
    notifyListeners();
  }

  /// Record a dynamic note from the latest probe (e.g. the exact runtime
  /// init failure so Settings can show why the model is Error/Missing).
  /// Pass a non-null note; use [clearProbeNote] to clear (copyWith treats
  /// a null argument as "keep", so null here would NOT clear).
  void setProbeNote(FlmModelId id, String? note) {
    if (note == null) {
      clearProbeNote(id);
      return;
    }
    _models[id] = _models[id]!.copyWith(probeNote: note);
    notifyListeners();
  }

  /// Clear a stale probe note (e.g. after a later probe succeeds — otherwise
  /// an old error would linger next to a healthy state).
  void clearProbeNote(FlmModelId id) {
    _models[id] = FlmModelInfo(
      name: _models[id]!.name,
      state: _models[id]!.state,
      storageRequiredMb: _models[id]!.storageRequiredMb,
      detail: _models[id]!.detail,
      integrationPoint: _models[id]!.integrationPoint,
      packPresent: _models[id]!.packPresent,
      probeNote: null,
    );
    notifyListeners();
  }

  void setLoading(FlmModelId id) => setState(id, EngineStatus.loading);

  /// Load-and-park helper used by callers that only need the status updated.
  Future<void> markReadyAfterLoad(FlmModelId id, Future<void> loader) async {
    setLoading(id);
    try {
      await loader;
      setState(id, EngineStatus.ready);
    } catch (_) {
      setState(id, EngineStatus.error);
    }
    notifyListeners();
  }

  int totalStorageRequiredMb() {
    var sum = 0;
    for (final m in _models.values) {
      if (m.state == EngineStatus.missing && m.storageRequiredMb != null) {
        sum += m.storageRequiredMb!;
      }
    }
    return sum;
  }
}