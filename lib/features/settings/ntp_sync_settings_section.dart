import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/settings/settings_sheet_widgets.dart';

/// UI-only mirror of the prototype's NTP sync button
/// (docs/session-timer.html `#ntpSyncBtn`/`#ntpStatus`). Does not perform a
/// real network sync.
class NtpSyncSettingsSection extends StatelessWidget {
  const NtpSyncSettingsSection({
    required this.statusText,
    required this.onSyncPressed,
    super.key,
  });

  final String statusText;
  final VoidCallback onSyncPressed;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'おまけ：時刻同期（NTP風）',
      children: [
        FilledButton(
          onPressed: onSyncPressed,
          child: const Text('サーバー時刻に同期'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            statusText,
            style: const TextStyle(
              color: SessionTimerColors.muted,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
