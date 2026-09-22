/// Side-loaded IndicTrans2 INT8 model pack: presence probe + locations.
///
/// The pack is deliberately NOT bundled in the APK (keeps it ~135 MB). The
/// five files (≈312 MB total) are copied by the user/system into one of the
/// app-accessible directories — no network, no server:
///
///   Android/data/com.flame.flame/files/nmt_model/   (USB / Files app / adb)
///   [app files dir]/nmt_model/                      (internal)
/// Honesty contract: [resolveModelDir] returns a directory only when every
/// required file genuinely exists with a plausible size.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Per-file pack audit record, used by the runtime diagnostics stream so a
/// failing model init can show exactly which file is missing/truncated.
class PackFileAudit {
  const PackFileAudit({
    required this.name,
    required this.exists,
    required this.sizeBytes,
    required this.minBytes,
  });

  final String name;
  final bool exists;
  final int sizeBytes;
  final int minBytes;

  bool get ok => exists && sizeBytes >= minBytes;
}

class NmtModelPack {
  NmtModelPack({Future<List<Directory>> Function()? candidateDirs})
      : _candidateDirs = candidateDirs ?? _defaultCandidateDirs;

  final Future<List<Directory>> Function() _candidateDirs;

  static const String dirName = 'nmt_model';

  /// Required files with minimum plausible sizes (bytes). Exact sizes are
  /// avoided on purpose: a re-exported pack may differ by a few bytes, but a
  /// truncated copy is always far below these floors.
  static const Map<String, int> requiredFiles = {
    'encoder_model.onnx': 100 * 1024, // ~0.8 MB
    'encoder_model.onnx.data': 100 * 1024 * 1024, // ~114.5 MB
    'decoder_model.onnx': 1024 * 1024, // ~1.9 MB
    'decoder_with_past_model.onnx': 1024 * 1024, // ~1.8 MB
    'decoder_shared.onnx.data': 150 * 1024 * 1024, // ~193.6 MB
  };

  static const int totalSizeMb = 312;

  static Future<List<Directory>> _defaultCandidateDirs() async {
    final dirs = <Directory>[];
    try {
      final ext = await getExternalStorageDirectories();
      if (ext != null && ext.isNotEmpty) {
        dirs.add(Directory('${ext.first.path}/$dirName'));
      }
    } catch (_) {
      // External app dir unavailable (desktop tests, weird devices).
    }
    try {
      final support = await getApplicationSupportDirectory();
      dirs.add(Directory('${support.path}/$dirName'));
    } catch (_) {
      // Internal dir unavailable.
    }
    return dirs;
  }

  /// Directories the probe checks, in priority order (external first so the
  /// user-visible USB/Files location wins).
  Future<List<Directory>> candidateDirs() => _candidateDirs();

  /// Audits every required file of [dir] (exists / bytes / floor). Readable
  /// even for incomplete or unreadable packs, so the failure is observable.
  static List<PackFileAudit> audit(Directory dir) {
    final out = <PackFileAudit>[];
    for (final entry in requiredFiles.entries) {
      final f = File('${dir.path}/${entry.key}');
      var exists = false;
      var size = 0;
      try {
        exists = f.existsSync();
        if (exists) size = f.lengthSync();
      } catch (_) {
        // Unreadable file == not usable.
      }
      out.add(PackFileAudit(
        name: entry.key,
        exists: exists,
        sizeBytes: size,
        minBytes: entry.value,
      ));
    }
    return out;
  }

  /// True when [dir] holds every required file at a plausible size.
  static bool isComplete(Directory dir) {
    for (final entry in requiredFiles.entries) {
      final f = File('${dir.path}/${entry.key}');
      if (!f.existsSync()) return false;
      if (f.lengthSync() < entry.value) return false;
    }
    return true;
  }

  /// First candidate directory containing a complete pack, else null.
  Future<String?> resolveModelDir() async {
    for (final dir in await _candidateDirs()) {
      try {
        if (isComplete(dir)) return dir.path;
      } catch (_) {
        // Unreadable dir == not installed; keep probing.
      }
    }
    return null;
  }
}
