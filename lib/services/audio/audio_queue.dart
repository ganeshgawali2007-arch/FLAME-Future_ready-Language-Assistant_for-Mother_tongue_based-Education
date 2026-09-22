/// Speech-output queue used by the live classroom and the voice bot.
///
/// Guarantees ordered playback — one utterance at a time, no overlapping
/// speech. The teacher can keep producing new turns while the previous phrase
/// is still playing: new turns are enqueued and drained sequentially. [clear]
/// interrupts the currently speaking job (via the injected [AudioInterrupt]
/// callback, e.g. TTS.stop) and cancels everything queued.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/enums.dart';

enum AudioJobState { queued, speaking, done, failed, cancelled }

class AudioJob {
  AudioJob(this.id, this.text, this.language);
  final int id;
  final String text;
  final AppLanguage language;
  AudioJobState state = AudioJobState.queued;
  String? failureMessage;
}

typedef AudioSpeaker = Future<bool> Function(String text, AppLanguage language);
typedef AudioInterrupt = Future<void> Function();

class AudioQueue extends ChangeNotifier {
  AudioQueue(this._speaker, {AudioInterrupt? interrupt})
      : _interrupt = interrupt ?? (() async {});

  final AudioSpeaker _speaker;
  final AudioInterrupt _interrupt;
  final List<AudioJob> _jobs = [];
  int _nextId = 1;
  bool _draining = false;

  List<AudioJob> get jobs => List.unmodifiable(_jobs);
  bool get isSpeaking => _jobs.any((j) => j.state == AudioJobState.speaking);
  bool get hasPending => _jobs.any(
        (j) => j.state == AudioJobState.queued ||
            j.state == AudioJobState.speaking,
      );

  void enqueue(String text, {AppLanguage language = AppLanguage.hindi}) {
    _jobs.add(AudioJob(_nextId++, text, language));
    notifyListeners();
    _run();
  }

  Future<void> _run() async {
    if (_draining) return;
    _draining = true;
    while (_jobs.any((j) => j.state == AudioJobState.queued)) {
      final job = _jobs.firstWhere((j) => j.state == AudioJobState.queued);
      job.state = AudioJobState.speaking;
      notifyListeners();
      bool ok;
      try {
        ok = await _speaker(job.text, job.language);
      } catch (_) {
        ok = false;
      }
      job.state = ok ? AudioJobState.done : AudioJobState.failed;
      if (!ok) {
        job.failureMessage = 'Audio playback failed';
      }
      notifyListeners();
    }
    _draining = false;
  }

  /// Interrupt the current utterance and cancel all queued jobs.
  Future<void> clear() async {
    await _interrupt();
    for (final j in _jobs) {
      if (j.state == AudioJobState.queued) {
        j.state = AudioJobState.cancelled;
      }
    }
    notifyListeners();
  }

  void markFailed(AudioJob job, String message) {
    job.state = AudioJobState.failed;
    job.failureMessage = message;
    notifyListeners();
  }
}