import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:session_timer/core/clock/duration_format.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/core/clock/time_of_day_resolver.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';

class CompletionCountdownSection extends ConsumerWidget {
  const CompletionCountdownSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref
        .watch(completionTimeControllerProvider)
        .value
        ?.targetTime;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pickCompletionTime(context, ref, target),
      child: Stack(
        children: [
          _CountdownBody(target: target),
          if (target != null)
            _ClearButton(
              onPressed: () =>
                  ref.read(completionTimeControllerProvider.notifier).clear(),
            ),
        ],
      ),
    );
  }

  Future<void> _pickCompletionTime(
    BuildContext context,
    WidgetRef ref,
    DateTime? currentTarget,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: currentTarget == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(currentTarget),
    );
    if (picked == null || !context.mounted) return;
    final target = resolveNextOccurrence(picked, DateTime.now());
    await ref.read(completionTimeControllerProvider.notifier).setTarget(target);
  }
}

class _CountdownBody extends ConsumerWidget {
  const _CountdownBody({required this.target});

  final DateTime? target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = watchNow(ref);
    final isOverdue = target != null && now.isAfter(target!);
    return Column(
      children: [
        const Text('完了まで', style: SessionTimerTextStyles.label),
        Text(
          target == null ? '--:--' : formatCountdown(target!.difference(now)),
          style: SessionTimerTextStyles.value.copyWith(
            color: isOverdue
                ? SessionTimerColors.red
                : SessionTimerColors.amber,
          ),
        ),
        Text(_subtitle(target, isOverdue), style: SessionTimerTextStyles.label),
      ],
    );
  }

  String _subtitle(DateTime? target, bool isOverdue) {
    if (target == null) return 'タップして完了時刻を設定';
    final clock = DateFormat('HH:mm').format(target);
    final prefix = isOverdue ? '超過 / 完了予定だった時刻 ' : '完了予定 ';
    return '$prefix$clock（タップで変更）';
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: IconButton(
        tooltip: '完了時刻をクリア',
        icon: const Icon(
          Icons.close,
          color: SessionTimerColors.muted,
          size: 18,
        ),
        onPressed: onPressed,
      ),
    );
  }
}
