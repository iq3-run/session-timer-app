import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/multi_date_picker.dart';
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
  // Several days can be picked at once; each becomes its own event on add.
  Set<DateTime> _pickedDates = {};
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

  // The number field only exists for numbered types, so its text must not
  // block adding any other type.
  bool get _canSubmit =>
      _pickedDates.isNotEmpty &&
      (!numberedEventTypes.contains(_type) ||
          _pickedDates.length > 1 ||
          isValidManualNumberText(_numberController.text));

  // OR/CS exist at most once, so there is nothing to gain from picking
  // several days for them.
  bool get _allowsMultipleDates => !singletonEventTypes.contains(_type);

  // A manual number labels one specific event; stamping the same number on
  // a whole batch would be wrong, so the field only applies to a single day.
  bool get _numberFieldEnabled => _pickedDates.length <= 1;

  String get _dateButtonLabel {
    if (_pickedDates.isEmpty) return '日付';
    if (_pickedDates.length == 1) return formatScheduleDate(_pickedDates.first);
    return '${_pickedDates.length}日';
  }

  Widget _mainRow() {
    return Row(
      children: [
        if (numberedEventTypes.contains(_type)) ...[
          _numberField(),
          const SizedBox(width: 8),
        ],
        Expanded(child: _typeDropdown()),
        const SizedBox(width: 8),
        TextButton(
          key: const Key('scheduleDateButton'),
          onPressed: () => _pickDate(context),
          child: Text(
            _dateButtonLabel,
            style: const TextStyle(color: SessionTimerColors.muted),
          ),
        ),
        FilledButton(
          key: const Key('addScheduleEventButton'),
          onPressed: _canSubmit ? _submit : null,
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
        enabled: _numberFieldEnabled,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: SessionTimerColors.white),
        decoration: InputDecoration(
          labelText: '番号',
          // Shown while disabled so the greyed-out field isn't a mystery.
          helperText: _numberFieldEnabled ? null : '複数日は自動',
          helperMaxLines: 2,
          labelStyle: const TextStyle(color: SessionTimerColors.muted),
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
                !singletonEventTypes.contains(type) ||
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
        // Likewise a number typed for a numbered type: it would stay hidden
        // (and, if invalid, block adding) once the field is gone.
        if (!numberedEventTypes.contains(_type)) _numberController.clear();
        // A singleton type holds one event only: keep just the earliest day.
        if (!_allowsMultipleDates && _pickedDates.length > 1) {
          _pickedDates = {(_pickedDates.toList()..sort()).first};
        }
      }),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showMultiDatePicker(
      context,
      initialMonth: clampToScheduleRange(
        _pickedDates.isEmpty
            ? ref.read(correctedNowProvider)()
            : (_pickedDates.toList()..sort()).first,
      ),
      firstDate: earliestScheduleDate,
      lastDate: latestScheduleDate,
      initialSelection: _pickedDates,
      allowMultiple: _allowsMultipleDates,
    );
    if (picked == null || !context.mounted) return;
    setState(() {
      _pickedDates = picked;
      // The number belongs to a single event; drop it rather than leave
      // hidden text that would silently go unused.
      if (picked.length > 1) _numberController.clear();
    });
  }

  void _submit() {
    if (_pickedDates.isEmpty) return;
    final dates = _pickedDates.toList()..sort();
    final addedType = _type;
    final addedTrack = _track;
    final manualNumber =
        numberedEventTypes.contains(addedType) && dates.length == 1
        ? parseManualNumberText(_numberController.text)
        : null;
    unawaited(
      ref
          .read(sessionEventControllerProvider.notifier)
          .addEvents(
            addedType,
            dates,
            manualNumber: manualNumber,
            track: addedTrack,
          ),
    );
    setState(() {
      _pickedDates = {};
      _numberController.clear();
      // Back to 共通 after every add, like the date and number: otherwise a
      // forgotten A/B choice would silently put the next event on that
      // schedule.
      _track = SessionTrack.common;
      // OR/CS are singletons — once added, their dropdown entry disables
      // itself, so the selection must move off it or it'd point at a
      // disabled item.
      if (singletonEventTypes.contains(addedType)) {
        _type = SessionEventType.weekend;
      }
    });
  }
}
