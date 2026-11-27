import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/session_schedule_form_helpers.dart';

class DeleteAllScheduleDialog extends StatelessWidget {
  const DeleteAllScheduleDialog({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SessionTimerColors.panel,
      title: const Text(
        'すべての日程を削除',
        style: TextStyle(color: SessionTimerColors.white),
      ),
      content: Text(
        '登録されている$count件の日程をすべて削除します。\nこの操作は元に戻せません。',
        style: const TextStyle(color: SessionTimerColors.white),
      ),
      actions: [
        TextButton(
          key: const Key('deleteAllCancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('deleteAllConfirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('削除'),
        ),
      ],
    );
  }
}

class ManualNumberResult {
  const ManualNumberResult(this.manualNumber);

  final int? manualNumber;
}

class ManualNumberDialog extends StatefulWidget {
  const ManualNumberDialog({super.key, required this.initial});

  final int? initial;

  @override
  State<ManualNumberDialog> createState() => _ManualNumberDialogState();
}

class _ManualNumberDialogState extends State<ManualNumberDialog> {
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
          onPressed: isValidManualNumberText(_controller.text)
              ? () => Navigator.of(context).pop(
                  ManualNumberResult(parseManualNumberText(_controller.text)),
                )
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
