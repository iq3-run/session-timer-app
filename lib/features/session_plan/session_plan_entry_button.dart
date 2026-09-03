import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/session_plan/session_plan_screen.dart';

/// Entry point into [SessionPlanScreen].
class SessionPlanEntryButton extends StatelessWidget {
  const SessionPlanEntryButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        tooltip: 'セッションの流れ',
        icon: const Icon(
          Icons.view_timeline_outlined,
          color: SessionTimerColors.muted,
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SessionPlanScreen()),
        ),
      ),
    );
  }
}
