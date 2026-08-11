import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/session_chain.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:session_timer/features/schedule/session_gap_calculation.dart';
import 'package:session_timer/features/schedule/session_schedule_formatting.dart';
import 'package:session_timer/features/schedule/session_schedule_settings_screen.dart';

String _formatGap(GapResult? gap) =>
    gap == null ? '' : '${gap.days}日(${gap.weeks}W)';

/// Read-only screen showing the derived 週末間/今日から day-count table.
/// Adding, deleting, and the show/hide-on-this-screen toggle all live in
/// `SessionScheduleSettingsScreen`, reachable via the gear button here.
class SessionScheduleScreen extends ConsumerWidget {
  const SessionScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = watchNow(ref);
    final today = DateTime(now.year, now.month, now.day);
    final events = ref.watch(sessionEventControllerProvider).value ?? const [];
    return Scaffold(
      backgroundColor: SessionTimerColors.background,
      appBar: AppBar(
        backgroundColor: SessionTimerColors.background,
        foregroundColor: SessionTimerColors.white,
        title: const Text('セッションスケジュール'),
        actions: [
          IconButton(
            key: const Key('scheduleSettingsButton'),
            tooltip: '日程設定',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SessionScheduleSettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: _ScheduleBody(events: events, today: today),
    );
  }
}

class _ScheduleBody extends StatelessWidget {
  const _ScheduleBody({required this.events, required this.today});

  final List<SessionEvent> events;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final rows = buildScheduleRows(events, today);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _ScheduleTable(rows: rows),
      ),
    );
  }
}

class _ScheduleTable extends StatelessWidget {
  const _ScheduleTable({required this.rows});

  final List<ScheduleRow> rows;

  @override
  Widget build(BuildContext context) {
    // Nested scroll views: the outer one is vertical (the row count is
    // unbounded — past events are kept forever, see SessionEventController)
    // and the inner one is horizontal, for the table's own width.
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('')),
            DataColumn(label: Text('日付')),
            DataColumn(label: Text('週末間')),
            DataColumn(label: Text('今日から')),
          ],
          rows: [for (final row in rows) _rowFor(row)],
        ),
      ),
    );
  }

  DataRow _rowFor(ScheduleRow row) {
    return DataRow(
      color: row.isToday
          ? WidgetStatePropertyAll(
              SessionTimerColors.red.withValues(alpha: 0.15),
            )
          : null,
      cells: _cellsFor(row),
    );
  }

  List<DataCell> _cellsFor(ScheduleRow row) {
    return [
      DataCell(_TodayMarkedText(row.label, isToday: row.isToday)),
      DataCell(
        _TodayMarkedText(formatScheduleDate(row.date), isToday: row.isToday),
      ),
      DataCell(Text(_formatGap(row.chainGap))),
      DataCell(Text(_formatGap(row.todayGap))),
    ];
  }
}

/// Underlines the cell's text in red when its row is today's marker —
/// the "目立つように" highlight the user asked for.
class _TodayMarkedText extends StatelessWidget {
  const _TodayMarkedText(this.text, {required this.isToday});

  final String text;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: SessionTimerColors.white,
        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
        decoration: isToday ? TextDecoration.underline : null,
        decorationColor: SessionTimerColors.red,
        decorationThickness: 2,
      ),
    );
  }
}
