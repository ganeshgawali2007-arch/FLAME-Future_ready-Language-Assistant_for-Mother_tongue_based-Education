import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flame/services/translation/nmt_tokenizer.dart';

void main() {
  test('cross-tool preprocess parity (Python harness vs Dart)', () {
    const hin = [
      'सुप्रभात बच्चों।',
      'आज हम पौधों के बारे में सीखेंगे।',
      'अपनी किताब खोलो।',
      'ध्यान से सुनो।',
      'नमस्ते',
      'अच्छा काम किया।',
      'कल की कक्षा का पाठ आज याद करो।',
      'झरना पहाड़ से नीचे बहता है।',
      'भारत के उत्तर में ठंड पड़ती है।',
      'रंग मिलाकर नया रंग बनाओ।',
      'बारिश के बाद इंद्रधनुष दिखाई देता है।',
      'पेड़ हमें छाया और फल देते हैं।',
    ];
    const sat = [
      'ᱛᱮᱦᱮᱧ',
      'ᱥᱮᱛᱟᱜ',
      'ᱵᱤᱨ',
      'ᱥᱟᱱᱛᱟᱲᱤ',
      'ᱫᱟᱜ',
      'ᱠᱩᱲᱤ',
      'ᱢᱟᱹᱱᱢᱤ',
      'ᱡᱟᱱᱟᱢ',
    ];
    final tok = NmtTokenizer();
    final lines = <String>[
      for (final t in hin) 'H|${tok.preprocess(t, srcLang: 'hin_Deva', tgtLang: 'sat_Olck')}',
      for (final t in sat) 'S|${tok.preprocess(t, srcLang: 'sat_Olck', tgtLang: 'hin_Deva')}',
    ];
    final file = File(r'C:\Users\tohid\AppData\Local\Temp\opencode\dart_pre.txt');
    file.writeAsStringSync(lines.join('\n'));
    print('preprocess parity fixture written (${lines.length} lines)');
  });
}