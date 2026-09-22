import 'package:flutter_test/flutter_test.dart';

import 'package:flame/app.dart';

import 'tts_channel_mock.dart';

void main() {
  testWidgets('app builds, shows splash, and proceeds to welcome', (tester) async {
    installTtsChannelMock();
    installSatTtsChannelMock();
    await tester.pumpWidget(const FlameApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('FLAME'), findsOneWidget);
    expect(find.text('Learn in your language.'), findsOneWidget);

    // Let the splash timer fire and navigation settle.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Landed on the welcome screen (FLAME brand + Get Started CTA).
    expect(find.text('Get Started'), findsOneWidget);
  });
}