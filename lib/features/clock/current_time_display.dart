import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';

class CurrentTimeDisplay extends ConsumerWidget {
  const CurrentTimeDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = watchNow(ref);
    return Column(
      children: [
        const Text('現在時刻', style: SessionTimerTextStyles.label),
        Text(
          DateFormat('HH:mm:ss').format(now),
          style: SessionTimerTextStyles.value.copyWith(
            color: SessionTimerColors.white,
          ),
        ),
      ],
    );
  }
}
