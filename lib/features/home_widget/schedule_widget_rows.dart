import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/features/schedule/session_chain.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Only changes value when the calendar day rolls over, unlike `nowProvider`
/// itself (which ticks every second). The schedule widget has no natively
/// self-driving `Chronometer` to keep its "today" row correct after
/// midnight — this provider is what lets `scheduleWidgetRowsProvider`
/// recompute once a day without re-pushing to the widget on every tick.
final scheduleWidgetTodayProvider = Provider<DateTime>((ref) {
  return ref.watch(
    nowProvider.select((async) => _dateOnly(async.value ?? DateTime.now())),
  );
});

/// The exact same rows as the read-only セッションスケジュール screen
/// (`SessionScheduleScreen` via `buildScheduleRows`) — the widget mirrors
/// that screen's content and `SessionEvent.visible` filtering, not a
/// separate "every raw event" view.
final scheduleWidgetRowsProvider = Provider<List<ScheduleRow>>((ref) {
  final events = ref.watch(sessionEventControllerProvider).value ?? const [];
  final today = ref.watch(scheduleWidgetTodayProvider);
  return buildScheduleRows(events, today);
});
