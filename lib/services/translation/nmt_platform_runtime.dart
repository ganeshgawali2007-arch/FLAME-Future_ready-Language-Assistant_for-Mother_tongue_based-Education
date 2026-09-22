/// Android [NmtRuntime] over the `flame/nmt` platform channel.
///
/// The native side ([OnnxNmtSession.kt]) owns the ORT sessions and all past
/// tensors; only tiny per-step calls cross the channel (ids in, one id out —
/// the 122k-float logits vector is argmaxed natively).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'nmt_engine.dart';
import 'nmt_tokenizer.dart';

class MethodChannelNmtRuntime implements NmtRuntime {
  MethodChannelNmtRuntime({
    required this.metaProvider,
    MethodChannel? channel,
  }) : channel = channel ?? const MethodChannel('flame/nmt');

  final NmtMeta Function() metaProvider;
  final MethodChannel channel;

  bool _loaded = false;

  @override
  bool get isLoaded => _loaded;

  @override
  Future<void> load(String modelDir) async {
    if (_loaded) return;
    final meta = metaProvider();
    final sw = Stopwatch()..start();
    debugPrint('FLAME_NMT CHANNEL load modelDir=$modelDir');
    final state = await channel.invokeMethod<String>('load', {
      'modelDir': modelDir,
      'decoderStartId': meta.decoderStartTokenId,
    });
    _loaded = state == 'ready';
    debugPrint('FLAME_NMT CHANNEL load -> state=$state loaded=$_loaded '
        '(${sw.elapsedMilliseconds}ms)');
    if (!_loaded) {
      throw StateError('NMT native runtime not ready (state=$state)');
    }
  }

  @override
  Future<int> startDecode(List<int> inputIds, List<int> attentionMask) async {
    final sw = Stopwatch()..start();
    final next = await channel.invokeMethod<int>('startDecode', {
      'inputIds': inputIds,
      'attentionMask': attentionMask,
    });
    debugPrint('FLAME_NMT CHANNEL startDecode ids=${inputIds.length} '
        '-> next=$next (${sw.elapsedMilliseconds}ms)');
    if (next == null) {
      throw StateError('NMT startDecode returned null');
    }
    return next;
  }

  @override
  Future<int> step(int nextId) async {
    final sw = Stopwatch()..start();
    final next = await channel.invokeMethod<int>('step', {'nextId': nextId});
    debugPrint('FLAME_NMT CHANNEL step in=$nextId -> out=$next '
        '(${sw.elapsedMilliseconds}ms)');
    if (next == null) {
      throw StateError('NMT step returned null');
    }
    return next;
  }

  @override
  Future<void> endDecode() async {
    try {
      await channel.invokeMethod<void>('endDecode');
    } catch (_) {
      // Best-effort: native teardown is idempotent.
    }
  }

  @override
  Future<void> release() async {
    try {
      await channel.invokeMethod<void>('release');
    } catch (_) {
      // Best-effort: native teardown is idempotent.
    }
    _loaded = false;
  }
}
