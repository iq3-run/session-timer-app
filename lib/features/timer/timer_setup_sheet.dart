import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/features/timer/timer_state.dart';

const _defaultSetupDuration = Duration(minutes: 5);

class TimerSetupResult {
  const TimerSetupResult(this.mode, this.duration);

  final TimerMode mode;
  final Duration duration;
}

class TimerSetupSheet extends StatefulWidget {
  const TimerSetupSheet({super.key});

  @override
  State<TimerSetupSheet> createState() => _TimerSetupSheetState();
}

class _TimerSetupSheetState extends State<TimerSetupSheet> {
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
              ).pop(TimerSetupResult(_mode, _duration)),
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
