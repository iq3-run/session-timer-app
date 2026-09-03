import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';

/// A [Text] that stays readable if `FlashOverlay`'s background ever turns
/// the same color as this text — a black stroke is invisible against the
/// app's normal black background (no visual change day-to-day) but becomes
/// the only thing separating the glyphs from the background once it turns
/// amber.
class FlashLegibleText extends StatelessWidget {
  const FlashLegibleText(this.text, {required this.style, super.key});

  final String text;
  final TextStyle style;

  static const _strokeWidth = 3.0;

  @override
  Widget build(BuildContext context) {
    if (style.color != SessionTimerColors.amber) {
      return Text(text, style: style);
    }
    return Stack(
      children: [
        Text(
          text,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = _strokeWidth
              ..color = SessionTimerColors.background,
          ),
        ),
        Text(text, style: style),
      ],
    );
  }
}
