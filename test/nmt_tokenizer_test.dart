import 'dart:convert';
import 'dart:io';

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
  late NmtTokenizer tok;

  setUpAll(() async {
    tok = NmtTokenizer(assetLoader: _testLoader);
    await tok.load();
  });

  group('NmtTokenizer — preprocess parity', () {
    test('all 3154 entries', () async {
      final golden = (jsonDecode(
              await File('$_root/test_data/nmt_preprocess_golden.json')
                  .readAsString())
          as List)
          .cast<List>();
      var pass = 0;
      final fails = <String>[];
      for (final entry in golden) {
        final src = entry[0] as String;
        final tgt = entry[1] as String;
        final sent = entry[2] as String;
        final expected = entry[3] as String;
        final got = tok.preprocess(sent, srcLang: src, tgtLang: tgt);
        if (got == expected) {
          pass++;
        } else {
          if (fails.length < 5) {
            fails.add('[$src→$tgt] $sent\n  EXP $expected\n  GOT $got');
          }
        }
      }
      if (fails.isNotEmpty) {
        fail('$fails');
      }
      expect(pass, golden.length);
    });
  });

  group('NmtTokenizer — encode parity', () {
    test('all 800 entries', () async {
      final golden = (jsonDecode(
              await File('$_root/test_data/nmt_encode_golden.json')
                  .readAsString())
          as List)
          .cast<List>();
      var pass = 0;
      final fails = <String>[];
      for (final entry in golden) {
        final src = entry[0] as String;
        final tgt = entry[1] as String;
        final sent = entry[2] as String;
        final expected = (entry[3] as List).cast<int>();
        final proc = tok.preprocess(sent, srcLang: src, tgtLang: tgt);
        final got = tok.encode(proc, target: false);
        if (got.length == expected.length &&
            List.generate(got.length, (i) => got[i] == expected[i])
                .every((e) => e)) {
          pass++;
        } else {
          if (fails.length < 3) {
            fails.add(
                '[$src→$tgt] len=${got.length}/${expected.length}  sent=$sent'
                '\n  EXP ${expected.take(12).toList()}…'
                '\n  GOT ${got.take(12).toList()}…');
          }
        }
      }
      if (fails.isNotEmpty) {
        fail('$fails');
      }
      expect(pass, golden.length);
    });
  });

  group('NmtTokenizer — decode parity', () {
    test('all 14 entries', () async {
      final golden = (jsonDecode(
              await File('$_root/test_data/nmt_decode_golden.json')
                  .readAsString())
          as List)
          .cast<Map<String, dynamic>>();
      for (final entry in golden) {
        final src = entry['src'] as String;
        final tgt = entry['tgt'] as String;
        final sent = entry['text'] as String;
        final ids = (entry['ids'] as List).cast<int>();
        final expectedRaw = entry['decoded_raw'] as String;
        final expected = entry['expected'] as String;
        tok.preprocess(sent, srcLang: src, tgtLang: tgt);
        final decodedRaw = tok.decodeRaw(ids, target: true);
        final decoded = tok.decode(ids, target: true);
        expect(decodedRaw, expectedRaw);
        expect(decoded, expected);
      }
    });
  });

  group('NmtTokenizer — edge cases', () {
    test('empty string', () {
      final proc = tok.preprocess('', srcLang: 'hin_Deva', tgtLang: 'sat_Olck');
      expect(proc, startsWith('hin_Deva sat_Olck'));
      final ids = tok.encode(proc, target: false);
      expect(ids.last, 2);
    });

    test('single word Hindi', () {
      final proc =
          tok.preprocess('पानी', srcLang: 'hin_Deva', tgtLang: 'sat_Olck');
      final ids = tok.encode(proc, target: false);
      expect(ids, isNotEmpty);
      expect(ids.last, 2);
    });

    test('single word Santali', () {
      final proc =
          tok.preprocess('ᱫᱚ', srcLang: 'sat_Olck', tgtLang: 'hin_Deva');
      final ids = tok.encode(proc, target: false);
      expect(ids, isNotEmpty);
      expect(ids.last, 2);
    });

    test('punctuation only', () {
      final proc =
          tok.preprocess('!', srcLang: 'hin_Deva', tgtLang: 'sat_Olck');
      final ids = tok.encode(proc, target: false);
      expect(ids.length, greaterThanOrEqualTo(3)); // lang tags + punct + eos
      expect(ids.last, 2);
    });

    test('number preservation', () {
      final proc =
          tok.preprocess('2 और 3 को जोड़ो', srcLang: 'hin_Deva', tgtLang: 'sat_Olck');
      expect(proc, contains('2'));
      expect(proc, contains('3'));
    });

    test('placeholder wrapping', () {
      final proc = tok.preprocess(
          'मेल करें team@flame.edu: 100.5% ३,५००',
          srcLang: 'hin_Deva',
          tgtLang: 'sat_Olck');
      expect(proc, contains('< ID1 >')); // email wrapped
      expect(proc, contains('< ID2 >')); // '100.5' (URL rule) wrapped
      expect(proc, contains('3,500')); // reference leaves this unwrapped
    });

    test('placeholder restore on contiguous markup', () {
      tok.preprocess(
          'मेल करें team@flame.edu: 100.5% ३,५००',
          srcLang: 'hin_Deva',
          tgtLang: 'sat_Olck');
      final restored = tok.postprocessDecoded('<ID1>+ <ID2> % 3,500', target: true);
      expect(restored, contains('team@flame.edu'));
      expect(restored, contains('100.5'));
    });

    test('max_length meta', () {
      expect(tok.meta.maxLength, 256);
      expect(tok.meta.srcDictSize, greaterThan(100000));
      expect(tok.meta.tgtDictSize, greaterThan(100000));
    });

    test('load idempotent', () async {
      await tok.load(); // should be a no-op
      expect(tok.isReady, isTrue);
    });
  });
}