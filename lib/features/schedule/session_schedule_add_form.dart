import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:session_timer/features/schedule/session_schedule_form_helpers.dart';
import 'package:session_timer/features/schedule/session_schedule_formatting.dart';

class AddScheduleEventForm extends ConsumerStatefulWidget {
  const AddScheduleEventForm({super.key, required this.existingTypes});

  final Set<SessionEventType> existingTypes;

  @override
  ConsumerState<AddScheduleEventForm> createState() =>
      _AddScheduleEventFormState();
}

class _AddScheduleEventFormState extends ConsumerState<AddScheduleEventForm> {
  SessionEventType _type = SessionEventType.weekend;
  SessionTrack _track = SessionTrack.common;
  DateTime? _pickedDate;
  final _numberController = TextEditingController();

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The A/B selector gets its own line: the main row is already full on a
    // narrow portrait screen, and only WE/WD ever show it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mainRow(),
        if (SessionEvent.supportsTrack(_type)) _trackSelector(),
      ],
    );
  }

  Widget _trackSelector() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Text('日程', style: TextStyle(color: SessionTimerColors.muted)),
          const SizedBox(width: 12),
          SegmentedButton<SessionTrack>(
            key: const Key('scheduleTrackSelector'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: SessionTrack.common, label: Text('共通')),
              ButtonSegment(value: SessionTrack.a, label: Text('A')),
              ButtonSegment(value: SessionTrack.b, label: Text('B')),
            ],
            selected: {_track},
            onSelectionChanged: (selection) =>
                setState(() => _track = selection.first),
          ),
        ],
      ),
    );
  }

  Widget _mainRow() {
    return Row(
      children: [
        if (numberedScheduleTypes.contains(_type)) ...[
          _numberField(),
          const SizedBox(width: 8),
        ],
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
                  !isValidManualNumberText(_numberController.text)
              ? null
              : _submit,
          child: const Text('追加'),
        ),
      ],
    );
  }

  Widget _numberField() {
    return SizedBox(
      width: 64,
      child: TextField(
        key: const Key('scheduleManualNumberField'),
        controller: _numberController,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: SessionTimerColors.white),
        decoration: const InputDecoration(
          labelText: '番号',
          labelStyle: TextStyle(color: SessionTimerColors.muted),
        ),
        onChanged: (_) => setState(() {}),
      ),
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
                !singletonScheduleTypes.contains(type) ||
                !widget.existingTypes.contains(type),
            child: Text(
              scheduleTypeNames[type]!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: SessionTimerColors.white),
            ),
          ),
      ],
      onChanged: (value) => setState(() {
        _type = value ?? _type;
        // A/B only exists for WE/WD; don't carry a leftover choice over to
        // a type that can't have one.
        if (!SessionEvent.supportsTrack(_type)) _track = SessionTrack.common;
      }),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: clampToScheduleRange(_pickedDate ?? DateTime.now()),
      firstDate: earliestScheduleDate,
      lastDate: latestScheduleDate,
    );
    if (picked == null || !context.mounted) return;
    setState(() => _pickedDate = picked);
  }

  void _submit() {
    final date = _pickedDate;
    if (date == null) return;
    final addedType = _type;
    final addedTrack = _track;
    final manualNumber = numberedScheduleTypes.contains(addedType)
        ? parseManualNumberText(_numberController.text)
        : null;
    unawaited(
      ref
          .read(sessionEventControllerProvider.notifier)
          .addEvent(
            addedType,
            date,
            manualNumber: manualNumber,
            track: addedTrack,
          ),
    );
    setState(() {
      _pickedDate = null;
      _numberController.clear();
      // Back to 共通 after every add, like the date and number: otherwise a
      // forgotten A/B choice would silently put the next event on that
      // schedule.
      _track = SessionTrack.common;
      // OR/CS are singletons — once added, their dropdown entry disables
      // itself, so the selection must move off it or it'd point at a
      // disabled item.
      if (singletonScheduleTypes.contains(addedType)) {
        _type = SessionEventType.weekend;
      }
    });
  }
}
