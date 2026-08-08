import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/settings/settings_sheet_widgets.dart';
import 'package:session_timer/features/settings/weekend_milestone.dart';

/// UI-only mirror of the prototype's milestone list
/// (docs/session-timer.html `#milestoneList`/`#msLabelInput`/`#msDateInput`).
/// Not persisted.
class WeekendMilestonesSettingsSection extends StatelessWidget {
  const WeekendMilestonesSettingsSection({
    required this.milestones,
    required this.onAdd,
    required this.onRemove,
    super.key,
  });

  final List<WeekendMilestone> milestones;
  final void Function(String label, DateTime date) onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final sorted = [...milestones]..sort((a, b) => a.date.compareTo(b.date));
    return SettingsSection(
      title: 'おまけ：週末（マイルストーン）',
      children: [
        for (final m in sorted)
          SettingsListItem(
            label: m.label,
            meta: DateFormat('yyyy/MM/dd').format(m.date),
            onDelete: () => onRemove(m.id),
          ),
        _AddMilestoneRow(onAdd: onAdd),
      ],
    );
  }
}

class _AddMilestoneRow extends StatefulWidget {
  const _AddMilestoneRow({required this.onAdd});

  final void Function(String label, DateTime date) onAdd;

  @override
  State<_AddMilestoneRow> createState() => _AddMilestoneRowState();
}

class _AddMilestoneRowState extends State<_AddMilestoneRow> {
  final _labelController = TextEditingController();
  DateTime? _pickedDate;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('milestoneLabelField'),
            controller: _labelController,
            style: const TextStyle(color: SessionTimerColors.white),
            decoration: const InputDecoration(hintText: 'ラベル（例: 第3週末）'),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: const Key('milestoneDateButton'),
          onPressed: () => _pickDate(context),
          child: _DateLabel(_pickedDate),
        ),
        FilledButton(
          key: const Key('addMilestoneButton'),
          onPressed: _submit,
          child: const Text('追加'),
        ),
      ],
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
    final label = _labelController.text.trim();
    widget.onAdd(label.isEmpty ? '週末' : label, date);
    _labelController.clear();
    setState(() => _pickedDate = null);
  }
}

class _DateLabel extends StatelessWidget {
  const _DateLabel(this.date);

  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final text = date == null ? '日付' : DateFormat('MM/dd').format(date!);
    return Text(text, style: const TextStyle(color: SessionTimerColors.muted));
  }
}
