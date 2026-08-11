import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/session_chain.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:session_timer/features/schedule/session_event_numbering.dart';
import 'package:session_timer/features/schedule/session_schedule_formatting.dart';

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

/// Whether [event] gets a show/hide-on-`SessionScheduleScreen` toggle — CS,
/// the first WE, and CR always show there and never expose one (see
/// `session_chain.dart`'s `_isVisibleOnScheduleScreen`, which this mirrors).
bool _hasVisibilityToggle(SessionEvent event, Map<String, int> numbers) {
  if (event.type == SessionEventType.completion) return false;
  if (event.type == SessionEventType.classroom) return false;
  if (event.type == SessionEventType.weekend && numbers[event.id] == 1) {
    return false;
  }
  return true;
}

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
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AddEventForm(existingTypes: events.map((e) => e.type).toSet()),
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
          SizedBox(
            width: 48,
            child: Text(
              sessionEventLabel(event, numbers),
              style: SessionTimerTextStyles.label,
            ),
          ),
          Expanded(
            child: Text(
              formatScheduleDate(event.date),
              style: const TextStyle(color: SessionTimerColors.white),
            ),
          ),
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
    if (!_hasVisibilityToggle(event, numbers)) {
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
            _pickedDate == null ? '日付' : formatScheduleDate(_pickedDate!),
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
