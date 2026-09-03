import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/flash/flash_legible_text.dart';

void main() {
  group('FlashLegibleText', () {
    testWidgets(
      'adds a black-stroke outline copy behind amber-colored text',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: FlashLegibleText(
              '12:34',
              style: TextStyle(color: SessionTimerColors.amber),
            ),
          ),
        );

        expect(find.text('12:34'), findsNWidgets(2));
        final texts = tester.widgetList<Text>(find.text('12:34')).toList();
        final stroked = texts.where(
          (t) => t.style?.foreground?.style == PaintingStyle.stroke,
        );
        expect(stroked, hasLength(1));
      },
    );

    testWidgets('renders a single plain Text for any other color', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlashLegibleText(
            '12:34',
            style: TextStyle(color: SessionTimerColors.red),
          ),
        ),
      );

      expect(find.text('12:34'), findsOneWidget);
      final text = tester.widget<Text>(find.text('12:34'));
      expect(text.style?.foreground, isNull);
    });
  });
}
