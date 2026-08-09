import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/flash/flash_point_config.dart';
import 'package:session_timer/features/settings/settings_sheet_widgets.dart';

/// Flash-point add/remove list, each row with its own フラッシュ/通知
/// toggle. Mirrors the prototype's (docs/session-timer.html
/// `#flashList`/`#flashMinInput`) add/remove UI, extended with the two
/// switches. [points] and the callbacks are supplied by the caller, which
/// owns whatever backs them.
class FlashPointsSettingsSection extends StatelessWidget {
  const FlashPointsSettingsSection({
    required this.points,
    required this.onAdd,
    required this.onRemove,
    required this.onToggleFlash,
    required this.onToggleNotify,
    super.key,
  });

  final List<FlashPointConfig> points;
  final ValueChanged<int> onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int minutes, {required bool enabled}) onToggleFlash;
  final void Function(int minutes, {required bool enabled}) onToggleNotify;

  @override
  Widget build(BuildContext context) {
    final sorted = [...points]..sort((a, b) => b.minutes.compareTo(a.minutes));
    return SettingsSection(
      title: '完了◯分前フラッシュ',
      children: [
        for (final p in sorted)
          _FlashPointRow(
            point: p,
            onRemove: () => onRemove(p.minutes),
            onToggleFlash: (enabled) =>
                onToggleFlash(p.minutes, enabled: enabled),
            onToggleNotify: (enabled) =>
                onToggleNotify(p.minutes, enabled: enabled),
          ),
        _AddFlashPointRow(onAdd: onAdd),
      ],
    );
  }
}

class _FlashPointRow extends StatelessWidget {
  const _FlashPointRow({
    required this.point,
    required this.onRemove,
    required this.onToggleFlash,
    required this.onToggleNotify,
  });

  final FlashPointConfig point;
  final VoidCallback onRemove;
  final ValueChanged<bool> onToggleFlash;
  final ValueChanged<bool> onToggleNotify;

  @override
  Widget build(BuildContext context) {
    return SettingsRowContainer(
      verticalPadding: 4,
      children: [
        Expanded(
          child: Text(
            '残り ${point.minutes} 分',
            style: const TextStyle(color: SessionTimerColors.white),
          ),
        ),
        _ToggleLabel(
          switchKey: Key('flashToggle_${point.minutes}'),
          label: 'フラッシュ',
          value: point.flashEnabled,
          onChanged: onToggleFlash,
        ),
        _ToggleLabel(
          switchKey: Key('notifyToggle_${point.minutes}'),
          label: '通知',
          value: point.notifyEnabled,
          // フラッシュOFFの点は通知も強制OFF・変更不可（フラッシュしないのに
          // 通知だけ来る状態を防ぐ）。
          onChanged: point.flashEnabled ? onToggleNotify : null,
        ),
        SettingsDeleteButton(
          key: Key('removeFlashPoint_${point.minutes}'),
          onPressed: onRemove,
        ),
      ],
    );
  }
}

class _ToggleLabel extends StatelessWidget {
  const _ToggleLabel({
    required this.switchKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: disabled
                  ? SessionTimerColors.muted
                  : SessionTimerColors.white,
              fontSize: 10,
            ),
          ),
          Switch(
            key: switchKey,
            value: value,
            onChanged: onChanged,
            activeThumbColor: SessionTimerColors.amber,
          ),
        ],
      ),
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
