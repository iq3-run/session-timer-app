import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/flash/flash_points_controller.dart';
import 'package:session_timer/features/settings/flash_points_settings_section.dart';
import 'package:session_timer/features/settings/ntp_sync_settings_section.dart';

/// The settings sheet's shell, mirroring docs/session-timer.html's `#sheet`.
/// Flash points (add/remove/flash-toggle/notify-toggle) and NTP sync are
/// wired to their respective controllers (persisted). The prototype's
/// "週末（マイルストーン）" section now lives in its own dedicated screen
/// (`SessionScheduleScreen`, reachable from `ClockScreen`), not here.
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
    final flashPoints =
        ref.watch(flashPointsControllerProvider).value ?? const [];
    return [
      FlashPointsSettingsSection(
        points: flashPoints,
        onAdd: _addFlashPoint,
        onRemove: _removeFlashPoint,
        onToggleFlash: _setFlashEnabled,
        onToggleNotify: _setNotifyEnabled,
      ),
      NtpSyncSettingsSection(
        state: ref.watch(ntpSyncControllerProvider),
        onSync: _syncNtp,
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const Key('closeSettingsSheetButton'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('閉じる'),
      ),
    ];
  }

  void _syncNtp(String host) =>
      ref.read(ntpSyncControllerProvider.notifier).syncNow(host);

  void _addFlashPoint(int minutes) =>
      ref.read(flashPointsControllerProvider.notifier).addPoint(minutes);

  void _removeFlashPoint(int minutes) =>
      ref.read(flashPointsControllerProvider.notifier).removePoint(minutes);

  void _setFlashEnabled(int minutes, {required bool enabled}) => ref
      .read(flashPointsControllerProvider.notifier)
      .setFlashEnabled(minutes, enabled: enabled);

  void _setNotifyEnabled(int minutes, {required bool enabled}) => ref
      .read(flashPointsControllerProvider.notifier)
      .setNotifyEnabled(minutes, enabled: enabled);
}
