import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/duration_format.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/timer/timer_controller.dart';
import 'package:session_timer/features/timer/timer_state.dart';

const _defaultSetupDuration = Duration(minutes: 5);

class TimerSection extends ConsumerWidget {
  const TimerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timerControllerProvider).value;
    final notifier = ref.read(timerControllerProvider.notifier);
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openSetup(context, ref),
          onLongPress: notifier.reset,
          child: Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: SessionTimerColors.line)),
            ),
            child: _TimerBody(state: state),
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _QuickAddButton(label: '+30秒', amount: Duration(seconds: 30)),
            SizedBox(width: 12),
            _QuickAddButton(label: '+1分', amount: Duration(minutes: 1)),
          ],
        ),
      ],
    );
  }

  Future<void> _openSetup(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<_TimerSetupResult>(
      context: context,
      backgroundColor: SessionTimerColors.panel,
      builder: (context) => const _TimerSetupSheet(),
    );
    if (result == null) return;
    await ref
        .read(timerControllerProvider.notifier)
        .start(result.mode, result.duration);
  }
}

class _TimerBody extends StatefulWidget {
  const _TimerBody({required this.state});

  final TimerState? state;

  @override
  State<_TimerBody> createState() => _TimerBodyState();
}

class _TimerBodyState extends State<_TimerBody> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _TimerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // Dedicated 1s ticker, independent of the shared nowProvider the
  // current-time/completion/targets displays tick on — only runs while a
  // timer is actually running, matching StopwatchSection's _ElapsedTime.
  void _syncTicker() {
    final isRunning = widget.state?.isRunning ?? false;
    if (isRunning && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!isRunning && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final now = DateTime.now();
    final isOverdue = state != null && state.isOverdueAt(now);
    return Column(
      children: [
        Text(_label(state, isOverdue), style: SessionTimerTextStyles.label),
        Text(_value(state, now), style: _valueStyle(isOverdue)),
        Text(
          _subtitle(state),
          style: const TextStyle(
            fontSize: 11,
            color: SessionTimerColors.muted,
          ),
        ),
      ],
    );
  }

  String _value(TimerState? state, DateTime now) {
    if (state == null || !state.isRunning) return '--:--';
    return formatCountdown(state.remainingAt(now));
  }

  TextStyle _valueStyle(bool isOverdue) =>
      SessionTimerTextStyles.value.copyWith(
        color: isOverdue ? SessionTimerColors.red : SessionTimerColors.amber,
      );

  String _label(TimerState? state, bool isOverdue) {
    if (state == null || !state.isRunning) return 'タイマー';
    final modeLabel = state.mode == TimerMode.linked ? '連動タイマー' : 'タイマー';
    return isOverdue ? '$modeLabel（超過）' : modeLabel;
  }

  String _subtitle(TimerState? state) {
    if (state == null || !state.isRunning) return 'タップして設定';
    return 'タップで再設定・長押しでリセット';
  }
}

class _QuickAddButton extends ConsumerWidget {
  const _QuickAddButton({required this.label, required this.amount});

  final String label;
  final Duration amount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(timerControllerProvider.notifier);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => notifier.addTime(amount),
      onLongPress: () => notifier.quickStart(amount),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: SessionTimerColors.line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: SessionTimerTextStyles.label),
      ),
    );
  }
}

class _TimerSetupResult {
  const _TimerSetupResult(this.mode, this.duration);

  final TimerMode mode;
  final Duration duration;
}

class _TimerSetupSheet extends StatefulWidget {
  const _TimerSetupSheet();

  @override
  State<_TimerSetupSheet> createState() => _TimerSetupSheetState();
}

class _TimerSetupSheetState extends State<_TimerSetupSheet> {
  TimerMode _mode = TimerMode.normal;
  Duration _duration = _defaultSetupDuration;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeSelector(
              mode: _mode,
              onChanged: (mode) => setState(() => _mode = mode),
            ),
            _DurationPicker(
              duration: _duration,
              onChanged: (duration) => setState(() => _duration = duration),
            ),
            _StartButton(
              enabled: _duration > Duration.zero,
              onPressed: () => Navigator.of(
                context,
              ).pop(_TimerSetupResult(_mode, _duration)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final TimerMode mode;
  final ValueChanged<TimerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TimerMode>(
      segments: const [
        ButtonSegment(value: TimerMode.normal, label: Text('通常タイマー')),
        ButtonSegment(value: TimerMode.linked, label: Text('連動タイマー')),
      ],
      selected: {mode},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _DurationPicker extends StatelessWidget {
  const _DurationPicker({required this.duration, required this.onChanged});

  final Duration duration;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 216,
      child: CupertinoTheme(
        data: const CupertinoThemeData(brightness: Brightness.dark),
        child: CupertinoTimerPicker(
          mode: CupertinoTimerPickerMode.ms,
          initialTimerDuration: duration,
          onTimerDurationChanged: onChanged,
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      child: const Text('この設定でスタート'),
    );
  }
}
