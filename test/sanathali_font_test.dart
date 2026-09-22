import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/widgets/sanathali_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const olChikiWord = 'ᱥᱮᱛᱟᱜ';
  const olChikiSentence = 'ᱮᱛᱚᱢ ᱨᱮ';

  testWidgets(
      'SanathaliText applies the bundled Ol Chiki font and keeps glyphs',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SanathaliText(
            olChikiSentence,
            style: TextStyle(fontSize: 16, color: Colors.black),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, olChikiSentence);
    expect(text.style!.fontFamily, 'NotoSansOlChiki');
  });

  testWidgets('word and sentence text is carried verbatim', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SanathaliText(olChikiWord),
              SanathaliText(olChikiSentence),
            ],
          ),
        ),
      ),
    );

    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts.map((t) => t.data), [olChikiWord, olChikiSentence]);
    for (final t in texts) {
      expect(t.style!.fontFamily, 'NotoSansOlChiki');
    }
  });

  test('Noto Sans Ol Chiki font asset is bundled', () async {
    final data = await rootBundle.load('assets/fonts/NotoSansOlChiki.ttf');
    expect(data.lengthInBytes, greaterThan(0));
  });
}