import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/session_plan/session_plan_controller.dart';
import 'package:session_timer/features/session_plan/session_plan_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _format = DateFormat('H:mm');

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: SessionTimerTheme.dark,
        home: const SessionPlanScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _rangeLabel(DateTime start, DateTime end) =>
    '${_format.format(start)}〜${_format.format(end)}';

String _entryJson(String id, DateTime start, DateTime end) =>
    '{"id":"$id",'
    '"startEpochMs":${start.millisecondsSinceEpoch},'
    '"endEpochMs":${end.millisecondsSinceEpoch}}';

void _seedSessions(List<String> entriesJson) {
  SharedPreferences.setMockInitialValues({
    sessionPlanJsonKey: '[${entriesJson.join(',')}]',
  });
}

void main() {
  group('SessionPlanScreen', () {
    testWidgets(
      'renders persisted sessions sorted by start time, regardless of the '
      'order they were persisted in',
      (tester) async {
        final laterStart = DateTime.now().add(const Duration(hours: 5));
        final laterEnd = laterStart.add(const Duration(hours: 1));
        final soonerStart = DateTime.now().add(const Duration(hours: 1));
        final soonerEnd = soonerStart.add(const Duration(hours: 1));
        _seedSessions([
          _entryJson('later', laterStart, laterEnd),
          _entryJson('sooner', soonerStart, soonerEnd),
        ]);

        await _pumpScreen(tester);

        final soonerY = tester
            .getTopLeft(find.text(_rangeLabel(soonerStart, soonerEnd)))
            .dy;
        final laterY = tester
            .getTopLeft(find.text(_rangeLabel(laterStart, laterEnd)))
            .dy;

        expect(soonerY, lessThan(laterY));
      },
    );

    testWidgets(
      "tapping a row's ✕ button deletes only that session, without also "
      "triggering the row's tap-to-edit gesture",
      (tester) async {
        final start = DateTime.now().add(const Duration(hours: 1));
        final end = start.add(const Duration(hours: 1));
        _seedSessions([_entryJson('s1', start, end)]);

        await _pumpScreen(tester);
        expect(find.text(_rangeLabel(start, end)), findsOneWidget);

        await tester.tap(find.byKey(const Key('removeSession_s1')));
        await tester.pumpAndSettle();

        expect(find.text(_rangeLabel(start, end)), findsNothing);
        expect(find.byType(TimePickerDialog), findsNothing);
      },
    );

    testWidgets(
      'tapping the row itself (not the ✕ button) still opens the edit '
      'time picker',
      (tester) async {
        final start = DateTime.now().add(const Duration(hours: 1));
        final end = start.add(const Duration(hours: 1));
        _seedSessions([_entryJson('s1', start, end)]);

        await _pumpScreen(tester);
        await tester.tap(find.text(_rangeLabel(start, end)));
        await tester.pumpAndSettle();

        expect(find.byType(TimePickerDialog), findsOneWidget);
      },
    );

    testWidgets(
      'deleting one of several sessions leaves the others, still sorted',
      (tester) async {
        final first = DateTime.now().add(const Duration(hours: 1));
        final second = DateTime.now().add(const Duration(hours: 2));
        final third = DateTime.now().add(const Duration(hours: 3));
        const duration = Duration(minutes: 30);
        final firstEnd = first.add(duration);
        final secondEnd = second.add(duration);
        final thirdEnd = third.add(duration);
        _seedSessions([
          _entryJson('a', first, firstEnd),
          _entryJson('b', second, secondEnd),
          _entryJson('c', third, thirdEnd),
        ]);

        await _pumpScreen(tester);
        expect(find.byIcon(Icons.close), findsNWidgets(3));

        // Delete the middle row specifically, not just "the first close
        // button", to prove deletion targets the tapped row's own id.
        await tester.tap(find.byKey(const Key('removeSession_b')));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.close), findsNWidgets(2));
        expect(find.text(_rangeLabel(second, secondEnd)), findsNothing);
        final firstY = tester
            .getTopLeft(find.text(_rangeLabel(first, firstEnd)))
            .dy;
        final thirdY = tester
            .getTopLeft(find.text(_rangeLabel(third, thirdEnd)))
            .dy;
        expect(firstY, lessThan(thirdY));
      },
    );
  });
}
