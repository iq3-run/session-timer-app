import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/home_widget/home_widget_sync_service.dart';
import 'package:session_timer/features/home_widget/timer_widget_callback.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_home_widget_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHomeWidgetChannel channel;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    channel = FakeHomeWidgetChannel()..install();
  });

  tearDown(() => channel.uninstall());

  test(
    'a start URI starts a fresh 5-minute countdown and pushes both timer '
    'widgets and the stopwatch widget',
    () async {
      await timerWidgetBackgroundCallback(
        Uri.parse('homewidget://timer/start'),
      );

      expect(channel.saved[timerTargetEpochMsKey], isNotNull);
      // quickStart auto-starts the stopwatch if it wasn't already running.
      expect(channel.saved[stopwatchRunningSinceEpochMsKey], isNotNull);
      expect(channel.updatedAndroidNames, [
        timerWidgetAndroidName,
        timerControlWidgetAndroidName,
        stopwatchWidgetAndroidName,
      ]);
    },
  );

  test('an add30 URI starts a fresh 30-second countdown when idle', () async {
    await timerWidgetBackgroundCallback(Uri.parse('homewidget://timer/add30'));

    final targetEpochMs = int.parse(
      channel.saved[timerTargetEpochMsKey]! as String,
    );
    final remainingMs = targetEpochMs - DateTime.now().millisecondsSinceEpoch;
    expect(remainingMs, closeTo(30000, 2000));
  });

  test(
    'an add60 URI extends an already-running countdown by 1 minute',
    () async {
      await timerWidgetBackgroundCallback(
        Uri.parse('homewidget://timer/start'),
      );
      final startedTargetEpochMs = int.parse(
        channel.saved[timerTargetEpochMsKey]! as String,
      );

      await timerWidgetBackgroundCallback(
        Uri.parse('homewidget://timer/add60'),
      );

      final extendedTargetEpochMs = int.parse(
        channel.saved[timerTargetEpochMsKey]! as String,
      );
      expect(extendedTargetEpochMs - startedTargetEpochMs, 60000);
    },
  );

  test('a reset URI clears the timer back to unset', () async {
    await timerWidgetBackgroundCallback(Uri.parse('homewidget://timer/start'));

    await timerWidgetBackgroundCallback(Uri.parse('homewidget://timer/reset'));

    expect(channel.saved[timerTargetEpochMsKey], isNull);
  });

  test(
    "pushes the current ntpOffsetMs already stored in the widget's own "
    'data store, not a freshly-resolved (unsynced, always-zero) offset',
    () async {
      channel.saved[ntpOffsetMsKey] = '7';

      await timerWidgetBackgroundCallback(
        Uri.parse('homewidget://timer/start'),
      );

      expect(channel.saved[ntpOffsetMsKey], '7');
    },
  );

  test('a null URI is a no-op but still redraws every widget', () async {
    await timerWidgetBackgroundCallback(null);

    expect(channel.saved[timerTargetEpochMsKey], isNull);
    expect(channel.updatedAndroidNames, [
      timerWidgetAndroidName,
      timerControlWidgetAndroidName,
      stopwatchWidgetAndroidName,
    ]);
  });
}
