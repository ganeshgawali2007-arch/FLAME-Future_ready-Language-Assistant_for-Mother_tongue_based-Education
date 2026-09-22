/// Debug-only, on-device NMT runtime self-test.
///
/// Triggered by a flag file (`nmt_selftest.flag`) in the app-external files
/// dir AND kDebugMode — release builds and normal debug launches are never
/// affected. It isolates the direct translation path (no microphone, no live
/// classroom): tokenizer ids, the native ONNX loop, decoded output, and the
/// pipeline tier (cache vs model vs explicit failure) for the three directive
/// sentences. Every line is also written to `nmt_selftest_result.txt` in the
/// same dir so the evidence survives adb/USB flakiness and the app process.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/enums.dart';
import 'nmt_engine.dart';
import 'nmt_model_pack.dart';
import 'nmt_tokenizer.dart';
import 'offline_translation_engine.dart';

class NmtSelfTest {
  NmtSelfTest._();

  static const String flagName = 'nmt_selftest.flag';
  static const String resultName = 'nmt_selftest_result.txt';

  static const List<String> sentences = [
    'आज हम पौधों के बारे में सीखेंगे।',
    'अपनी किताब खोलो।',
    'ध्यान से सुनो।',
  ];

  /// First app-external files dir, or null when unavailable (desktop tests).
  static Future<String?> _externalBase() async {
    List<Directory>? dirs;
    try {
      dirs = await getExternalStorageDirectories();
    } catch (_) {
      dirs = const [];
    }
    if (dirs == null || dirs.isEmpty) return null;
    return dirs.first.path;
  }

  /// True when the self-test flag is present (and this is a debug build).
  /// Callers MUST gate the normal startup probe on this, so the self-test is
  /// the only owner of the shared backend while it runs.
  static Future<bool> isArmed() async {
    if (!kDebugMode) return false;
    final base = await _externalBase();
    if (base == null) return false;
    return File('$base/$flagName').existsSync();
  }

  /// Runs the full self-test and returns true only when the pack resolved,
  /// warmUp succeeded, and every sentence plus the pipeline tier produced a
  /// result. Each step's evidence is both logged and written to
  /// [resultName] so it survives adb/USB flakiness and app restarts.
  static Future<bool> run({
    required IndicTrans2Backend backend,
    required NmtTokenizer tokenizer,
    required NmtModelPack pack,
    required OfflineTranslationEngine pipeline,
    String? outputDir,
  }) async {
    final base = outputDir ?? await _externalBase();
    final lines = <String>[];
    void emit(String line) {
      debugPrint('FLAME_NMT_SELFTEST $line');
      lines.add(line);
    }

    var ok = true;
    void flagIf(bool v) {
      if (!v) ok = false;
    }

    try {
      emit('START lang_src=hin_Deva lang_tgt=sat_Olck '
          'sentences=${sentences.length}');
      emit('PATH_MODEL_DIR_REQUIRED ${NmtModelPack.requiredFiles.length} files '
          'floors=${NmtModelPack.requiredFiles}');

      String? modelDir;
      for (final dir in await pack.candidateDirs()) {
        final audit = NmtModelPack.audit(dir);
        emit('CANDIDATE dir=${dir.path} '
            'complete=${audit.every((a) => a.ok)}');
        for (final a in audit) {
          emit('CANDIDATE_FILE dir=${dir.path} name=${a.name} '
              'exists=${a.exists} bytes=${a.sizeBytes} floor=${a.minBytes} '
              'ok=${a.ok}');
        }
        if (audit.every((a) => a.ok)) modelDir = dir.path;
      }
      if (modelDir == null) {
        emit('FAIL pack unresolved (no complete candidate dir)');
        ok = false;
        _write(base, resultName, lines);
        return ok;
      }
      emit('RESOLVED modelDir=$modelDir');

      final warmed = await backend.warmUp();
      emit('WARMUP ok=$warmed installed=${backend.isInstalled} '
          'dir=${backend.modelDir}');
      flagIf(warmed && backend.isInstalled);
      if (!ok) {
        _write(base, resultName, lines);
        return ok;
      }

      final meta = tokenizer.meta;
      emit('META srcDict=${meta.srcDictSize} tgtDict=${meta.tgtDictSize} '
          'decoderStart=${meta.decoderStartTokenId} eos=${meta.eosTokenId} '
          'maxLength=${meta.maxLength}');

      for (var i = 0; i < sentences.length; i++) {
        final s = sentences[i];
        final prefixed =
            tokenizer.preprocess(s, srcLang: 'hin_Deva', tgtLang: 'sat_Olck');
        final ids = tokenizer.encode(prefixed, target: false);
        emit('SENTENCE[$i] raw="${s.length > 80 ? s.substring(0, 80) : s}" '
            'prefixedLen=${prefixed.length}');
        emit('INPUT_IDS[$i] len=${ids.length} ids=$ids');
        try {
          final r = await backend.translate(
            s,
            source: AppLanguage.hindi,
            target: AppLanguage.santhali,
          );
          emit('RESULT[$i] quality=${r.quality.name} canTranslate=${r.canTranslate} '
              'chars=${r.targetText.runes.length} '
              'out="${r.targetText.length > 120 ? r.targetText.substring(0, 120) : r.targetText}"');
          flagIf(r.canTranslate && r.targetText.isNotEmpty &&
              r.quality.name != 'fallback');
        } catch (e) {
          emit('RESULT[$i] FAIL exactException="$e"');
          flagIf(false);
        }
      }

      // Pipeline tier evidence for one sentence: cache vs model vs explicit.
      emit('PIPELINE_TEST start');
      try {
        final p = await pipeline.translate(
          sentences[1],
          source: AppLanguage.hindi,
          target: AppLanguage.santhali,
        );
        emit('PIPELINE_TEST quality=${p.quality.name} canTranslate=${p.canTranslate} '
            'chars=${p.targetText.runes.length} '
            'out="${p.targetText.length > 120 ? p.targetText.substring(0, 120) : p.targetText}"');
        flagIf(p.canTranslate && p.targetText.isNotEmpty);
      } catch (e) {
        emit('PIPELINE_TEST FAIL exactException="$e"');
        flagIf(false);
      }

      emit('DONE ok=$ok');
    } catch (e, st) {
      ok = false;
      emit('DONE ok=false exactException="$e"');
      emit('STACK ${st.toString().split('\n').take(6).join(' | ')}');
    }

    _write(base, resultName, lines);
    return ok;
  }

  static Future<void> _write(String? dir, String name, List<String> lines) async {
    if (dir == null) {
      debugPrint('FLAME_NMT_SELFTEST RESULT_WRITE_SKIP no external dir');
      return;
    }
    try {
      final f = File('$dir/$name');
      await f.writeAsString('${lines.join('\n')}\n');
      debugPrint('FLAME_NMT_SELFTEST WROTE $dir/$name (${lines.length} lines)');
    } catch (e) {
      debugPrint('FLAME_NMT_SELFTEST_RESULT_WRITE_FAILED exact="$e"');
    }
  }
}