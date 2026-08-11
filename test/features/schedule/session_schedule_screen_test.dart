import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:session_timer/features/schedule/session_schedule_entry_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpAndOpenScreen(
  WidgetTester tester, {
  Map<String, Object> initialValues = const {},
  Size surfaceSize = const Size(1000, 1400),
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  // Wide enough that the DataTable's columns (including the trailing
  // delete icon) all fit without needing a horizontal scroll to tap them.
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: SessionTimerTheme.dark,
        home: const Scaffold(body: SessionScheduleEntryButton()),
      ),
    ),
  );
  await tester.tap(find.byIcon(Icons.event_note_outlined));
  await tester.pumpAndSettle();
}

Future<void> _pickDateAndAdd(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('scheduleDateButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('addScheduleEventButton')));
  await tester.pumpAndSettle();
}

void main() {
  group('SessionScheduleScreen', () {
    testWidgets('entry button opens the schedule screen', (tester) async {
      await _pumpAndOpenScreen(tester);

      expect(find.text('セッションスケジュール'), findsOneWidget);
      expect(find.text('週末間'), findsOneWidget);
      expect(find.text('今日から'), findsOneWidget);
    });

    testWidgets('the add button stays disabled until a date is picked', (
      tester,
    ) async {
      await _pumpAndOpenScreen(tester);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('addScheduleEventButton')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'picking a date and adding creates a row labeled 1WE (the default '
      'type)',
      (tester) async {
        await _pumpAndOpenScreen(tester);

        await _pickDateAndAdd(tester);

        expect(find.text('1WE'), findsOneWidget);
      },
    );

    testWidgets('deleting a row removes it from the table', (tester) async {
      await _pumpAndOpenScreen(tester);
      await _pickDateAndAdd(tester);
      expect(find.text('1WE'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('1WE'), findsNothing);
    });

    testWidgets(
      'the table scrolls vertically to reach rows past the viewport',
      (tester) async {
        // A short viewport with 30 rows guarantees the last one starts
        // off-screen regardless of DataTable's exact row height.
        final events = [
          for (var i = 0; i < 30; i++)
            SessionEvent(
              id: 'wd$i',
              type: SessionEventType.workday,
              date: DateTime(2026).add(Duration(days: i)),
            ),
        ];
        await _pumpAndOpenScreen(
          tester,
          initialValues: {
            sessionEventsJsonKey: jsonEncode(
              events.map((e) => e.toJson()).toList(),
            ),
          },
          surfaceSize: const Size(1000, 500),
        );
        // DataTable isn't lazy — every row is already in the widget tree
        // regardless of scroll position, so `findsOneWidget` alone
        // wouldn't catch a regression back to the single-axis scroll
        // view. What actually matters is *where* the row is painted.
        final beforeY = tester.getTopLeft(find.text('30WD')).dy;
        expect(beforeY, greaterThanOrEqualTo(500));

        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -5000),
        );
        await tester.pumpAndSettle();

        final afterY = tester.getTopLeft(find.text('30WD')).dy;
        expect(afterY, lessThan(500));
      },
    );
  });
}
