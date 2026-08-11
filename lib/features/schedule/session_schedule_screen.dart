import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/session_chain.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:session_timer/features/schedule/session_gap_calculation.dart';

const Map<SessionEventType, String> _typeNames = {
  SessionEventType.orientation: 'オリエンテーション(OR)',
  SessionEventType.weekend: '週末(WE)',
  SessionEventType.workday: 'ワークデー(WD)',
  SessionEventType.classroom: 'クラスルーム(CR)',
  SessionEventType.specialSession: '特別セッション(SS)',
  SessionEventType.completion: '完了セッション(CS)',
};

const Set<SessionEventType> _singletonTypes = {
  SessionEventType.orientation,
  SessionEventType.completion,
};

const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

String _formatDate(DateTime date) =>
    '${date.month}/${date.day}(${_weekdayLabels[date.weekday - 1]})';

String _formatGap(GapResult? gap) =>
    gap == null ? '' : '${gap.days}日(${gap.weeks}W)';

/// Dedicated screen for managing the session schedule (OR/WE/WD/CR/SS/CS)
/// and viewing the derived day-count table.
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AddEventForm(existingTypes: events.map((e) => e.type).toSet()),
            const SizedBox(height: 16),
            Expanded(child: _ScheduleTable(rows: rows)),
          ],
        ),
      ),
    );
  }
}

class _ScheduleTable extends ConsumerWidget {
  const _ScheduleTable({required this.rows});

  final List<ScheduleRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            DataColumn(label: Text('')),
          ],
          rows: [for (final row in rows) _rowFor(row, ref)],
        ),
      ),
    );
  }

  DataRow _rowFor(ScheduleRow row, WidgetRef ref) {
    return DataRow(
      color: row.isToday
          ? WidgetStatePropertyAll(
              SessionTimerColors.red.withValues(alpha: 0.15),
            )
          : null,
      cells: _cellsFor(row, ref),
    );
  }

  List<DataCell> _cellsFor(ScheduleRow row, WidgetRef ref) {
    return [
      DataCell(_TodayMarkedText(row.label, isToday: row.isToday)),
      DataCell(_TodayMarkedText(_formatDate(row.date), isToday: row.isToday)),
      DataCell(Text(_formatGap(row.chainGap))),
      DataCell(Text(_formatGap(row.todayGap))),
      DataCell(_deleteButton(row, ref)),
    ];
  }

  Widget _deleteButton(ScheduleRow row, WidgetRef ref) {
    if (row.event == null) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.close, color: SessionTimerColors.muted),
      onPressed: () => ref
          .read(sessionEventControllerProvider.notifier)
          .removeEvent(row.event!.id),
    );
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

class _AddEventForm extends ConsumerStatefulWidget {
  const _AddEventForm({required this.existingTypes});

  final Set<SessionEventType> existingTypes;

  @override
  ConsumerState<_AddEventForm> createState() => _AddEventFormState();
}

class _AddEventFormState extends ConsumerState<_AddEventForm> {
  SessionEventType _type = SessionEventType.weekend;
  DateTime? _pickedDate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _typeDropdown()),
        const SizedBox(width: 8),
        TextButton(
          key: const Key('scheduleDateButton'),
          onPressed: () => _pickDate(context),
          child: Text(
            _pickedDate == null ? '日付' : _formatDate(_pickedDate!),
            style: const TextStyle(color: SessionTimerColors.muted),
          ),
        ),
        FilledButton(
          key: const Key('addScheduleEventButton'),
          onPressed: _pickedDate == null ? null : _submit,
          child: const Text('追加'),
        ),
      ],
    );
  }

  DropdownButton<SessionEventType> _typeDropdown() {
    return DropdownButton<SessionEventType>(
      key: const Key('scheduleTypeDropdown'),
      value: _type,
      isExpanded: true,
      dropdownColor: SessionTimerColors.panel,
      items: [
        for (final type in SessionEventType.values)
          DropdownMenuItem(
            value: type,
            enabled:
                !_singletonTypes.contains(type) ||
                !widget.existingTypes.contains(type),
            child: Text(
              _typeNames[type]!,
              style: const TextStyle(color: SessionTimerColors.white),
            ),
          ),
      ],
      onChanged: (value) => setState(() => _type = value ?? _type),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !context.mounted) return;
    setState(() => _pickedDate = picked);
  }

  void _submit() {
    final date = _pickedDate;
    if (date == null) return;
    final addedType = _type;
    unawaited(
      ref
          .read(sessionEventControllerProvider.notifier)
          .addEvent(addedType, date),
    );
    setState(() {
      _pickedDate = null;
      // OR/CS are singletons — once added, their dropdown entry disables
      // itself, so the selection must move off it or it'd point at a
      // disabled item.
      if (_singletonTypes.contains(addedType)) {
        _type = SessionEventType.weekend;
      }
    });
  }
}
