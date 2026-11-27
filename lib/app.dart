import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/persistence/persistence_error_toast.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/clock/clock_screen.dart';
import 'package:session_timer/features/home_widget/home_widget_scheduler.dart';
import 'package:session_timer/features/notifications/notification_scheduler.dart';

class SessionTimerApp extends StatelessWidget {
  const SessionTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Session Timer',
      debugShowCheckedModeBanner: false,
      theme: SessionTimerTheme.dark,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ja'), Locale('en')],
      localeListResolutionCallback: resolveDeviceLocale,
      builder: (context, child) =>
          PersistenceErrorToast(child: child ?? const SizedBox.shrink()),
      home: const NotificationScheduler(
        child: HomeWidgetScheduler(child: ClockScreen()),
      ),
    );
  }
}

/// Picks the device's own locale for Material widgets (e.g. `showDatePicker`)
/// when flutter_localizations ships a translation for it, walking the
/// device's preferred-locale list in order; falls back to Japanese if none
/// of them are supported. `supportedLocales` isn't consulted — providing
/// this callback makes it purely declarative.
@visibleForTesting
Locale resolveDeviceLocale(
  List<Locale>? locales,
  Iterable<Locale> supportedLocales,
) {
  return (locales ?? const <Locale>[]).firstWhere(
    GlobalMaterialLocalizations.delegate.isSupported,
    orElse: () => const Locale('ja'),
  );
}
