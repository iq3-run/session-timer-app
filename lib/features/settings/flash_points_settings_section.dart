import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/settings/settings_sheet_widgets.dart';

/// UI-only mirror of the prototype's flash-point add/remove list
/// (docs/session-timer.html `#flashList`/`#flashMinInput`). [minutes] is
/// ephemeral state owned by `SettingsSheet`, not backed by
/// `FlashQueueController`.
class FlashPointsSettingsSection extends StatelessWidget {
  const FlashPointsSettingsSection({
    required this.minutes,
    required this.onAdd,
    required this.onRemove,
    super.key,
  });

  final List<int> minutes;
  final ValueChanged<int> onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final sorted = [...minutes]..sort((a, b) => b.compareTo(a));
    return SettingsSection(
      title: '完了◯分前フラッシュ',
      children: [
        for (final m in sorted)
          SettingsListItem(
            label: '残り $m 分',
            onDelete: () => onRemove(m),
          ),
        _AddFlashPointRow(onAdd: onAdd),
      ],
    );
  }
}

class _AddFlashPointRow extends StatefulWidget {
  const _AddFlashPointRow({required this.onAdd});

  final ValueChanged<int> onAdd;

  @override
  State<_AddFlashPointRow> createState() => _AddFlashPointRowState();
}

class _AddFlashPointRowState extends State<_AddFlashPointRow> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('flashMinutesField'),
            controller: _controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: SessionTimerColors.white),
            decoration: const InputDecoration(hintText: '分'),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('addFlashPointButton'),
          onPressed: _submit,
          child: const Text('追加'),
        ),
      ],
    );
  }

  void _submit() {
    final minutes = int.tryParse(_controller.text);
    if (minutes == null || minutes <= 0) return;
    widget.onAdd(minutes);
    _controller.clear();
  }
}
