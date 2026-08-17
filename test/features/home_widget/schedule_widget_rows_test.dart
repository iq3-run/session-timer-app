import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/features/home_widget/schedule_widget_rows.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('scheduleWidgetTodayProvider', () {
    testWidgets(
      'only changes value when the calendar day changes, not on every '
      'same-day tick',
      (tester) async {
        final clock = StreamController<DateTime>();
        addTearDown(clock.close);
        final container = ProviderContainer(
          overrides: [nowProvider.overrideWith((ref) => clock.stream)],
        );
        addTearDown(container.dispose);

        final values = <DateTime>[];
        final sub = container.listen(
          scheduleWidgetTodayProvider,
          (previous, next) => values.add(next),
        );
        addTearDown(sub.close);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const SizedBox(),
          ),
        );

        clock.add(DateTime(2099, 1, 5, 9));
        await tester.pump();
        clock.add(DateTime(2099, 1, 5, 23, 59));
        await tester.pump();
        clock.add(DateTime(2099, 1, 6));
        await tester.pump();

        expect(values, [DateTime(2099, 1, 5), DateTime(2099, 1, 6)]);
      },
    );
  });

  group('scheduleWidgetRowsProvider', () {
    test('mirrors buildScheduleRows for the persisted events', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionEventControllerProvider.future);

      await container
          .read(sessionEventControllerProvider.notifier)
          .addEvent(SessionEventType.orientation, DateTime(2026, 8, 10));
      await container
          .read(sessionEventControllerProvider.notifier)
          .addEvent(SessionEventType.weekend, DateTime(2026, 8, 21));

      final rows = container.read(scheduleWidgetRowsProvider);

      expect(rows.map((r) => r.label), containsAll(['OR', '1WE']));
    });

    test('recomputes when the persisted event list changes', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionEventControllerProvider.future);

      expect(
        container.read(scheduleWidgetRowsProvider).any((r) => r.label == 'CS'),
        isFalse,
      );

      await container
          .read(sessionEventControllerProvider.notifier)
          .addEvent(SessionEventType.completion, DateTime(2026, 9, 2));

      expect(
        container.read(scheduleWidgetRowsProvider).any((r) => r.label == 'CS'),
        isTrue,
      );
    });
  });
}
