import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:session_timer/features/schedule/session_schedule_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpScreen(
  WidgetTester tester, {
  Map<String, Object> initialValues = const {},
  Size surfaceSize = const Size(1000, 1400),
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: SessionTimerTheme.dark,
        home: const SessionScheduleSettingsScreen(),
      ),
    ),
  );
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
  group('SessionScheduleSettingsScreen', () {
    testWidgets('the add button stays disabled until a date is picked', (
      tester,
    ) async {
      await _pumpScreen(tester);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('addScheduleEventButton')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'picking a date and adding creates a row labeled 1WE (the default '
      'type)',
      (tester) async {
        await _pumpScreen(tester);

        await _pickDateAndAdd(tester);

        expect(find.text('1WE'), findsOneWidget);
      },
    );

    testWidgets('deleting a row removes it from the list', (tester) async {
      await _pumpScreen(tester);
      await _pickDateAndAdd(tester);
      expect(find.text('1WE'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('1WE'), findsNothing);
    });

    testWidgets('shows every registered CR, not just today/next', (
      tester,
    ) async {
      final events = [
        SessionEvent(
          id: 'cr-past',
          type: SessionEventType.classroom,
          date: DateTime(2020),
        ),
        SessionEvent(
          id: 'cr-future',
          type: SessionEventType.classroom,
          date: DateTime(2030),
        ),
      ];
      await _pumpScreen(
        tester,
        initialValues: {
          sessionEventsJsonKey: jsonEncode(
            events.map((e) => e.toJson()).toList(),
          ),
        },
      );

      expect(find.text('CR'), findsNWidgets(2));
    });

    testWidgets(
      'a WD row has a visibility toggle, defaulting to on, absent for '
      '1WE/CS/CR',
      (tester) async {
        final events = [
          SessionEvent(
            id: 'we1',
            type: SessionEventType.weekend,
            date: DateTime(2026, 8, 21),
          ),
          SessionEvent(
            id: 'wd1',
            type: SessionEventType.workday,
            date: DateTime(2026, 9, 5),
          ),
          SessionEvent(
            id: 'cs',
            type: SessionEventType.completion,
            date: DateTime(2027, 6, 25),
          ),
          SessionEvent(
            id: 'cr',
            type: SessionEventType.classroom,
            date: DateTime(2026, 9, 18),
          ),
        ];
        await _pumpScreen(
          tester,
          initialValues: {
            sessionEventsJsonKey: jsonEncode(
              events.map((e) => e.toJson()).toList(),
            ),
          },
        );

        expect(
          tester
              .widget<Switch>(find.byKey(const Key('visibilityToggle_wd1')))
              .value,
          isTrue,
        );
        expect(find.byKey(const Key('visibilityToggle_we1')), findsNothing);
        expect(find.byKey(const Key('visibilityToggle_cs')), findsNothing);
        expect(find.byKey(const Key('visibilityToggle_cr')), findsNothing);
        expect(find.text('常に表示'), findsNWidgets(3));
      },
    );

    testWidgets('toggling a WD row off flips the switch to off', (
      tester,
    ) async {
      final events = [
        SessionEvent(
          id: 'wd1',
          type: SessionEventType.workday,
          date: DateTime(2026, 9, 5),
        ),
      ];
      await _pumpScreen(
        tester,
        initialValues: {
          sessionEventsJsonKey: jsonEncode(
            events.map((e) => e.toJson()).toList(),
          ),
        },
      );

      await tester.tap(find.byKey(const Key('visibilityToggle_wd1')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Switch>(find.byKey(const Key('visibilityToggle_wd1')))
            .value,
        isFalse,
      );
    });
  });
}
