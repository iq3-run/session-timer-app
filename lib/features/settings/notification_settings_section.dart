import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/settings/settings_sheet_widgets.dart';

/// UI-only mirror of the prototype's notify switch
/// (docs/session-timer.html `#notifyToggle`). Ephemeral local state, not
/// wired to `NotificationService`.
class NotificationSettingsSection extends StatelessWidget {
  const NotificationSettingsSection({
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: '通知',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: SessionTimerColors.amber,
          title: const Text(
            'フラッシュ/到達時に通知を送る',
            style: TextStyle(color: SessionTimerColors.white, fontSize: 13),
          ),
          value: enabled,
          onChanged: onChanged,
        ),
        const Text(
          'この設定は #22 で実際の通知に反映されます（現時点では見た目のみ）',
          style: TextStyle(color: SessionTimerColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}
