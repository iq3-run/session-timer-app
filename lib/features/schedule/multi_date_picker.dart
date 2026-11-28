import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';

const _weekdayHeaders = ['月', '火', '水', '木', '金', '土', '日'];

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// A month-grid dialog for picking several calendar days at once (Flutter's
/// own `showDatePicker` takes exactly one, and `showDateRangePicker` only a
/// contiguous run). Tap a day to select it, tap again to deselect; the
/// month arrows move between months without losing what was selected.
///
/// Returns the chosen days as midnight-normalized dates, or `null` if
/// cancelled. With [allowMultiple] false, tapping a day replaces the
/// selection instead of adding to it (for event types that can only exist
/// once).
Future<Set<DateTime>?> showMultiDatePicker(
  BuildContext context, {
  required DateTime initialMonth,
  required DateTime firstDate,
  required DateTime lastDate,
  Set<DateTime> initialSelection = const {},
  bool allowMultiple = true,
}) {
  return showDialog<Set<DateTime>>(
    context: context,
    builder: (_) => MultiDatePickerDialog(
      initialMonth: initialMonth,
      firstDate: firstDate,
      lastDate: lastDate,
      initialSelection: initialSelection,
      allowMultiple: allowMultiple,
    ),
  );
}

class MultiDatePickerDialog extends StatefulWidget {
  const MultiDatePickerDialog({
    super.key,
    required this.initialMonth,
    required this.firstDate,
    required this.lastDate,
    this.initialSelection = const {},
    this.allowMultiple = true,
  });

  final DateTime initialMonth;
  final DateTime firstDate;
  final DateTime lastDate;
  final Set<DateTime> initialSelection;
  final bool allowMultiple;

  @override
  State<MultiDatePickerDialog> createState() => _MultiDatePickerDialogState();
}

class _MultiDatePickerDialogState extends State<MultiDatePickerDialog> {
  late DateTime _month = DateTime(
    widget.initialMonth.year,
    widget.initialMonth.month,
  );
  late final Set<DateTime> _selected = {
    for (final d in widget.initialSelection) _dayOnly(d),
  };

  bool get _hasPrevMonth => DateTime(_month.year, _month.month - 1).isAfter(
    DateTime(widget.firstDate.year, widget.firstDate.month - 1),
  );

  bool get _hasNextMonth => DateTime(_month.year, _month.month + 1).isBefore(
    DateTime(widget.lastDate.year, widget.lastDate.month + 1),
  );

  bool _inRange(DateTime day) =>
      !day.isBefore(_dayOnly(widget.firstDate)) &&
      !day.isAfter(_dayOnly(widget.lastDate));

  void _toggle(DateTime day) {
    setState(() {
      if (_selected.contains(day)) {
        _selected.remove(day);
      } else {
        if (!widget.allowMultiple) _selected.clear();
        _selected.add(day);
      }
    });
  }

  void _moveMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SessionTimerColors.panel,
      // Scrolls rather than overflows when a landscape phone leaves little
      // height for the 6-week grid.
      scrollable: true,
      // Narrower insets so each of the 7 columns keeps a usable tap width on
      // a 360dp phone.
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 336,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const SizedBox(height: 8),
            _weekdayRow(),
            _grid(),
            const SizedBox(height: 8),
            Text(
              widget.allowMultiple
                  ? '${_selected.length}日選択中（タップで追加・解除）'
                  : '${_selected.length}日選択中',
              key: const Key('multiDateSelectedCount'),
              style: SessionTimerTextStyles.label,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('multiDateClear'),
          onPressed: _selected.isEmpty ? null : () => setState(_selected.clear),
          child: const Text('クリア'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('multiDateConfirm'),
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(Set.of(_selected)),
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: [
        IconButton(
          key: const Key('multiDatePrevMonth'),
          tooltip: '前の月',
          onPressed: _hasPrevMonth ? () => _moveMonth(-1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            '${_month.year}年${_month.month}月',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SessionTimerColors.white,
              fontSize: 16,
            ),
          ),
        ),
        IconButton(
          key: const Key('multiDateNextMonth'),
          tooltip: '次の月',
          onPressed: _hasNextMonth ? () => _moveMonth(1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _weekdayRow() {
    return Row(
      children: [
        for (final label in _weekdayHeaders)
          Expanded(
            child: Center(
              child: Text(label, style: SessionTimerTextStyles.label),
            ),
          ),
      ],
    );
  }

  Widget _grid() {
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // DateTime.weekday is Mon=1..Sun=7, matching the header's Monday start.
    final leadingBlanks = first.weekday - 1;
    final cellCount = ((leadingBlanks + daysInMonth + 6) ~/ 7) * 7;
    // Plain rows rather than a GridView: AlertDialog measures its content's
    // intrinsic size, which a lazy viewport can't provide.
    return Column(
      children: [
        for (var start = 0; start < cellCount; start += 7)
          SizedBox(
            height: 48,
            child: Row(
              children: [
                for (var index = start; index < start + 7; index++)
                  Expanded(
                    child: _cellAt(index - leadingBlanks + 1, daysInMonth),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cellAt(int dayNumber, int daysInMonth) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox.shrink();
    }
    return _dayCell(DateTime(_month.year, _month.month, dayNumber));
  }

  Widget _dayCell(DateTime day) {
    final selected = _selected.contains(day);
    final enabled = _inRange(day);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${day.month}月${day.day}日',
      excludeSemantics: true,
      child: InkWell(
        key: Key('multiDateDay_${day.year}-${day.month}-${day.day}'),
        customBorder: const CircleBorder(),
        onTap: enabled ? () => _toggle(day) : null,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? SessionTimerColors.amber : null,
            ),
            child: Center(
              child: Text(
                '${day.day}',
                style: TextStyle(
                  color: selected
                      ? SessionTimerColors.background
                      : enabled
                      ? SessionTimerColors.white
                      : SessionTimerColors.line,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
