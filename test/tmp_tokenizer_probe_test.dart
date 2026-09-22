import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/services/translation/nmt_tokenizer.dart';

const _root = 'D:\\FOREST-FLAME\\Flame apk';

Future<Map<String, String>> _testLoader() async {
  Future<String> load(String path) async =>
      (await File('$_root/$path').readAsString()).trim();
  return {
    'vocab_src': await load('assets/nmt/nmt_vocab_src.txt'),
    'vocab_tgt': await load('assets/nmt/nmt_vocab_tgt.txt'),
    'merges_src': await load('assets/nmt/nmt_merges_src.txt'),
    'merges_tgt': await load('assets/nmt/nmt_merges_tgt.txt'),
    'added_src': await load('assets/nmt/nmt_added_src.txt'),
    'added_tgt': await load('assets/nmt/nmt_added_tgt.txt'),
    'meta': await load('assets/nmt/nmt_meta.json'),
  };
}

void main() {
  test('dart tokenizer on the device sentence', () async {
    final tok = NmtTokenizer(assetLoader: _testLoader);
    await tok.load();
    const s = 'बच्चों ने पौधे लगाए और पानी दिया';
    final prefixed = tok.preprocess(s,
        srcLang: 'hin_Deva', tgtLang: 'sat_Olck');
    debugPrint('PREF= $prefixed');
    final ids = tok.encode(prefixed, target: false);
    debugPrint('IDS= $ids (count=${ids.length})');
    expect(prefixed, 'hin_Deva sat_Olck बच्चों ने पौधे लगाए और पानी दिया');
  });
}