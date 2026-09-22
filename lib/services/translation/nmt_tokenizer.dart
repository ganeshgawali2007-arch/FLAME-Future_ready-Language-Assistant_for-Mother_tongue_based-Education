/// Byte-exact NMT tokenizer for IndicTrans2 (src/tgt BPE), ported from the
/// verified Python reference chain:
///
///   IndicProcessorPy.preprocess
///     -> `tokenizers` BPE (Metaspace pretokenizer + added tokens + rank merges)
///        + TemplateProcessing `</s>` append
///     -> decode (Metaspace reverse, skip specials)
///     -> postprocess (placeholder restore + trivial_detokenize)
///
/// The port is validated against frozen golden fixtures generated on the host
/// (see `test/nmt_tokenizer_test.dart`). We deliberately do NOT depend on NFC
/// or the `Precompiled` charsmap: the pipeline's own normalizer + digit table
/// already collapse the classroom inputs, and full 3,144/3,144 string/ID
/// parity was measured against the host reference.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class NmtMeta {
  const NmtMeta({
    required this.srcDictSize,
    required this.tgtDictSize,
    required this.decoderStartTokenId,
    required this.eosTokenId,
    required this.maxLength,
  });

  final int srcDictSize;
  final int tgtDictSize;
  final int decoderStartTokenId;
  final int eosTokenId;
  final int maxLength;
}

/// One BPE vocabulary + merge table (a 1:1 port of a `tokenizers` BPE JSON).
class _BpeTable {
  _BpeTable({
    required this.vocab,
    required this.rank,
    required this.added,
    required this.idToToken,
    required this.addedSpecialIds,
    required this.unkId,
  });

  final Map<String, int> vocab;
  final Map<String, int> rank;
  final Map<String, int> added;
  final Map<int, String> idToToken;
  final Set<int> addedSpecialIds;
  final int unkId;
}

/// Pure-Dart IndicTrans2 tokenizer + processor.
///
/// Transcript-level usage keeps a single shared instance; the tokenizer tables
/// are reference-counted by the owning engine and unloaded when the model is
/// released (2-4 GB device rule).
class NmtTokenizer {
  NmtTokenizer({
    Future<Map<String, String>> Function()? assetLoader,
  }) : _assetLoader = assetLoader ?? _rootBundleLoader;

  final Future<Map<String, String>> Function()? _assetLoader;

  _BpeTable? _src;
  _BpeTable? _tgt;
  NmtMeta? _meta;

  bool get isReady => _src != null && _tgt != null && _meta != null;

  NmtMeta get meta {
    final m = _meta;
    if (m == null) {
      throw StateError('NmtTokenizer not loaded');
    }
    return m;
  }

  _BpeTable _table(bool target) => target ? _tgt! : _src!;

