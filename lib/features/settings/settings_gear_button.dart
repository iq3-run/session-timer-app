import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/settings/settings_sheet.dart';

/// Entry point into the settings sheet, matching the prototype's `#gearBtn`
/// (docs/session-timer.html). Placed inline in `ClockScreen`'s layout since
/// the app has no `AppBar`.
class SettingsGearButton extends StatelessWidget {
  const SettingsGearButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        tooltip: '設定',
        icon: const Icon(Icons.settings, color: SessionTimerColors.muted),
        onPressed: () => SettingsSheet.show(context),
      ),
    );
  }
}
