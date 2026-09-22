import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/enums.dart';
import 'package:flame/services/audio/audio_queue.dart';

void main() {
  group('AudioQueue ordering', () {
    test('plays exactly one job at a time, in order', () async {
      final order = <String>[];
      final gates = <Completer<bool>>[];

      final queue = AudioQueue((text, language) {
        order.add(text);
        final gate = Completer<bool>();
        gates.add(gate);
        return gate.future;
      });

      queue.enqueue('A');
      queue.enqueue('B');

      await Future<void>.delayed(Duration.zero);
      expect(order, ['A'], reason: 'second job must wait');
      expect(queue.isSpeaking, isTrue);

      gates[0].complete(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(order, ['A', 'B']);
      expect(gates, hasLength(2));
      expect(queue.isSpeaking, isTrue, reason: 'B has started speaking');

      gates[1].complete(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(queue.jobs.map((j) => j.state), everyElement(
        equals(AudioJobState.done),
      ));
      expect(queue.isSpeaking, isFalse);
    });

    test('enqueue while speaking keeps teacher input non-blocking', () async {
      final order = <String>[];
      final gates = <Completer<bool>>[];
      final queue = AudioQueue((text, language) {
        order.add(text);
        final gate = Completer<bool>();
        gates.add(gate);
        return gate.future;
      });

      queue.enqueue('first');
      await Future<void>.delayed(Duration.zero);
      queue.enqueue('second'); // teacher continues before first finishes
      queue.enqueue('third');
      expect(queue.jobs, hasLength(3));

      gates[0].complete(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(order, ['first', 'second']);
      gates[1].complete(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      gates[2].complete(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(order, ['first', 'second', 'third']);
    });
  });

  group('AudioQueue interrupt / clear', () {
    test('clear interrupts the current job and cancels queued ones', () async {
      var interrupted = false;
      final gates = <Completer<bool>>[];
      final queue = AudioQueue(
        (text, language) {
          final gate = Completer<bool>();
          gates.add(gate);
          return gate.future;
        },
        interrupt: () async => interrupted = true,
      );

      queue.enqueue('A');
      queue.enqueue('B');
      queue.enqueue('C');
      await Future<void>.delayed(Duration.zero);
      expect(gates, hasLength(1), reason: 'only A started');

      await queue.clear();

      expect(interrupted, isTrue);
      // Queued B/C cancelled immediately; the speaking A is still awaiting its
      // device future, which resolves false once interrupted.
      expect(queue.jobs[0].state, AudioJobState.speaking);
      expect(queue.jobs[1].state, AudioJobState.cancelled);
      expect(queue.jobs[2].state, AudioJobState.cancelled);

      gates[0].complete(false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final states = queue.jobs.map((j) => j.state).toList();
      expect(states, [AudioJobState.failed, AudioJobState.cancelled,
        AudioJobState.cancelled]);
      expect(queue.jobs[0].failureMessage, isNotNull);
      expect(queue.hasPending, isFalse);
    });

    test('failed speech surfaces the failure message', () async {
      final queue = AudioQueue(
        (text, language) async => false,
      );
      queue.enqueue('X');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(queue.jobs.single.state, AudioJobState.failed);
      expect(queue.jobs.single.failureMessage, isNotNull);
    });
  });

  test('santhali language is carried on the job', () {
    final queue = AudioQueue((text, language) async => true);
    queue.enqueue('ᱥᱮᱛᱟᱜ', language: AppLanguage.santhali);
    expect(queue.jobs.single.language, AppLanguage.santhali);
  });
}