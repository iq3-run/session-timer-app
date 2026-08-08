import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/duration_format.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/stopwatch/stopwatch_state.dart';

class StopwatchSection extends ConsumerWidget {
  const StopwatchSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stopwatchControllerProvider).value;
    final notifier = ref.read(stopwatchControllerProvider.notifier);

    return GestureDetector(
      onTap: notifier.toggle,
      onDoubleTap: notifier.resetAndRestart,
      onLongPress: notifier.reset,
      child: Container(
        padding: const EdgeInsets.only(top: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SessionTimerColors.line)),
        ),
        child: Column(
          children: [
            Text(_label(state), style: SessionTimerTextStyles.label),
            _ElapsedTime(state: state),
            const Text(
              'タップで開始/一時停止・長押しでリセット・ダブルタップでリスタート',
              style: TextStyle(fontSize: 11, color: SessionTimerColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  String _label(StopwatchState? state) {
    if (state == null) return '';
    if (state.isRunning) return '経過時間（計測中）';
    if (state.accumulatedMs > 0) return '経過時間（一時停止）';
    return 'タップして経過時間を計測';
  }
}

class _ElapsedTime extends StatefulWidget {
  const _ElapsedTime({required this.state});

  final StopwatchState? state;

  @override
  State<_ElapsedTime> createState() => _ElapsedTimeState();
}

class _ElapsedTimeState extends State<_ElapsedTime> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _ElapsedTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // Only ticks at 1/10s while actually running, so the stopwatch's smooth
  // display doesn't cost battery when idle or paused.
  void _syncTicker() {
    final isRunning = widget.state?.isRunning ?? false;
    if (isRunning && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => setState(() {}),
      );
    } else if (!isRunning && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.state?.elapsedAt(DateTime.now()) ?? Duration.zero;
    return Text(
      formatElapsedTenths(elapsed),
      style: SessionTimerTextStyles.value.copyWith(
        fontSize: 40,
        color: SessionTimerColors.white,
      ),
    );
  }
}
