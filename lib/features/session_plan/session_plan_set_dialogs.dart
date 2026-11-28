import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/session_plan/session_plan_book.dart';

/// Asks for a 組's name. Returns the trimmed text, or `null` if cancelled.
/// An empty result is only possible with [allowEmpty] (meaning "pick one for
/// me"); otherwise the save button stays disabled until something is typed.
Future<String?> promptSessionSetName(
  BuildContext context, {
  required String title,
  required String initial,
  String? hint,
  bool allowEmpty = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SessionSetNameDialog(
      title: title,
      initial: initial,
      hint: hint,
      allowEmpty: allowEmpty,
    ),
  );
}

class _SessionSetNameDialog extends StatefulWidget {
  const _SessionSetNameDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.allowEmpty,
  });

  final String title;
  final String initial;
  final String? hint;
  final bool allowEmpty;

  @override
  State<_SessionSetNameDialog> createState() => _SessionSetNameDialogState();
}

class _SessionSetNameDialogState extends State<_SessionSetNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave => widget.allowEmpty || _controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SessionTimerColors.panel,
      title: Text(
        widget.title,
        style: const TextStyle(color: SessionTimerColors.white),
      ),
      content: TextField(
        key: const Key('sessionSetNameField'),
        controller: _controller,
        autofocus: true,
        maxLength: maxSessionPlanSetNameLength,
        style: const TextStyle(color: SessionTimerColors.white),
        decoration: InputDecoration(
          labelText: '組の名前',
          hintText: widget.hint,
          labelStyle: const TextStyle(color: SessionTimerColors.muted),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('sessionSetNameSave'),
          onPressed: _canSave ? _submit : null,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_canSave) return;
    Navigator.of(context).pop(_controller.text.trim());
  }
}

/// Confirms deleting a 組 together with its [sessionCount] sessions.
Future<bool> confirmRemoveSessionSet(
  BuildContext context, {
  required String name,
  required int sessionCount,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: SessionTimerColors.panel,
      title: const Text(
        '組を削除',
        style: TextStyle(color: SessionTimerColors.white),
      ),
      content: Text(
        '「$name」と、登録されている$sessionCount件のセッションを削除します。\n'
        'この操作は元に戻せません。',
        style: const TextStyle(color: SessionTimerColors.white),
      ),
      actions: [
        TextButton(
          key: const Key('removeSetCancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('removeSetConfirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('削除'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
