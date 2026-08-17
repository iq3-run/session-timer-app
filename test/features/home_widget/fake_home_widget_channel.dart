import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fakes the `home_widget` plugin's own method channel (rather than
/// `HomeWidgetGateway`, which the background-isolate callback functions have
/// no way to inject — each builds its own throwaway `ProviderContainer` with
/// the real provider tree, matching what actually runs in the background
/// isolate) so `saveWidgetData`/`getWidgetData`/`updateWidget` calls can be
/// observed without a real platform channel.
class FakeHomeWidgetChannel {
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