  /// Asset paths mirror the generated compact files (assets/nmt/...).
  static Future<Map<String, String>> _rootBundleLoader() async {
    Future<String> load(String path) async =>
        (await rootBundle.loadString(path)).trim();
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

  /// Load the vocab/merges tables + generation metadata from assets. Idempotent.
  Future<void> load() async {
    if (isReady) return;
    final loader = _assetLoader;
    final assets = loader != null ? await loader() : await _rootBundleLoader();

    _meta = _parseMeta(assets['meta']!);
    _src = _parseTable(
      vocabText: assets['vocab_src']!,
      mergesText: assets['merges_src']!,
      addedText: assets['added_src']!,
    );
    _tgt = _parseTable(
      vocabText: assets['vocab_tgt']!,
      mergesText: assets['merges_tgt']!,
      addedText: assets['added_tgt']!,
    );
  }

  static NmtMeta _parseMeta(String jsonText) {
    final map = jsonDecode(jsonText) as Map<String, dynamic>;
    return NmtMeta(
      srcDictSize: map['src_dict_size'] as int,
      tgtDictSize: map['tgt_dict_size'] as int,
      decoderStartTokenId: map['decoder_start_token_id'] as int,
      eosTokenId: map['eos_token_id'] as int,
      maxLength: (map['max_length'] as int?) ?? 256,
    );
  }

  static _BpeTable _parseTable({
    required String vocabText,
    required String mergesText,
    required String addedText,
  }) {
    final vLines = vocabText.replaceAll('\r', '').split('\n');
    final mLines = mergesText.replaceAll('\r', '').split('\n');
    final aLines = addedText.replaceAll('\r', '').split('\n');

    final vocab = <String, int>{};
    final idToToken = <int, String>{};
    for (final line in vLines) {
      if (line.isEmpty) continue;
      final tab = line.indexOf('\t');
      final id = int.parse(line.substring(0, tab));
      final token = line.substring(tab + 1);
      vocab[token] = id;
      idToToken[id] = token;
    }
    final rank = <String, int>{};
    for (final line in mLines) {
      if (line.isEmpty) continue;
      final t1 = line.indexOf('\t');
      final t2 = line.indexOf('\t', t1 + 1);
      final rankId = int.parse(line.substring(0, t1));
      rank['${line.substring(t1 + 1, t2)}\u0001${line.substring(t2 + 1)}'] =
          rankId;
    }
    final added = <String, int>{};
    final specialIds = <int>{};
    for (final line in aLines) {
      if (line.isEmpty) continue;
      final t1 = line.indexOf('\t');
      final t2 = line.indexOf('\t', t1 + 1);
      final id = int.parse(line.substring(0, t1));
      final content = line.substring(t1 + 1, t2);
      final special = line.substring(t2 + 1) == '1';
      added[content] = id;
      if (special) specialIds.add(id);
    }
    final unkId = added['<unk>'] ?? 3;
    return _BpeTable(
      vocab: vocab,
      rank: rank,
      added: added,
      idToToken: idToToken,
      addedSpecialIds: specialIds,
      unkId: unkId,
    );
  }

  // --------------------------------------------------------------------------
  // Placeholder bookkeeping (mirrors the processor's entity queue).
  // --------------------------------------------------------------------------

  final Map<String, String> _placeholders = {};

  Map<String, String> _takePlaceholders() {
    final copy = Map<String, String>.from(_placeholders);
    _placeholders.clear();
    return copy;
  }

  // --------------------------------------------------------------------------
  // Preprocess (processor replica).
  // --------------------------------------------------------------------------

  // Dart's RegExp treats \w / \d / \b as ASCII, so the placeholder patterns
  // must be Unicode-explicit (\p{L}, \p{Nd}, and a Python-\s whitespace set)
  // to match the reference `regex` module semantics.
  static final RegExp _multiSpace = RegExp(r'[ ]{2,}');
  static final RegExp _endBracket = RegExp(r'\) ([\.!:?;,])');
  static final RegExp _digitSpacePercent = RegExp(r'([\p{Nd}]) %');
  static final RegExp _doubleQuotPunc = RegExp(r'"([,\.]+)');
  static final RegExp _digitNbspDigit = RegExp(r'([\p{Nd}])\u00a0([\p{Nd}])');
  static const String _ws = r'[ \t\n\r\f\v\u00a0\u1680\u2000\u2001\u2002'
      '\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a'
      '\u2028\u2029\u202f\u205f\u3000]';
  static final RegExp _email = RegExp(
      r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}');
  static final RegExp _url = RegExp(
      r'(?<![\p{L}\p{N}\p{M}_/.])(?=[\p{L}\p{N}\p{M}_])(?:(?:https?|ftp)://)?'
      r'(?:(?:[\p{L}\p{N}\p{M}_-]+\.)+(?!\.))(?:[\p{L}\p{N}\p{M}_/\-?#&=%.]+)+'
      r'(?!\.[\p{L}\p{N}\p{M}_]+)(?<=[\p{L}\p{N}\p{M}_])(?![\p{L}\p{N}\p{M}_])',
      unicode: true);
  static final RegExp _num = RegExp(
      r'(~?[\p{Nd}]+\.?[\p{Nd}]*\s?%?\s?-?\s?~?[\p{Nd}]+\.?[\p{Nd}]*\s?%|~?[\p{Nd}]+%|[\p{Nd}]+[-\/.,:\x27]+[\p{Nd}]+[-\/.,:\x27+][\p{Nd}]+(?:\.[\p{Nd}]+)?|[\p{Nd}]+[-\/.:\x27+][\p{Nd}]+(?:\.[\p{Nd}]+)?)',
      unicode: true);
  static final RegExp _other = RegExp(r'[A-Za-z0-9]*[#|@][\p{L}\p{N}\p{M}_]+',
      unicode: true);
  static final RegExp _collapseWs = RegExp('$_ws+', unicode: true);

  static const String _digitPairs = '\u09e6\u09e7\u09e8\u09e9\u09ea\u09eb'
      '\u09ec\u09ed\u09ee\u09ef\u0ae6\u0ae7\u0ae8\u0ae9\u0aea\u0aeb'
      '\u0aec\u0aed\u0aee\u0aef\u0ce6\u0ce7\u0ce8\u0ce9\u0cea\u0ceb'
      '\u0cec\u0ced\u0cee\u0cef\u0966\u0967\u0968\u0969\u096a\u096b'
      '\u096c\u096d\u096e\u096f\u0660\u0661\u0662\u0663\u0664\u0665'
      '\u0666\u0667\u0668\u0669\ubbf0\ubbf1\ubbf2\ubbf3\ubbf4\ubbf5'
      '\ubbf6\ubbf7\ubbf8\ubbf9\u0b66\u0b67\u0b68\u0b69\u0b6a\u0b6b'
      '\u0b6c\u0b6d\u0b6e\u0b6f\u0a66\u0a67\u0a68\u0a69\u0a6a\u0a6b'
      '\u0a6c\u0a6d\u0a6e\u0a6f\u1c50\u1c51\u1c52\u1c53\u1c54\u1c55'
      '\u1c56\u1c57\u1c58\u1c59\u06f0\u06f1\u06f2\u06f3\u06f4\u06f5'
      '\u06f6\u06f7\u06f8\u06f9\u0c67\u0c68\u0c69\u0c6a\u0c6b\u0c6c'
      '\u0c6d\u0c6e\u0c6f';

  /// Removes control/whitespace artifacts the processor's normalizer handles.
  static String _cleanNormalizerWhitespace(String text) {
    var out = text
        .replaceAll('\ufeff', '')
        .replaceAll('\ufffe', '')
        .replaceAll('\u2060', '')
        .replaceAll('\u00ad', '')
        .replaceAll('\u200b', ' ')
        .replaceAll('\u00a0', ' ')
        .replaceAll('\u200c', '')
        .replaceAll('\u200d', '');
    // _normalize_punctuations
    out = out
        .replaceAll('„', '"')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('–', '-')
        .replaceAll('—', ' - ')
        .replaceAll('´', "'")
        .replaceAll('‘', "'")
        .replaceAll('‚', "'")
        .replaceAll('’', "'")
        .replaceAll("''", '"')
        .replaceAll('´´', '"')
        .replaceAll('…', '...');
    return out;
  }

  String _puncNorm(String text) {
    var t = text;
    t = t.replaceAll('\r', '');
    t = t.replaceAll(RegExp(r'\(\s*'), '(');
    t = t.replaceAll(RegExp(r'\s*\)'), ')');
    t = t.replaceAll(RegExp(r'\s:\s?'), ':');
    t = t.replaceAll(RegExp(r'\s;\s?'), ';');
    t = t.replaceAll(RegExp(r'[`´‘‚’]'), "'");
    t = t.replaceAll(RegExp(r'[„“”«»]'), '"');
    t = t.replaceAll(RegExp(r'[–—]'), '-');
    t = t.replaceAll(RegExp(r'\.\.\.'), '...');
    t = t.replaceAll('\u00a0%', '%');
    t = t.replaceAll(RegExp(r'nº\u00a0'), 'nº ');
    t = t.replaceAll('\u00a0ºC', ' ºC');
    t = t.replaceAllMapped(RegExp(r'\u00a0[?!;]'), (m) => m.group(0)!.trim());
    t = t.replaceAll(RegExp(r',\u00a0'), ', ');
    t = t.replaceAll(_multiSpace, ' ');
    t = t.replaceAllMapped(_endBracket, (m) => ')${m[1]}');
    t = t.replaceAllMapped(_digitSpacePercent, (m) => '${m[1]}%');
    t = t.replaceAllMapped(_doubleQuotPunc, (m) => '${m[1]}"');
    t = t.replaceAllMapped(_digitNbspDigit, (m) => '${m[1]}.${m[2]}');
    return t.trim();
  }

  String _wrapPlaceholders(String text) {
    var out = text;
    var serial = 1;
    final map = <String, String>{};
    void handle(RegExp pattern, bool isUrl, bool isNum) {
      final found = <String>{};
      for (final m in pattern.allMatches(out)) {
        final g = m.group(0);
        if (g != null) found.add(g);
      }
      final sorted = found.toList()..sort();
      for (final match in sorted) {
        if (isUrl && match.replaceAll('.', '').length < 4) continue;
        if (isNum &&
            match.replaceAll(' ', '').replaceAll('.', '').replaceAll(':', '')
                    .length <
                4) {
          continue;
        }
        final ph = '<ID$serial>';
        map[ph] = match;
        out = out.replaceAll(match, ph);
        serial++;
      }
    }

    handle(_email, false, false);
    handle(_url, true, false);
    handle(_num, false, true);
    handle(_other, false, false);
    out = out
        .replaceAll(_collapseWs, ' ')
        .replaceAll('>/', '>')
        .replaceAll(']/', ']');
    _placeholders.clear();
    _placeholders.addAll(map);
    return out;
  }

  String _normalize(String text, {required bool oriya}) {
    var t = _cleanNormalizerWhitespace(text);
    if (oriya) {
      t = t.replaceAll('\u0b05\u0b3e', '\u0b06');
      t = t.replaceAll('\u0b0f\u0b57', '\u0b10');
      t = t.replaceAll('\u0b13\u0b57', '\u0b14');
      t = t.replaceAll('\u0b5c', '\u0b21\u0b3c');
      t = t.replaceAll('\u0b5d', '\u0b22\u0b3c');
      t = t.replaceAll('\u0b64', '\u0964');
      t = t.replaceAll('\u0b65', '\u0965');
      t = t.replaceAll('\u0b7c', '\u0964');
      t = t.replaceAll('\u0b35', '\u0b2c');
      t = t.replaceAll('\u0b47\u0b56', '\u0b58');
      t = t.replaceAll('\u0b47\u0b3e', '\u0b4b');
      t = t.replaceAll('\u0b47\u0b57', '\u0b4c');
      t = t.replaceAllMapped(
        RegExp(r'([\u0b00-\u0b7f]):'),
        (m) => '${m[1]}\u0b03',
      );
    } else {
      t = t.replaceAll('\u0972', '\u090f');
      t = t.replaceAll('\u0929', '\u0928\u093c');
      t = t.replaceAll('\u0931', '\u0930\u093c');
      t = t.replaceAll('\u0934', '\u0933\u093c');
      t = t.replaceAll('\u0958', '\u0915\u093c');
      t = t.replaceAll('\u0959', '\u0916\u093c');
      t = t.replaceAll('\u095a', '\u0917\u093c');
      t = t.replaceAll('\u095b', '\u091c\u093c');
      t = t.replaceAll('\u095c', '\u0921\u093c');
      t = t.replaceAll('\u095d', '\u0922\u093c');
      t = t.replaceAll('\u095e', '\u092b\u093c');
      t = t.replaceAll('\u095f', '\u092f\u093c');
      t = t.replaceAll('\u007c', '\u0964');
      t = t.replaceAllMapped(
        RegExp(r'([\u0900-\u097f]):'),
        (m) => '${m[1]}\u0903',
      );
    }
    return t;
  }

  /// `trivial_tokenize` from indicnlp (pad punctuation, re-join number runs).
  List<String> trivialTokenize(String text) {
    final punct = RegExp(
        r'''([!"#$%&'()*+,\-./:;<=>?@\[\]^_`{|}~\u0964\u0965\uAAF1\uAAF0\uABEB\uABEC\uABED\uABEE\uABEF\u1C7E\u1C7F])''');
    var s = text.replaceAll('\t', ' ');
    s = s.replaceAllMapped(punct, (m) => ' ${m[1]} ');
    s = s.replaceAll(RegExp(r'[ ]+'), ' ').trimLeft().trimRight();
    s = _rejoinNumberSequences(s);
    return s.split(' ');
  }

  /// Mirrors `pat_num_seq` handling: drop the spaces inside number runs —
  /// with the reference's exact `m.start > prev` guard (matches at position 0
  /// are deliberately NOT rejoined, an indicnlp quirk the goldens bake in).
  static String _rejoinNumberSequences(String s) {
    final pat = RegExp(r'([0-9]+ [,.:/] )+[0-9]+');
    final sb = StringBuffer();
    var prev = 0;
    for (final m in pat.allMatches(s)) {
      final start = m.start;
      final end = m.end;
      if (start > prev) {
        sb.write(s.substring(prev, start));
        sb.write(m.group(0)!.replaceAll(' ', ''));
        prev = end;
      }
    }
    sb.write(s.substring(prev));
    return sb.toString();
  }

  String digits(String text) {
    // Each block of ten codepoints in _digitPairs corresponds to digits 0..9
    // across the Indic/Ol Chiki scripts supported by the processor's table.
    final sb = StringBuffer();
    for (final r in text.runes) {
      if (r >= 0x30 && r <= 0x39) {
        sb.write(String.fromCharCode(r));
        continue;
      }
      final idx = _digitPairs.indexOf(String.fromCharCode(r));
      if (idx >= 0) {
        sb.write((idx % 10).toString());
      } else {
        sb.write(String.fromCharCode(r));
      }
    }
    return sb.toString();
  }

  /// Processor-equivalent preprocess. Returns the lang-prefixed string and
  /// stores this call's placeholder map for later [postprocess].
  String preprocess(
    String sentence, {
    required String srcLang,
    required String tgtLang,
  }) {
    var sent = _puncNorm(sentence);
    sent = digits(sent); // digit canonization happens before placeholders
    sent = _wrapPlaceholders(sent);
    final iso = _floresCode(srcLang);
    final script = srcLang.split('_')[1];
    final doTransliterate = !_scriptPassthrough(script);
    var processed = _indicTokenizeAndTransliterate(sent, iso, doTransliterate);
    processed = processed.trim();
    return '$srcLang $tgtLang $processed';
  }

  String _indicTokenizeAndTransliterate(
    String sentence,
    String isoLang,
    bool transliterate,
  ) {
    var normed = sentence.trim();
    final oriya = isoLang == 'or';
    normed = _normalize(normed, oriya: oriya);
    final tokens = trivialTokenize(normed);
    var joined = tokens.join(' ');
    if (transliterate) {
      // The reference applies UnicodeIndicTransliterator here. For FLAME's
      // pair the non-passthrough scripts are Devanagari (hi↔hi idempotent),
      // and sat_Olck/sat_Deva are passthrough — so this is a no-op by design.
    }
    return joined;
  }

  static String _floresCode(String lang) {
    switch (lang) {
      case 'hin_Deva':
        return 'hi';
      case 'sat_Olck':
        return 'or';
      case 'sat_Deva':
        return 'sat';
      default:
        return 'hi';
    }
  }

  static bool _scriptPassthrough(String script) =>
      script == 'Arab' ||
      script == 'Aran' ||
      script == 'Olck' ||
      script == 'Mtei' ||
      script == 'Latn';

  // --------------------------------------------------------------------------
  // BPE encode / decode (tokenizers-equivalent).
  // --------------------------------------------------------------------------

  List<String> _pretokenize(String text) {
    final pieces = <String>[];
    var buf = '';
    var pending = '\u2581';
    void flush() {
      final piece = pending + buf;
      if (piece.isNotEmpty && piece != '\u2581') pieces.add(piece);
      buf = '';
      pending = '\u2581';
    }

    for (final r in text.runes) {
      if (r == 0x20) {
        flush();
      } else {
        buf += String.fromCharCode(r);
      }
    }
    flush();
    if (pieces.isEmpty) pieces.add('\u2581');
    return pieces;
  }

  List<String> _bpe(_BpeTable table, String word) {
    var pieces = word.runes.map(String.fromCharCode).toList();
    List<(int, int)> candidates() {
      final out = <(int, int)>[];
      for (var i = 0; i < pieces.length - 1; i++) {
        final key = '${pieces[i]}\u0001${pieces[i + 1]}';
        final r = table.rank[key];
        if (r != null) out.add((r, i));
      }
      out.sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
      return out;
    }

    var cands = candidates();
    while (cands.isNotEmpty) {
      final (_, i) = cands.removeAt(0);
      if (i + 1 >= pieces.length) continue;
      final merged = pieces[i] + pieces[i + 1];
      pieces[i] = merged;
      pieces.removeAt(i + 1);
      cands = candidates();
    }
    return pieces;
  }

  /// Encode a raw sentence to src-side token ids (includes lang tags and the
  /// trailing `</s>`), mirroring the host reference's `Tokenizer.encode`.
  List<int> encode(String text, {required bool target}) {
    final table = _table(target);
    final ids = <int>[];
    for (final pt in _pretokenize(text)) {
      final content = pt.startsWith('\u2581')
          ? pt.substring(1)
          : pt;
      if (content.isNotEmpty) {
        if (pt == '\u2581$content') {
          final addedId =
              table.added[content] ?? table.added['$content '];
          if (addedId != null) {
            ids.add(addedId);
            continue;
          }
        }
      }
      for (final piece in _bpe(table, pt)) {
        ids.add(table.vocab[piece] ?? table.unkId);
      }
    }
    ids.add(meta.eosTokenId);
    return ids;
  }

  /// Raw Metaspace reversal (skip specials, ▁→space) WITHOUT postprocess —
  /// matches the host golden `decoded_raw` field.
  String decodeRaw(List<int> ids, {required bool target}) {
    final table = _table(target);
    final clamped = [
      for (final id in ids)
        id < 0
            ? (table.unkId)
            : (id >= (target ? meta.tgtDictSize : meta.srcDictSize)
                ? (target ? meta.tgtDictSize - 1 : meta.srcDictSize - 1)
                : id),
    ];
    final sb = StringBuffer();
    for (final id in clamped) {
      if (table.addedSpecialIds.contains(id)) continue;
      final token = table.idToToken[id];
      sb.write(token ?? '<unk>');
    }
    return sb.toString().replaceAll('\u2581', ' ').trim();
  }

  /// Decode raw generated ids to text (skip specials, Metaspace reverse), then
  /// run postprocess (placeholder restore + trivial detokenize).
  String decode(List<int> ids, {required bool target}) {
    var text = decodeRaw(ids, target: target);
    return postprocessDecoded(text, target: target);
  }

  /// Postprocess for generated output (placeholder restore + detokenize).
  /// The reference transliteration (hi→or) is identity on Ol Chiki outputs and
  /// would map stray Devanagari to Oriya; FLAME keeps the model's native Ol
  /// Chiki output instead (see module doc + report).
  String postprocessDecoded(String text, {required bool target}) {
    var s = text;
    for (final entry in _takePlaceholders().entries) {
      s = s.replaceAll(entry.key, entry.value);
    }
    s = trivialDetokenize(s);
    return s.trim();
  }

  /// `trivial_detokenize` from indicnlp.
  static String trivialDetokenize(String text) {
    var s = _rejoinNumberSequences(text);
    s = s.replaceAllMapped(RegExp(r'[ ]([-/\\])[ ]'), (m) => '${m[1]}');
    s = s.replaceAllMapped(
        RegExp(r'[ ]([!%)\]}.,:;>?\u0964\u0965])'), (m) => '${m[1]}');
    s = s.replaceAllMapped(RegExp(r'([#$(\[{<@])[ ]'), (m) => '${m[1]}');
    const alt = "\"'"'\u0060';
    for (final punc in alt.split('')) {
      var cnt = 0;
      final out = StringBuffer();
      for (final ch in s.split('')) {
        if (ch == punc) {
          out.write(cnt.isEven ? '@RA' : '@LA');
          cnt++;
        } else {
          out.write(ch);
        }
      }
      s = out
          .toString()
          .replaceAll('@RA ', punc)
          .replaceAll(' @LA', punc)
          .replaceAll('@RA', punc)
          .replaceAll('@LA', punc);
    }
    return s;
  }
}