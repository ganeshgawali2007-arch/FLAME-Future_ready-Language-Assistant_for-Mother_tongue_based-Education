import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flame/services/translation/nmt_model_pack.dart';

void main() {
  group('NmtModelPack', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('nmt_pack_test');
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    Future<void> writeFake(String name, int size) async {
      final f = File('${tmp.path}/$name');
      final raf = await f.open(mode: FileMode.write);
      // truncate() also extends, so this creates an exact-size file instantly.
      await raf.truncate(size);
      await raf.close();
    }

    test('isComplete false when directory is empty', () {
      expect(NmtModelPack.isComplete(tmp), isFalse);
    });

    test('isComplete false when a file is truncated', () async {
      for (final entry in NmtModelPack.requiredFiles.entries) {
        await writeFake(entry.key, entry.value);
      }
      // Truncate one required file below its floor.
      await writeFake('decoder_shared.onnx.data', 1024);
      expect(NmtModelPack.isComplete(tmp), isFalse);
    });

    test('isComplete true when every file meets its floor', () async {
      for (final entry in NmtModelPack.requiredFiles.entries) {
        await writeFake(entry.key, entry.value);
      }
      expect(NmtModelPack.isComplete(tmp), isTrue);
    });

    test('resolveModelDir returns the complete candidate dir', () async {
      for (final entry in NmtModelPack.requiredFiles.entries) {
        await writeFake(entry.key, entry.value);
      }
      final pack = NmtModelPack(candidateDirs: () async => [tmp]);
      expect(await pack.resolveModelDir(), tmp.path);
    });

    test('resolveModelDir returns null when no candidate is complete',
        () async {
      final pack = NmtModelPack(candidateDirs: () async => [tmp]);
      expect(await pack.resolveModelDir(), isNull);
    });

    test('resolveModelDir skips unreadable/missing candidates', () async {
      final missing = Directory('${tmp.path}/does-not-exist');
      for (final entry in NmtModelPack.requiredFiles.entries) {
        await writeFake(entry.key, entry.value);
      }
      final pack =
          NmtModelPack(candidateDirs: () async => [missing, tmp]);
      expect(await pack.resolveModelDir(), tmp.path);
    });
  });
}
