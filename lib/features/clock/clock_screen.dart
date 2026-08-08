import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/clock/current_time_display.dart';
import 'package:session_timer/features/completion/completion_countdown_section.dart';
import 'package:session_timer/features/flash/flash_overlay.dart';
import 'package:session_timer/features/flash/flash_points_chip_row.dart';
import 'package:session_timer/features/settings/settings_gear_button.dart';
import 'package:session_timer/features/stopwatch/stopwatch_section.dart';
import 'package:session_timer/features/targets/time_targets_section.dart';
import 'package:session_timer/features/timer/timer_section.dart';

class ClockScreen extends StatelessWidget {
  const ClockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: SessionTimerColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SettingsGearButton(),
                    CurrentTimeDisplay(),
                    SizedBox(height: 8),
                    CompletionCountdownSection(),
                    SizedBox(height: 16),
                    TimeTargetsSection(),
                    SizedBox(height: 16),
                    StopwatchSection(),
                    SizedBox(height: 16),
                    TimerSection(),
                    SizedBox(height: 16),
                    FlashPointsChipRow(),
                  ],
                ),
              ),
            ),
            FlashOverlay(),
          ],
        ),
      ),
    );
  }
}
