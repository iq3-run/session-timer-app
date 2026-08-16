import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

/// Thin wrapper around the `home_widget` plugin's static methods, mirroring
/// why `NotificationService` takes an injected
/// `FlutterLocalNotificationsPlugin` — `home_widget`'s API is a set of
/// static calls into a platform channel, which can't be faked directly in a
/// test. Implementations swap in a recording fake instead.
abstract class HomeWidgetGateway {
  Future<void> saveWidgetData(String key, Object? value);
  Future<void> updateWidget({required String androidName});
  Future<String?> getWidgetData(String key);
}

class HomeWidgetPluginGateway implements HomeWidgetGateway {
  @override
  Future<void> saveWidgetData(String key, Object? value) async {
    await HomeWidget.saveWidgetData(key, value);
  }

  @override
  Future<void> updateWidget({required String androidName}) async {
    await HomeWidget.updateWidget(androidName: androidName);
  }

  @override
  Future<String?> getWidgetData(String key) {
    return HomeWidget.getWidgetData<String>(key);
  }
}

final homeWidgetGatewayProvider = Provider<HomeWidgetGateway>(
  (ref) => HomeWidgetPluginGateway(),
);
