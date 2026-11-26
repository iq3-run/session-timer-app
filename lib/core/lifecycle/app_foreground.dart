import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app is in the foreground right now (its window is shown and
/// has focus). A function rather than a value because callers need the
/// answer at the moment they act, not the one from their last rebuild.
///
/// `inactive` (e.g. the notification shade pulled down) counts as not
/// foreground: callers use this to *drop* something the user would
/// otherwise get, so when in doubt the answer is no.
///
/// Overridable so tests need no widgets binding.
final appInForegroundProvider = Provider<bool Function()>(
  (ref) =>
      () => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
);
