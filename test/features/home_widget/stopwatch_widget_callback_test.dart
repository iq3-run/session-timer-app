import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/home_widget/home_widget_sync_service.dart';
import 'package:session_timer/features/home_widget/stopwatch_widget_callback.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fakes the `home_widget` plugin's own method channel (rather than
/// `HomeWidgetGateway`, which `stopwatchWidgetBackgroundCallback` has no way
/// to inject — it builds its own throwaway `ProviderContainer` with the
/// real provider tree, matching what actually runs in the background
/// isolate) so `saveWidgetData`/`getWidgetData`/`updateWidget` calls can be
/// observed without a real platform channel.
class _FakeHomeWidgetChannel {
  final saved = <String, Object?>{};
  final updatedAndroidNames = <String>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), (
          call,
        ) async {
          final args = (call.arguments as Map).cast<String, dynamic>();
          switch (call.method) {
            case 'saveWidgetData':
              saved[args['id'] as String] = args['data'];
              return true;
            case 'getWidgetData':
              return saved[args['id'] as String] ?? args['defaultValue'];
            case 'updateWidget':
              updatedAndroidNames.add(args['android'] as String);
              return true;
          }
          return null;
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeHomeWidgetChannel channel;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    channel = _FakeHomeWidgetChannel()..install();
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
      expect(channel.updatedAndroidNames, [stopwatchWidgetAndroidName]);
    },
  );

  test('a reset URI resets the stopwatch back to zero', () async {
    await stopwatchWidgetBackgroundCallback(
      Uri.parse('homewidget://stopwatch/toggle'),
    );

    await stopwatchWidgetBackgroundCallback(
      Uri.parse('homewidget://stopwatch/reset'),
    );

    expect(channel.saved[stopwatchAccumulatedMsKey], '0');
    expect(channel.saved[stopwatchRunningSinceEpochMsKey], isNull);
  });

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
      expect(channel.updatedAndroidNames, [stopwatchWidgetAndroidName]);
    },
  );

  test('a null URI is a no-op but still redraws the widget', () async {
    await stopwatchWidgetBackgroundCallback(null);

    expect(channel.saved[stopwatchRunningSinceEpochMsKey], isNull);
    expect(channel.updatedAndroidNames, [stopwatchWidgetAndroidName]);
  });
}
