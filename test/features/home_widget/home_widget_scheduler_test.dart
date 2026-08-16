import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/home_widget/home_widget_scheduler.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/stopwatch/stopwatch_state.dart';
import 'package:session_timer/features/timer/timer_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  testWidgets(
    'app resume reloads the stopwatch and timer controllers from disk, '
    'picking up a change the widget background isolate made while this '
    'app was backgrounded',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomeWidgetScheduler(child: SizedBox()),
          ),
        ),
      );
      await container.read(stopwatchControllerProvider.future);
      await container.read(timerControllerProvider.future);
      final targetEpochMs = DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch;

      // Written straight to the backing store, bypassing both
      // controllers' `_lastGood` caches — simulates a write that landed
      // on disk from the widget's background isolate while this app was
      // backgrounded (see stopwatch_widget_callback.dart).
      await SharedPreferencesStorePlatform.instance.setValue(
        'String',
        'flutter.$stopwatchStateJsonKey',
        jsonEncode(const StopwatchState(accumulatedMs: 9191).toJson()),
      );
      await SharedPreferencesStorePlatform.instance.setValue(
        'String',
        'flutter.$timerStateJsonKey',
        jsonEncode({'targetEpochMs': targetEpochMs, 'mode': 'normal'}),
      );

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pump();
      await tester.pump();

      final stopwatch = await container.read(
        stopwatchControllerProvider.future,
      );
      final timer = await container.read(timerControllerProvider.future);
      expect(stopwatch.accumulatedMs, 9191);
      expect(timer.targetEpochMs, targetEpochMs);
    },
  );
}
