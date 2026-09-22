/// Text normalisation + language heuristics shared by the education engine,
/// the phrase cache, and the translation engine.
library;

class FlmText {
  FlmText._();

  static String normalize(String input) {
    final lower = input.trim().toLowerCase();
    // Collapse repeated whitespace/punct variance and drop trailing '?', '।'.
    final withoutPunct = lower.replaceAll(RegExp(r'[?।!]+$'), '');
    final collapsed = withoutPunct.replaceAll(RegExp(r'\s+'), ' ');
    return collapsed.trim();
  }

  static List<String> tokens(String input) {
    final out = <String>[];
    final buf = StringBuffer();
    for (final ch in input.toLowerCase().split('')) {
      final code = ch.codeUnitAt(0);
      final isDev = code >= 0x0900 && code <= 0x097F;
      final isOl = code >= 0x1C50 && code <= 0x1CFF;
      final isLatin = (code >= 0x61 && code <= 0x7A) ||
          (code >= 0x30 && code <= 0x39);
      final isDanda = code == 0x0964 || code == 0x0965;
      if ((isDev || isOl || isLatin) && !isDanda) {
        buf.write(ch);
      } else {
        if (buf.isNotEmpty) {
          out.add(buf.toString());
          buf.clear();
        }
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  static bool looksLikeHindi(String input) {
    for (final c in input.runes) {
      if (c >= 0x0900 && c <= 0x097F) return true;
    }
    return false;
  }
}