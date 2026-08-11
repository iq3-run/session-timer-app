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

/// Types that carry a sequence number (and so can take a manual override) —
/// OR/CR/CS never have one regardless of `manualNumber`.
const Set<SessionEventType> _numberedTypes = {
  SessionEventType.weekend,
  SessionEventType.workday,
  SessionEventType.specialSession,
};

/// Empty (auto) or a positive integer — shared by the add form's number
/// field and the edit dialog's, so both accept/reject the same input.
bool _isValidManualNumberText(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty || (int.tryParse(trimmed) ?? -1) > 0;
}

/// `null` for empty (auto) text; the caller is expected to have already
/// checked [_isValidManualNumberText].
int? _parseManualNumberText(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : int.tryParse(trimmed);
}

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
          SizedBox(width: 48, child: _numberLabel(context, ref)),
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

  Widget _numberLabel(BuildContext context, WidgetRef ref) {
    final label = Text(
      sessionEventLabel(event, numbers),
      style: SessionTimerTextStyles.label,
    );
    if (!_numberedTypes.contains(event.type)) return label;
    // InkWell rather than GestureDetector — it picks up keyboard focus and
    // Enter/Space activation for free, which a bare GestureDetector doesn't.
    return InkWell(
      key: Key('editNumber_${event.id}'),
      onTap: () => _editManualNumber(context, ref, event),
      child: label,
    );
  }
}

/// Opens a dialog to set or clear [event]'s manual number override.
Future<void> _editManualNumber(
  BuildContext context,
  WidgetRef ref,
  SessionEvent event,
) async {
  final result = await showDialog<_ManualNumberResult>(
    context: context,
    builder: (context) => _ManualNumberDialog(initial: event.manualNumber),
  );
  if (result == null) return;
  await ref
      .read(sessionEventControllerProvider.notifier)
      .setManualNumber(event.id, result.manualNumber);
}

class _ManualNumberResult {
  const _ManualNumberResult(this.manualNumber);

  final int? manualNumber;
}

class _ManualNumberDialog extends StatefulWidget {
  const _ManualNumberDialog({required this.initial});

  final int? initial;

  @override
  State<_ManualNumberDialog> createState() => _ManualNumberDialogState();
}

class _ManualNumberDialogState extends State<_ManualNumberDialog> {
  late final _controller = TextEditingController(
    text: widget.initial?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SessionTimerColors.panel,
      title: const Text(
        '番号を編集',
        style: TextStyle(color: SessionTimerColors.white),
      ),
      content: TextField(
        key: const Key('manualNumberDialogField'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: SessionTimerColors.white),
        decoration: const InputDecoration(
          labelText: '番号（空欄なら自動採番）',
          labelStyle: TextStyle(color: SessionTimerColors.muted),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('manualNumberDialogSave'),
          onPressed: _isValidManualNumberText(_controller.text)
              ? () => Navigator.of(context).pop(
                  _ManualNumberResult(_parseManualNumberText(_controller.text)),
                )
              : null,
          child: const Text('保存'),
        ),
      ],
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
  final _numberController = TextEditingController();

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
              onPressed:
                  _pickedDate == null ||
                      !_isValidManualNumberText(_numberController.text)
                  ? null
                  : _submit,
              child: const Text('追加'),
            ),
          ],
        ),
        if (_numberedTypes.contains(_type)) ...[
          const SizedBox(height: 8),
          TextField(
            key: const Key('scheduleManualNumberField'),
            controller: _numberController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: SessionTimerColors.white),
            decoration: const InputDecoration(
              labelText: '番号（空欄なら自動採番）',
              labelStyle: TextStyle(color: SessionTimerColors.muted),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
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
    final manualNumber = _numberedTypes.contains(addedType)
        ? _parseManualNumberText(_numberController.text)
        : null;
    unawaited(
      ref
          .read(sessionEventControllerProvider.notifier)
          .addEvent(addedType, date, manualNumber: manualNumber),
    );
    setState(() {
      _pickedDate = null;
      _numberController.clear();
      // OR/CS are singletons — once added, their dropdown entry disables
      // itself, so the selection must move off it or it'd point at a
      // disabled item.
      if (_singletonTypes.contains(addedType)) {
        _type = SessionEventType.weekend;
      }
    });
  }
}
