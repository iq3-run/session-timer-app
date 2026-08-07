import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/clock/clock_screen.dart';

class SessionTimerApp extends StatelessWidget {
  const SessionTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Session Timer',
      debugShowCheckedModeBanner: false,
      theme: SessionTimerTheme.dark,
      home: const ClockScreen(),
    );
  }
}
