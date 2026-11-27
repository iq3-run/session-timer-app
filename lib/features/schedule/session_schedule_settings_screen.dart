import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/session_chain.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:session_timer/features/schedule/session_event_numbering.dart';
import 'package:session_timer/features/schedule/session_schedule_add_form.dart';
import 'package:session_timer/features/schedule/session_schedule_dialogs.dart';
import 'package:session_timer/features/schedule/session_schedule_form_helpers.dart';
import 'package:session_timer/features/schedule/session_schedule_formatting.dart';

/// Add/delete/full-list management screen for the session schedule (OR/WE/
/// WD/CR/SS/CS), reachable from `SessionScheduleScreen`. Unlike that
/// read-only screen, every registered event shows here regardless of type
/// or its `visible` flag — this is the only place CR history beyond
/// "today/next" is visible, and the only place `visible` can be changed.
class SessionScheduleSettingsScreen extends ConsumerWidget {
  const SessionScheduleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(sessionEventControllerProvider).value ?? const [];
    final sorted = [...events]..sort((a, b) => a.date.compareTo(b.date));
    final numbers = assignSequenceNumbers(events);
    return Scaffold(
      backgroundColor: SessionTimerColors.background,
      appBar: AppBar(
        backgroundColor: SessionTimerColors.background,
        foregroundColor: SessionTimerColors.white,
        title: const Text('日程設定'),
        actions: [
          IconButton(
            key: const Key('deleteAllScheduleEvents'),
            tooltip: 'すべての日程を削除',
            icon: const Icon(Icons.delete_sweep),
            // Nothing to delete — disabled rather than opening a dialog
            // that would confirm removing zero rows.
            onPressed: events.isEmpty
                ? null
                : () => unawaited(_confirmAndDeleteAll(context, ref, events)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AddScheduleEventForm(
                existingTypes: events.map((e) => e.type).toSet(),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _EventList(events: sorted, numbers: numbers),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({required this.events, required this.numbers});

  final List<SessionEvent> events;
  final Map<String, int> numbers;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Text('登録されている日程はありません', style: SessionTimerTextStyles.label),
      );
    }
    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (context, index) =>
          _EventRow(event: events[index], numbers: numbers),
    );
  }
}

class _EventRow extends ConsumerWidget {
  const _EventRow({required this.event, required this.numbers});

  final SessionEvent event;
  final Map<String, int> numbers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sessionEventControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 48, child: _numberLabel(context, ref)),
          Expanded(child: _dateLabel(context, ref)),
          _VisibilityControl(
            event: event,
            numbers: numbers,
            notifier: notifier,
          ),
          IconButton(
            key: Key('removeScheduleEvent_${event.id}'),
            icon: const Icon(Icons.close, color: SessionTimerColors.muted),
            onPressed: () => notifier.removeEvent(event.id),
          ),
        ],
      ),
    );
  }

  Widget _numberLabel(BuildContext context, WidgetRef ref) {
    final label = Text(
      sessionEventLabel(event, numbers),
      style: SessionTimerTextStyles.label,
    );
    if (!numberedEventTypes.contains(event.type)) return label;
    // InkWell rather than GestureDetector — it picks up keyboard focus and
    // Enter/Space activation for free, which a bare GestureDetector doesn't.
    return InkWell(
      key: Key('editNumber_${event.id}'),
      onTap: () => _editManualNumber(context, ref, event),
      child: label,
    );
  }

  Widget _dateLabel(BuildContext context, WidgetRef ref) {
    return InkWell(
      key: Key('editDate_${event.id}'),
      onTap: () => _editDate(context, ref, event),
      child: Text(
        formatScheduleDate(event.date),
        style: const TextStyle(color: SessionTimerColors.white),
      ),
    );
  }
}

/// Asks for confirmation (stating how many events would go), then removes
/// every event. Cancelling — or dismissing the dialog — leaves them all.
Future<void> _confirmAndDeleteAll(
  BuildContext context,
  WidgetRef ref,
  List<SessionEvent> events,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => DeleteAllScheduleDialog(count: events.length),
  );
  if (confirmed != true || !context.mounted) return;
  await ref.read(sessionEventControllerProvider.notifier).removeEvents({
    for (final e in events) e.id,
  });
}

/// Opens a dialog to set or clear [event]'s manual number override.
Future<void> _editManualNumber(
  BuildContext context,
  WidgetRef ref,
  SessionEvent event,
) async {
  final result = await showDialog<ManualNumberResult>(
    context: context,
    builder: (context) => ManualNumberDialog(initial: event.manualNumber),
  );
  if (result == null) return;
  await ref
      .read(sessionEventControllerProvider.notifier)
      .setManualNumber(event.id, result.manualNumber);
}

/// Opens a picker, pre-selected to [event]'s current date, to change it.
Future<void> _editDate(
  BuildContext context,
  WidgetRef ref,
  SessionEvent event,
) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: clampToScheduleRange(event.date),
    firstDate: earliestScheduleDate,
    lastDate: latestScheduleDate,
  );
  if (picked == null || !context.mounted) return;
  await ref
      .read(sessionEventControllerProvider.notifier)
      .setDate(
        event.id,
        picked,
      );
}

class _VisibilityControl extends StatelessWidget {
  const _VisibilityControl({
    required this.event,
    required this.numbers,
    required this.notifier,
  });

  final SessionEvent event;
  final Map<String, int> numbers;
  final SessionEventController notifier;

  @override
  Widget build(BuildContext context) {
    if (!hasVisibilityToggle(event, numbers)) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          '常に表示',
          style: TextStyle(fontSize: 11, color: SessionTimerColors.muted),
        ),
      );
    }
    return Switch(
      key: Key('visibilityToggle_${event.id}'),
      value: event.visible,
      onChanged: (visible) => notifier.setVisible(event.id, visible: visible),
    );
  }
}
