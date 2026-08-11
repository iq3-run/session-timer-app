import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/session_schedule_entry_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpAndOpenScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  // Wide enough that the DataTable's columns (including the trailing
  // delete icon) all fit without needing a horizontal scroll to tap them.
  await tester.binding.setSurfaceSize(const Size(1000, 1400));
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
  });
}
