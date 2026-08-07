import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';

/// Placeholder home screen. Replaced feature-by-feature starting with the
/// current-time / completion-countdown display (tracking issue #1).
class ClockScreen extends StatelessWidget {
  const ClockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: SessionTimerColors.background,
      body: Center(
        child: Text(
          'SESSION TIMER',
          style: TextStyle(
            color: SessionTimerColors.muted,
            fontSize: 16,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }
}
