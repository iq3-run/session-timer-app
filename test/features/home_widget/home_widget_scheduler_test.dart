import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/home_widget/home_widget_gateway.dart';
import 'package:session_timer/features/home_widget/home_widget_scheduler.dart';
import 'package:session_timer/features/home_widget/home_widget_sync_service.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/stopwatch/stopwatch_state.dart';
import 'package:session_timer/features/timer/timer_controller.dart';
import 'package:session_timer/features/timer/timer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _RecordingHomeWidgetGateway implements HomeWidgetGateway {
  final updatedAndroidNames = <String>[];

  @override
  Future<void> saveWidgetData(String key, Object? value) async {}

  @override
  Future<void> updateWidget({required String androidName}) async {
    updatedAndroidNames.add(androidName);
  }

  @override
  Future<String?> getWidgetData(String key) async => null;
}

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

  testWidgets(
    'a timer state change syncs the timer widget',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final gateway = _RecordingHomeWidgetGateway();
      final container = ProviderContainer(
        overrides: [homeWidgetGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomeWidgetScheduler(child: SizedBox()),
          ),
        ),
      );
      await container.read(timerControllerProvider.future);
      gateway.updatedAndroidNames.clear();

      await container
          .read(timerControllerProvider.notifier)
          .start(TimerMode.normal, const Duration(minutes: 5));
      await tester.pump();

      expect(gateway.updatedAndroidNames, contains(timerWidgetAndroidName));
    },
  );
}
