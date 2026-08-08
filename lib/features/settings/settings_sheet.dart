import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/flash/flash_points_controller.dart';
import 'package:session_timer/features/settings/flash_points_settings_section.dart';
import 'package:session_timer/features/settings/notification_settings_section.dart';
import 'package:session_timer/features/settings/ntp_sync_settings_section.dart';
import 'package:session_timer/features/settings/weekend_milestone.dart';
import 'package:session_timer/features/settings/weekend_milestones_settings_section.dart';

const _unsyncedStatusText = '未同期（端末時刻を使用中）';
const _syncPlaceholderStatusText = '同期は未実装です（実装予定: issue #1）';

/// The settings sheet's shell, mirroring docs/session-timer.html's `#sheet`.
/// Flash points are wired to `FlashPointsController` (persisted); the
/// notification/milestone/NTP sections below remain ephemeral to this
/// widget's lifetime, not yet wired to the app's real state.
class SettingsSheet extends ConsumerStatefulWidget {
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
  ConsumerState<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<SettingsSheet> {
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
            children: _sections(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final flashPointMinutes =
        ref.watch(flashPointsControllerProvider).value ?? const [];
    return [
      FlashPointsSettingsSection(
        minutes: flashPointMinutes,
        onAdd: _addFlashPoint,
        onRemove: _removeFlashPoint,
      ),
      NotificationSettingsSection(
        enabled: _notifyEnabled,
        onChanged: _setNotifyEnabled,
      ),
      WeekendMilestonesSettingsSection(
        milestones: _milestones,
        onAdd: _addMilestone,
        onRemove: _removeMilestone,
      ),
      NtpSyncSettingsSection(
        statusText: _ntpStatusText,
        onSyncPressed: _syncNow,
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const Key('closeSettingsSheetButton'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('閉じる'),
      ),
    ];
  }

  void _setNotifyEnabled(bool value) => setState(() => _notifyEnabled = value);

  void _syncNow() =>
      setState(() => _ntpStatusText = _syncPlaceholderStatusText);

  void _addFlashPoint(int minutes) =>
      ref.read(flashPointsControllerProvider.notifier).addPoint(minutes);

  void _removeFlashPoint(int minutes) =>
      ref.read(flashPointsControllerProvider.notifier).removePoint(minutes);

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
