import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';

/// Shared section heading + body, matching the prototype's `.sheetTitle`
/// (docs/session-timer.html).
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                color: SessionTimerColors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// Shared row for a deletable entry, matching the prototype's `.list-item`.
class SettingsListItem extends StatelessWidget {
  const SettingsListItem({
    required this.label,
    required this.onDelete,
    this.meta,
    super.key,
  });

  final String label;
  final String? meta;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: SessionTimerColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: label,
                style: const TextStyle(color: SessionTimerColors.white),
                children: [
                  if (meta != null)
                    TextSpan(
                      text: '  $meta',
                      style: const TextStyle(
                        color: SessionTimerColors.muted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: onDelete,
            child: const Text(
              '削除',
              style: TextStyle(color: SessionTimerColors.red),
            ),
          ),
        ],
      ),
    );
  }
}
