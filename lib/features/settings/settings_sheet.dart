import 'package:flutter/material.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/settings/flash_points_settings_section.dart';
import 'package:session_timer/features/settings/notification_settings_section.dart';
import 'package:session_timer/features/settings/ntp_sync_settings_section.dart';
import 'package:session_timer/features/settings/weekend_milestone.dart';
import 'package:session_timer/features/settings/weekend_milestones_settings_section.dart';

const _initialFlashPointMinutes = [10, 5, 1];
const _unsyncedStatusText = '未同期（端末時刻を使用中）';
const _syncPlaceholderStatusText = '同期は未実装です（実装予定: issue #1）';

/// The settings sheet's UI-only shell, mirroring
/// docs/session-timer.html's `#sheet`. Every section's state below is
/// ephemeral to this widget's lifetime — none of it is wired to the app's
/// real state or persisted. See plans/feat-settings-sheet-shell.md.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: SessionTimerColors.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const SettingsSheet(),
    );
  }

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  List<int> _flashPointMinutes = [..._initialFlashPointMinutes];
  bool _notifyEnabled = false;
  List<WeekendMilestone> _milestones = [];
  int _nextMilestoneId = 0;
  String _ntpStatusText = _unsyncedStatusText;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlashPointsSettingsSection(
                minutes: _flashPointMinutes,
                onAdd: _addFlashPoint,
                onRemove: _removeFlashPoint,
              ),
              NotificationSettingsSection(
                enabled: _notifyEnabled,
                onChanged: (value) => setState(() => _notifyEnabled = value),
              ),
              WeekendMilestonesSettingsSection(
                milestones: _milestones,
                onAdd: _addMilestone,
                onRemove: _removeMilestone,
              ),
              NtpSyncSettingsSection(
                statusText: _ntpStatusText,
                onSyncPressed: () => setState(
                  () => _ntpStatusText = _syncPlaceholderStatusText,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('closeSettingsSheetButton'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('閉じる'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addFlashPoint(int minutes) {
    if (_flashPointMinutes.contains(minutes)) return;
    setState(() => _flashPointMinutes = [..._flashPointMinutes, minutes]);
  }

  void _removeFlashPoint(int minutes) {
    setState(
      () => _flashPointMinutes = _flashPointMinutes
          .where((m) => m != minutes)
          .toList(),
    );
  }

  void _addMilestone(String label, DateTime date) {
    final milestone = WeekendMilestone(
      id: _nextMilestoneId++,
      label: label,
      date: date,
    );
    setState(() => _milestones = [..._milestones, milestone]);
  }

  void _removeMilestone(int id) {
    setState(
      () => _milestones = _milestones.where((m) => m.id != id).toList(),
    );
  }
}
