import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/home_widget/home_widget_background_callback.dart';
import 'package:session_timer/features/home_widget/home_widget_sync_service.dart';
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
    'a "stopwatch" host URI is dispatched to the stopwatch handler',
    () async {
      await homeWidgetBackgroundCallback(
        Uri.parse('homewidget://stopwatch/toggle'),
      );

      expect(channel.saved[stopwatchRunningSinceEpochMsKey], isNotNull);
    },
  );

  test('a "timer" host URI is dispatched to the timer handler', () async {
    await homeWidgetBackgroundCallback(Uri.parse('homewidget://timer/start'));

    expect(channel.saved[timerTargetEpochMsKey], isNotNull);
  });

  test('an unrecognized host is a no-op', () async {
    await homeWidgetBackgroundCallback(
      Uri.parse('homewidget://unknown/toggle'),
    );

    expect(channel.saved, isEmpty);
    expect(channel.updatedAndroidNames, isEmpty);
  });

  test('a null URI is a no-op', () async {
    await homeWidgetBackgroundCallback(null);

    expect(channel.saved, isEmpty);
    expect(channel.updatedAndroidNames, isEmpty);
  });
}
