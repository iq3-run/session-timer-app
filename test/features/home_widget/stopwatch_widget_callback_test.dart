import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/home_widget/home_widget_sync_service.dart';
import 'package:session_timer/features/home_widget/stopwatch_widget_callback.dart';
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
    'a toggle URI starts the stopwatch and pushes the new state to the '
    'widget',
    () async {
      await stopwatchWidgetBackgroundCallback(
        Uri.parse('homewidget://stopwatch/toggle'),
      );

      expect(channel.saved[stopwatchRunningSinceEpochMsKey], isNotNull);
      expect(channel.updatedAndroidNames, [
        stopwatchWidgetAndroidName,
        timerWidgetAndroidName,
        timerControlWidgetAndroidName,
      ]);
    },
  );

  test(
    'a reset URI resets the stopwatch back to zero and also pushes the '
    'linked timer reset to both timer widgets',
    () async {
      await stopwatchWidgetBackgroundCallback(
        Uri.parse('homewidget://stopwatch/toggle'),
      );

      await stopwatchWidgetBackgroundCallback(
        Uri.parse('homewidget://stopwatch/reset'),
      );

      expect(channel.saved[stopwatchAccumulatedMsKey], '0');
      expect(channel.saved[stopwatchRunningSinceEpochMsKey], isNull);
      expect(channel.updatedAndroidNames, [
        stopwatchWidgetAndroidName,
        timerWidgetAndroidName,
        timerControlWidgetAndroidName,
        stopwatchWidgetAndroidName,
        timerWidgetAndroidName,
        timerControlWidgetAndroidName,
      ]);
    },
  );

  test(
    "pushes the current ntpOffsetMs already stored in the widget's own "
    'data store, not a freshly-resolved (unsynced, always-zero) offset',
    () async {
      channel.saved[ntpOffsetMsKey] = '7';

      await stopwatchWidgetBackgroundCallback(
        Uri.parse('homewidget://stopwatch/toggle'),
      );

      expect(channel.saved[ntpOffsetMsKey], '7');
    },
  );

  test(
    'an unrecognized URI host is a no-op but still redraws the widget',
    () async {
      await stopwatchWidgetBackgroundCallback(
        Uri.parse('homewidget://stopwatch/unknown'),
      );

      expect(channel.saved[stopwatchRunningSinceEpochMsKey], isNull);
      expect(channel.updatedAndroidNames, [
        stopwatchWidgetAndroidName,
        timerWidgetAndroidName,
        timerControlWidgetAndroidName,
      ]);
    },
  );

  test('a null URI is a no-op but still redraws the widget', () async {
    await stopwatchWidgetBackgroundCallback(null);

    expect(channel.saved[stopwatchRunningSinceEpochMsKey], isNull);
    expect(channel.updatedAndroidNames, [
      stopwatchWidgetAndroidName,
      timerWidgetAndroidName,
      timerControlWidgetAndroidName,
    ]);
  });
}
