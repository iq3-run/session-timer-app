import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/clock/duration_format.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/stopwatch/stopwatch_state.dart';

const _tickInterval = Duration(milliseconds: 100);

class StopwatchSection extends ConsumerWidget {
  const StopwatchSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stopwatchControllerProvider).value;
    final notifier = ref.read(stopwatchControllerProvider.notifier);

    return Container(
      padding: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SessionTimerColors.line)),
      ),
      child: Column(
        children: [
          GestureDetector(
            // The tappable area is the whole section, not just where the
            // text itself paints — without this, taps landing in the
            // padding or between lines are silently ignored.
            behavior: HitTestBehavior.opaque,
            onTap: notifier.toggle,
            onDoubleTap: notifier.resetAndRestart,
            onLongPress: notifier.reset,
            child: Column(
              children: [
                Text(_label(state), style: SessionTimerTextStyles.label),
                _ElapsedTime(state: state),
                const Text(
                  'タップで開始/一時停止・長押しでリセット・ダブルタップでリスタート',
                  style: TextStyle(
                    fontSize: 11,
                    color: SessionTimerColors.muted,
                  ),
                ),
              ],
            ),
          ),
          // Outside the GestureDetector on purpose: a double-tap recognizer
          // above it would delay this button's tap by the double-tap window
          // and let a quick second tap restart the stopwatch.
          TextButton.icon(
            key: const Key('adjustStopwatch'),
            onPressed: state == null
                ? null
                : () => _adjust(context, notifier, state),
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('経過時間を調整'),
          ),
        ],
      ),
    );
  }

  Future<void> _adjust(
    BuildContext context,
    StopwatchController notifier,
    StopwatchState state,
  ) async {
    final elapsed = await showDialog<Duration>(
      context: context,
      builder: (_) =>
          _AdjustElapsedDialog(initial: state.elapsedAt(DateTime.now())),
    );
    if (elapsed != null) await notifier.setElapsed(elapsed);
  }

  String _label(StopwatchState? state) {
    // While SharedPreferences is still loading, `state` is briefly null —
    // treat it the same as the idle state so the label doesn't pop in and
    // shift the layout once loading resolves.
    if (state == null || (!state.isRunning && state.accumulatedMs == 0)) {
      return 'タップして経過時間を計測';
    }
    if (state.isRunning) return '経過時間（計測中）';
    return '経過時間（一時停止）';
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
      _ticker = Timer.periodic(_tickInterval, (_) {
        if (mounted) setState(() {});
      });
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

/// Longest value the dialog accepts: 99:59:59 would overflow the display's
/// layout for no practical benefit, so cap at 99 hours' worth of minutes.
const int _maxMinutes = 99 * 60 + 59;

class _AdjustElapsedDialog extends StatefulWidget {
  const _AdjustElapsedDialog({required this.initial});

  final Duration initial;

  @override
  State<_AdjustElapsedDialog> createState() => _AdjustElapsedDialogState();
}

class _AdjustElapsedDialogState extends State<_AdjustElapsedDialog> {
  late final TextEditingController _minutes = TextEditingController(
    text: widget.initial.inMinutes.clamp(0, _maxMinutes).toString(),
  );
  late final TextEditingController _seconds = TextEditingController(
    text: widget.initial.inSeconds.remainder(60).toString(),
  );
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_minutes.text.trim());
    final seconds = int.tryParse(_seconds.text.trim());
    if (minutes == null ||
        seconds == null ||
        minutes < 0 ||
        minutes > _maxMinutes ||
        seconds < 0 ||
        seconds > 59) {
      setState(() => _error = '分は0〜$_maxMinutes、秒は0〜59の整数で入力してください');
      return;
    }
    Navigator.of(context).pop(Duration(minutes: minutes, seconds: seconds));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('経過時間を調整'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('adjustMinutes'),
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '分'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  key: const Key('adjustSeconds'),
                  controller: _seconds,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '秒'),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('adjustCancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        TextButton(
          key: const Key('adjustConfirm'),
          onPressed: _submit,
          child: const Text('設定'),
        ),
      ],
    );
  }
}
