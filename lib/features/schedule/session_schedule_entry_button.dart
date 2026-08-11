import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/session_schedule_screen.dart';

/// Entry point into [SessionScheduleScreen].
class SessionScheduleEntryButton extends StatelessWidget {
  const SessionScheduleEntryButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        tooltip: 'セッションスケジュール',
        icon: const Icon(
          Icons.event_note_outlined,
          color: SessionTimerColors.muted,
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SessionScheduleScreen(),
          ),
        ),
      ),
    );
  }
}
