import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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

void main() {
  group('SessionScheduleScreen', () {
    testWidgets('entry button opens the read-only schedule table', (
      tester,
    ) async {
      await _pumpAndOpenScreen(tester);

      expect(find.text('セッションスケジュール'), findsOneWidget);
      expect(find.text('週末間'), findsOneWidget);
      expect(find.text('今日から'), findsOneWidget);
    });

    testWidgets('has no add form — registration moved to 日程設定', (
      tester,
    ) async {
      await _pumpAndOpenScreen(tester);

      expect(find.byKey(const Key('scheduleTypeDropdown')), findsNothing);
      expect(find.byKey(const Key('addScheduleEventButton')), findsNothing);
    });

    testWidgets('has no per-row delete button — moved to 日程設定', (
      tester,
    ) async {
      await _pumpAndOpenScreen(
        tester,
        initialValues: {
          sessionEventsJsonKey: jsonEncode([
            SessionEvent(
              id: 'we1',
              type: SessionEventType.weekend,
              date: DateTime(2026, 8, 21),
            ).toJson(),
          ]),
        },
      );

      expect(find.text('1WE'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('the settings button navigates to 日程設定', (tester) async {
      await _pumpAndOpenScreen(tester);

      await tester.tap(find.byKey(const Key('scheduleSettingsButton')));
      await tester.pumpAndSettle();

      expect(find.text('日程設定'), findsOneWidget);
      expect(find.byKey(const Key('scheduleTypeDropdown')), findsOneWidget);
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

  group('SessionScheduleScreen with A/B schedules', () {
    String eventsJson(List<SessionEvent> events) =>
        jsonEncode(events.map((e) => e.toJson()).toList());

    final events = [
      SessionEvent(
        id: 'or',
        type: SessionEventType.orientation,
        date: DateTime(2026, 8, 7),
      ),
      SessionEvent(
        id: 'weA',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 21),
        track: SessionTrack.a,
      ),
      SessionEvent(
        id: 'weB',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 28),
        track: SessionTrack.b,
      ),
      SessionEvent(
        id: 'wdA',
        type: SessionEventType.workday,
        date: DateTime(2026, 9, 5),
        track: SessionTrack.a,
      ),
      SessionEvent(
        id: 'wdB',
        type: SessionEventType.workday,
        date: DateTime(2026, 9, 12),
        track: SessionTrack.b,
      ),
      SessionEvent(
        id: 'we2',
        type: SessionEventType.weekend,
        date: DateTime(2026, 9, 26),
      ),
    ];

    testWidgets('shows A and B as separate labelled rows', (tester) async {
      await _pumpAndOpenScreen(
        tester,
        initialValues: {sessionEventsJsonKey: eventsJson(events)},
      );

      expect(find.text('1WE(A)'), findsOneWidget);
      expect(find.text('1WE(B)'), findsOneWidget);
      expect(find.text('1WD(A)'), findsOneWidget);
      expect(find.text('1WD(B)'), findsOneWidget);
      expect(find.text('2WE'), findsOneWidget);
    });

    testWidgets('the merge row lists each schedule on its own line', (
      tester,
    ) async {
      await _pumpAndOpenScreen(
        tester,
        initialValues: {sessionEventsJsonKey: eventsJson(events)},
      );

      expect(find.text('A:20日(3W)\nB:13日(2W)'), findsOneWidget);
    });
  });
}
