import 'package:flutter/material.dart';

/// Renders text in the bundled Ol Chiki font (Noto Sans Ol Chiki, OFL).
///
/// Guarantees correct rendering of Santhali's Ol Chiki script
/// (U+1C50–U+1C7F) without depending on Android system fallback fonts.
/// Non-Ol-Chiki text still renders via normal fallback.
class SanathaliText extends StatelessWidget {
  const SanathaliText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: (style ?? const TextStyle())
          .copyWith(fontFamily: 'NotoSansOlChiki'),
    );
  }
}