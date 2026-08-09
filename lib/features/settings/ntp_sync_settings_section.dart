import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/settings/settings_sheet_widgets.dart';

const _unsyncedStatusText = '未同期（端末時刻を使用中）';
const _syncingStatusText = '同期中…';
const _failedStatusText = '同期失敗（インターネット接続を確認してください）';

/// NTP sync settings, mirroring the prototype's sync button
/// (docs/session-timer.html `#ntpSyncBtn`/`#ntpStatus`) plus a free-text
/// server field (not present in the prototype). [state] is supplied by the
/// caller, which owns `NtpSyncController`.
class NtpSyncSettingsSection extends StatefulWidget {
  const NtpSyncSettingsSection({
    required this.state,
    required this.onSync,
    super.key,
  });

  final AsyncValue<NtpSyncState> state;
  final ValueChanged<String> onSync;

  @override
  State<NtpSyncSettingsSection> createState() => _NtpSyncSettingsSectionState();
}

class _NtpSyncSettingsSectionState extends State<NtpSyncSettingsSection> {
  final _hostController = TextEditingController(text: defaultNtpServerHost);

  // The persisted host only becomes known once the controller finishes its
  // first build (usually after this widget's first frame) — seed the field
  // from it exactly once, then leave the user's own edits alone.
  bool _seededFromState = false;

  @override
  void initState() {
    super.initState();
    _seedHostIfNeeded();
  }

  @override
  void didUpdateWidget(covariant NtpSyncSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _seedHostIfNeeded();
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  void _seedHostIfNeeded() {
    if (_seededFromState) return;
    final host = widget.state.value?.serverHost;
    if (host == null) return;
    _seededFromState = true;
    _hostController.text = host;
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.state.isLoading || _isSyncing;
    return SettingsSection(
      title: 'おまけ：時刻同期（NTP風）',
      children: [
        _HostSyncRow(controller: _hostController, busy: busy, onSync: _submit),
        _StatusLine(_statusText),
      ],
    );
  }

  bool get _isSyncing => widget.state.value?.status == NtpSyncStatus.syncing;

  // Normalize the field itself (not just what's persisted) so a blank
  // submission visibly becomes the default host instead of leaving the
  // field looking out of sync with what actually got synced.
  void _submit() {
    final normalized = normalizeNtpHost(_hostController.text);
    _hostController.text = normalized;
    widget.onSync(normalized);
  }

  String get _statusText {
    final syncState = widget.state.value;
    if (syncState == null || syncState.status == NtpSyncStatus.unsynced) {
      return _unsyncedStatusText;
    }
    if (syncState.status == NtpSyncStatus.syncing) return _syncingStatusText;
    if (syncState.status == NtpSyncStatus.failed) return _failedStatusText;
    return _syncedStatusText(syncState);
  }

  // `syncState.lastSyncedAt`, not `DateTime.now()` — this getter re-runs on
  // every rebuild (e.g. editing an unrelated milestone), and a live clock
  // here would make the timestamp jump on rebuilds that have nothing to do
  // with syncing. Non-null assertion: every `synced` state is constructed
  // with `lastSyncedAt` set, so a null here means that invariant broke.
  String _syncedStatusText(NtpSyncState syncState) =>
      '同期完了（誤差補正 ${syncState.offsetMs}ms） / '
      '${DateFormat('HH:mm:ss').format(syncState.lastSyncedAt!)}';
}

class _HostSyncRow extends StatelessWidget {
  const _HostSyncRow({
    required this.controller,
    required this.busy,
    required this.onSync,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('ntpServerHostField'),
            controller: controller,
            enabled: !busy,
            style: const TextStyle(color: SessionTimerColors.white),
            decoration: const InputDecoration(hintText: 'NTPサーバー'),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('ntpSyncButton'),
          onPressed: busy ? null : onSync,
          child: const Text('サーバー時刻に同期'),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: const TextStyle(color: SessionTimerColors.muted, fontSize: 12),
      ),
    );
  }
}
