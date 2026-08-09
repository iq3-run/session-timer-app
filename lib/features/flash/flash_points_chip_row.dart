import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/duration_format.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/flash/flash_points_controller.dart';
import 'package:session_timer/features/flash/flash_queue_controller.dart';

const _visibleChipCount = 3;
const _idleRevertDelay = Duration(seconds: 5);

List<int> _sortDescending(List<int> minutes) =>
    [...minutes]..sort((a, b) => b.compareTo(a));

/// 完了◯分前 flash points, shown 3 at a time with swipe paging that reverts
/// to the default (next-to-fire) window after 5s idle (spec 3-4節).
class FlashPointsChipRow extends ConsumerStatefulWidget {
  const FlashPointsChipRow({super.key});

  @override
  ConsumerState<FlashPointsChipRow> createState() => _FlashPointsChipRowState();
}

class _FlashPointsChipRowState extends ConsumerState<FlashPointsChipRow> {
  int? _windowStart;
  Timer? _idleTimer;

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = ref
        .watch(completionTimeControllerProvider)
        .value
        ?.targetTime;
    final sortedPoints = _sortDescending(
      ref.watch(flashPointsControllerProvider).value ?? const [],
    );
    if (target == null || sortedPoints.isEmpty) return const SizedBox.shrink();

    final now = watchNow(ref);
    final firedIds = ref.watch(flashQueueControllerProvider).firedIds;
    final targetEpochMs = target.millisecondsSinceEpoch;
    // Reclamped on every build, not just when _onSwipe sets it — the
    // settings sheet can shrink the point list out from under an active
    // custom window at any time, and a stale out-of-range _windowStart
    // would otherwise render zero chips until the 5s idle revert fires.
    final windowStart =
        (_windowStart ??
                _defaultWindowStart(sortedPoints, targetEpochMs, firedIds))
            .clamp(0, _maxWindowStart(sortedPoints));

    return GestureDetector(
      onHorizontalDragEnd: (details) =>
          _onSwipe(details, sortedPoints, windowStart),
      child: _ChipRowContent(
        sortedPoints: sortedPoints,
        target: target,
        now: now,
        firedIds: firedIds,
        windowStart: windowStart,
      ),
    );
  }

  int _defaultWindowStart(
    List<int> sortedPoints,
    int targetEpochMs,
    Set<String> firedIds,
  ) {
    final firstPending = sortedPoints.indexWhere(
      (m) => !firedIds.contains('completion:$targetEpochMs:$m'),
    );
    final maxStart = _maxWindowStart(sortedPoints);
    if (firstPending == -1) return maxStart;
    return firstPending.clamp(0, maxStart);
  }

  void _onSwipe(
    DragEndDetails details,
    List<int> sortedPoints,
    int currentWindowStart,
  ) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity == 0) return;

    final maxStart = _maxWindowStart(sortedPoints);
    final step = velocity < 0 ? _visibleChipCount : -_visibleChipCount;
    setState(
      () => _windowStart = (currentWindowStart + step).clamp(0, maxStart),
    );

    _idleTimer?.cancel();
    _idleTimer = Timer(_idleRevertDelay, () {
      if (mounted) setState(() => _windowStart = null);
    });
  }

  int _maxWindowStart(List<int> sortedPoints) =>
      sortedPoints.length > _visibleChipCount
      ? sortedPoints.length - _visibleChipCount
      : 0;
}

class _ChipRowContent extends StatelessWidget {
  const _ChipRowContent({
    required this.sortedPoints,
    required this.target,
    required this.now,
    required this.firedIds,
    required this.windowStart,
  });

  final List<int> sortedPoints;
  final DateTime target;
  final DateTime now;
  final Set<String> firedIds;
  final int windowStart;

  @override
  Widget build(BuildContext context) {
    final targetEpochMs = target.millisecondsSinceEpoch;
    final visible = sortedPoints.skip(windowStart).take(_visibleChipCount);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Ellipsis(visible: windowStart > 0),
        for (final m in visible)
          _FlashPointChip(
            minutesBefore: m,
            target: target,
            now: now,
            fired: firedIds.contains('completion:$targetEpochMs:$m'),
          ),
        _Ellipsis(
          visible: windowStart + _visibleChipCount < sortedPoints.length,
        ),
      ],
    );
  }
}

class _Ellipsis extends StatelessWidget {
  const _Ellipsis({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(width: 12);
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 2),
      child: Text('…', style: TextStyle(color: SessionTimerColors.muted)),
    );
  }
}

class _FlashPointChip extends StatelessWidget {
  const _FlashPointChip({
    required this.minutesBefore,
    required this.target,
    required this.now,
    required this.fired,
  });

  final int minutesBefore;
  final DateTime target;
  final DateTime now;
  final bool fired;

  @override
  Widget build(BuildContext context) {
    final instant = target.subtract(Duration(minutes: minutesBefore));
    final remaining = instant.isBefore(now)
        ? Duration.zero
        : instant.difference(now);
    final color = fired ? SessionTimerColors.red : SessionTimerColors.muted;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '残$minutesBefore分フラッシュ',
            style: TextStyle(color: color, fontSize: 11),
          ),
          Text(
            fired ? '済' : formatCountdown(remaining),
            style: TextStyle(
              color: fired ? SessionTimerColors.red : SessionTimerColors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
