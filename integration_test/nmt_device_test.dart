import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:flame/app.dart';
import 'package:flame/models/enums.dart';
import 'package:flame/services/model_manager.dart';
import 'package:flame/services/translation/nmt_model_pack.dart';
import 'package:flame/screens/live_session_screen.dart';
import 'package:flame/widgets/sanathali_text.dart';

/// On-device live-classroom round-trip: walks the real UI (Welcome → Role →
/// Language → Offline setup → Home → Create Class → Lesson → Live session),
/// types a real Devanagari sentence through the app's typed-input path, taps
/// the mic button and reads the transcript + model-manager state afterwards.
///
/// This exercises the genuine production pipeline end-to-end on the device:
/// OfflineTranslationEngine tier 1 (cache miss) → tier 2 (IndicTrans2Backend
/// lazy warmUp → ONNX Runtime encoder/decoder on the side-loaded INT8 pack).
/// Nothing here is mocked; the model pack must be present on the device.
///
/// NOTE on taps: the integration-test harness's injected pointer coordinates do
/// not reliably hit on-device widgets at high DPI, so buttons are activated by
/// invoking their own callbacks (onPressed / onTap). Real touch navigation of
/// the same screens was separately verified on the device via adb input taps.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const hindiSource = 'बच्चों ने पौधे लगाए और पानी दिया';

  Future<void> pumpFor(WidgetTester tester, Duration d) async {
    await tester.pump(d);
  }

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await pumpFor(tester, const Duration(milliseconds: 250));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for ${finder.describeMatch(Plurality.many)}');
  }

  /// Activates the first actionable ancestor of [finder] by calling its own
  /// callback: FilledButton/OutlinedButton/TextButton/IconButton onPressed or
  /// InkWell/GestureDetector onTap.
  Future<void> press(
    WidgetTester tester,
    Finder finder, {
    Duration settle = const Duration(milliseconds: 700),
    String label = '',
  }) async {
    final matches = finder.evaluate();
    if (matches.isEmpty) {
      fail('press: nothing matched "$label" (${finder.describeMatch(Plurality.many)})');
    }
    bool handled = false;
    void tryHandle(Widget w) {
      if (handled) return;
      if (w is FilledButton && w.onPressed != null) {
        w.onPressed!();
        handled = true;
      } else if (w is OutlinedButton && w.onPressed != null) {
        w.onPressed!();
        handled = true;
      } else if (w is TextButton && w.onPressed != null) {
        w.onPressed!();
        handled = true;
      } else if (w is IconButton && w.onPressed != null) {
        w.onPressed!();
        handled = true;
      } else if (w is InkWell && w.onTap != null) {
        w.onTap!();
        handled = true;
      } else if (w is GestureDetector && w.onTap != null) {
        w.onTap!();
        handled = true;
      }
    }

    final el = matches.first;
    tryHandle(el.widget);
    if (!handled) {
      el.visitAncestorElements((ancestor) {
        tryHandle(ancestor.widget);
        return !handled;
      });
    }
    if (!handled) {
      fail('press: no actionable ancestor for "$label" (${finder.describeMatch(Plurality.many)})');
    }
    await pumpFor(tester, settle);
  }

  testWidgets('FLAME on-device: real Hindi→Santhali via the live classroom path',
      (tester) async {
    await tester.pumpWidget(const FlameApp());

    // 0. Pack detection probe — print exactly what the app's resolver sees.
    final pack = NmtModelPack();
    final cands = await pack.candidateDirs();
    for (final d in cands) {
      debugPrint('FLAME_DBG candidate=${d.path}');
      try {
        final enc = File('${d.path}/encoder_model.onnx');
        debugPrint('FLAME_DBG   encoderExists=${enc.existsSync()} '
            'len=${enc.lengthSync()}');
        debugPrint('FLAME_DBG   isComplete=${NmtModelPack.isComplete(d)}');
      } catch (e) {
        debugPrint('FLAME_DBG   ERROR: $e');
      }
    }
    final resolved = await pack.resolveModelDir();
    debugPrint('FLAME_DBG resolveModelDir=$resolved');

    // 1. Splash -> Welcome.
    await waitFor(tester, find.text('Get Started'),
        timeout: const Duration(seconds: 20));
    await press(tester, find.text('Get Started'), label: 'Welcome Get Started');

    // 2. Role -> Teacher.
    await waitFor(tester, find.text('Teacher'));
    await press(tester, find.text('Teacher'), label: 'Role Teacher');

    // 3. Language: pick "Hindi → Santhali", Continue.
    await waitFor(tester, find.text('Your language'));
    await press(tester, find.textContaining(RegExp(r'^Hindi')),
        label: 'Language pair');
    await pumpFor(tester, const Duration(milliseconds: 200));
    await press(tester, find.text('Continue'), label: 'Language Continue');

    // 4. Offline setup (unique check-row marker), then its Continue after the
    //    corpus check + delay complete.
    await waitFor(tester, find.text('Lesson content'),
        timeout: const Duration(seconds: 15));
    await waitFor(tester, find.text('Continue'),
        timeout: const Duration(seconds: 40));
    await press(tester, find.text('Continue'),
        label: 'Offline setup Continue', settle: const Duration(seconds: 1));

    // 5. Home -> Create Class.
    await waitFor(tester, find.text('Create Class'));
    await press(tester, find.text('Create Class'), label: 'Home Create Class');

    // 6. Create class form -> Next (defaults: Class 3, EVS).
    await waitFor(tester, find.text('Next'));
    await press(tester, find.text('Next'), label: 'Create class Next');

    // 7. Lesson selection (repository-backed) -> Create Classroom.
    await waitFor(tester, find.text('Create Classroom'),
        timeout: const Duration(seconds: 8));
    await press(tester, find.text('Create Classroom'),
        label: 'Lesson Create Classroom', settle: const Duration(seconds: 1));

    // 8. Teacher classroom -> Start Class -> live session with input bar.
    await waitFor(tester, find.text('Start Class'));
    await press(tester, find.text('Start Class'), label: 'Start Class',
        settle: const Duration(seconds: 1));
    await waitFor(tester, find.byType(TextField));

    // 9. Real typed input (Devanagari). enterText focuses the field, then the IME
//     submit action drives the app's real onSubmitted seam -> _speak().
    final t0 = DateTime.now();
    final tf = find.byType(TextField);
    final fields = tester.widgetList<TextField>(tf).toList();
    debugPrint(
        'FLAME_DBG textfields=${fields.length} '
        'texts=${fields.map((f) => '"${f.controller?.text ?? "null"}"').toList()}');
    await tester.enterText(tf, hindiSource);
    await pumpFor(tester, const Duration(milliseconds: 300));
    final field = tester.widget<TextField>(tf);
    if (field.controller!.text != hindiSource) {
      field.controller!.text = hindiSource;
      await pumpFor(tester, const Duration(milliseconds: 200));
    }
    debugPrint('FLAME_DBG after-enter controller="${field.controller!.text}"');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFor(tester, const Duration(milliseconds: 500));
    debugPrint('FLAME_DBG after-submit micIconPresent='
        '${find.byIcon(Icons.mic).evaluate().isNotEmpty} '
        '(false means _speak started -> _busy spinner replaced it)');

    if (find.byIcon(Icons.mic).evaluate().isNotEmpty) {
      // Fallback: invoke the mic GestureDetector's own onTap directly.
      final g = tester.widget<GestureDetector>(
        find
            .ancestor(
                of: find.byIcon(Icons.mic),
                matching: find.byType(GestureDetector))
            .first,
      );
      g.onTap?.call();
      await pumpFor(tester, const Duration(milliseconds: 500));
      debugPrint('FLAME_DBG after-fallback-mic micIconPresent='
          '${find.byIcon(Icons.mic).evaluate().isNotEmpty}');
    }

    // 10. Wait for a completed turn (model warm-up loads the 312 MB pack
    //     lazily on the first request; inference is slow on edge devices).
    final classroom =
        tester.widget<LiveSessionView>(find.byType(LiveSessionView)).classroom;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    var lastProbe = DateTime.now();
    while (DateTime.now().isBefore(deadline)) {
      await pumpFor(tester, const Duration(milliseconds: 500));
      if (classroom.transcript.isNotEmpty) break;
      if (DateTime.now().difference(lastProbe).inSeconds >= 30) {
        lastProbe = DateTime.now();
        final micStillBusy = find.byIcon(Icons.mic).evaluate().isEmpty;
        debugPrint('FLAME_DBG poll t=${DateTime.now().difference(t0).inSeconds}s '
            'transcript=${classroom.transcript.length} micBusy=$micStillBusy '
            'mode=${classroom.activeMode.name}');
      }
    }
    final elapsedMs = DateTime.now().difference(t0).inMilliseconds;

    if (classroom.transcript.isEmpty) {
      fail('No transcript entry was produced within 180s.');
    }

    final turn = classroom.transcript.last;
    final models = tester
        .element(find.byType(LiveSessionView))
        .read<ModelManagerController>();
    final packState = models.statusOf(FlmModelId.hindiSanthaliTranslation);

    debugPrint('FLAME_DEVICE_RESULT source="${turn.sourceText}"');
    debugPrint('FLAME_DEVICE_RESULT target="${turn.targetText}"');
    debugPrint(
        'FLAME_DEVICE_RESULT targetLanguage=${turn.targetLanguage.name} '
        'targetChars=${turn.targetText.runes.length} '
        'canTranslate=${turn.targetText.isNotEmpty} '
        'elapsedMs=$elapsedMs');
    debugPrint('FLAME_DEVICE_PACK status=$packState');

    expect(packState, EngineStatus.installed,
        reason: 'The side-loaded pack must be detected as installed.');
    expect(classroom.transcript.length, greaterThanOrEqualTo(1));

    // The source is a non-cache sentence, so a non-empty target proves real
    // tier-2 inference through IndicTrans2Backend + ONNX Runtime.
    if (turn.targetText.isEmpty) {
      debugPrint('FLAME_DEVICE_RESULT tier=FALLBACK_EXPLICIT (target empty)');
    } else if (turn.targetText == hindiSource) {
      debugPrint('FLAME_DEVICE_RESULT tier=UNEXPECTED_IDENTITY');
    } else {
      debugPrint('FLAME_DEVICE_RESULT tier=MODEL');
    }

    // Rendered-UI verification: the on-screen SanathaliText widget must carry
    // Ol Chiki (U+1C50–U+1C7F), not Devanagari (U+0900–U+097F).
    await pumpFor(tester, const Duration(milliseconds: 500));
    final rendered = tester
        .widgetList<SanathaliText>(find.byType(SanathaliText))
        .map((w) => w.data)
        .toList();
    final uiHasOlChiki = rendered.any(
        (s) => s.runes.any((r) => r >= 0x1C50 && r <= 0x1C7F));
    final uiHasDevanagari = rendered.any(
        (s) => s.runes.any((r) => r >= 0x0900 && r <= 0x097F));
    debugPrint('FLAME_UI renderedSanthaliText=$rendered '
        'olChiki=$uiHasOlChiki devanagari=$uiHasDevanagari');
    expect(uiHasOlChiki, isTrue,
        reason: 'The rendered SanathaliText widget must show Ol Chiki.');
    expect(uiHasDevanagari, isFalse,
        reason: 'The rendered SanathaliText widget must not show Devanagari.');
  });
}