import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:session_timer/core/clock/duration_format.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/core/clock/time_of_day_resolver.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/targets/time_target.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';

class TimeTargetsSection extends ConsumerWidget {
  const TimeTargetsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(timeTargetsControllerProvider).value ?? const [];
    return Column(
      children: [
        for (final target in targets) _TimeTargetRow(target: target),
        const _AddTargetRow(),
      ],
    );
  }
}

class _TimeTargetRow extends ConsumerWidget {
  const _TimeTargetRow({required this.target});

  final TimeTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _editTarget(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Stack(
          children: [
            Column(
              children: [
                Text(
                  '指定時刻 ${DateFormat('H:mm').format(target.targetTime)}',
                  style: SessionTimerTextStyles.label,
                ),
                _TargetCountdown(target: target),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'この指定時刻を削除',
                icon: const Icon(
                  Icons.close,
                  color: SessionTimerColors.muted,
                  size: 16,
                ),
                onPressed: () => ref
                    .read(timeTargetsControllerProvider.notifier)
                    .removeTarget(target.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTarget(BuildContext context, WidgetRef ref) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(target.targetTime),
    );
    if (picked == null || !context.mounted) return;
    final resolved = resolveNextOccurrence(picked, DateTime.now());
    await ref
        .read(timeTargetsControllerProvider.notifier)
        .updateTarget(target.id, resolved);
  }
}

class _TargetCountdown extends ConsumerWidget {
  const _TargetCountdown({required this.target});

  final TimeTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = watchNow(ref);
    final isHit = !now.isBefore(target.targetTime);
    return Text(
      formatCountdown(target.targetTime.difference(now)),
      style: SessionTimerTextStyles.value.copyWith(
        fontSize: 32,
        color: isHit ? SessionTimerColors.red : SessionTimerColors.cyan,
      ),
    );
  }
}

class _AddTargetRow extends ConsumerWidget {
  const _AddTargetRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _addTarget(context, ref),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('＋ 指定時刻を追加', style: SessionTimerTextStyles.label),
      ),
    );
  }

  Future<void> _addTarget(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (picked == null || !context.mounted) return;
    final resolved = resolveNextOccurrence(picked, DateTime.now());
    await ref.read(timeTargetsControllerProvider.notifier).addTarget(resolved);
  }
}
