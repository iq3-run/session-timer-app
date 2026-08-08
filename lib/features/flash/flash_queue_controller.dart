import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';
import 'package:session_timer/features/timer/timer_controller.dart';

/// How close two flash instants have to be to fold into a single played
/// flash rather than queueing separately (spec 3-5-1節).
const _flashMergeThreshold = Duration(seconds: 1);

class FlashQueueState {
  const FlashQueueState({required this.firedIds, this.active});

  /// The event currently animating in `FlashOverlay`, if any.
  final FlashEvent? active;

  /// Ids of every event whose window has been entered (played, merged into
  /// another flash, or missed while backgrounded) — used by
  /// `FlashPointsChipRow` to render "済" instead of a countdown.
  final Set<String> firedIds;
}

final flashQueueControllerProvider =
    NotifierProvider<FlashQueueController, FlashQueueState>(
      FlashQueueController.new,
    );

class FlashQueueController extends Notifier<FlashQueueState> {
  final Set<String> _firedIds = {};
  final List<FlashEvent> _queue = [];
  FlashEvent? _active;

  @override
  FlashQueueState build() {
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final completion = ref.watch(completionTimeControllerProvider).value;
    final targets = ref.watch(timeTargetsControllerProvider).value ?? const [];
    final timer = ref.watch(timerControllerProvider).value;

    // Sorted chronologically so that when several windows open in the same
    // build (e.g. resuming from a long background gap), each new event is
    // compared against its true nearest neighbor for merging — not just
    // whichever source happened to list it first.
    final candidates = [
      ...completionFlashEvents(completion),
      ...targetFlashEvents(targets),
      ...timerFlashEvents(timer),
    ]..sort((a, b) => a.instant.compareTo(b.instant));

    for (final event in candidates) {
      _admit(event, now);
    }
    _promoteNextIfIdle();

    return FlashQueueState(active: _active, firedIds: {..._firedIds});
  }

  void _promoteNextIfIdle() {
    if (_active == null && _queue.isNotEmpty) {
      _active = _queue.removeAt(0);
    }
  }

  /// Called by `FlashOverlay` when its animation for the current `active`
  /// event finishes — advances to the next queued event, chaining queued
  /// flashes back-to-back without a gap (spec 3-5-1節: 再生中の演出を中断
  /// せずキューイングして順番に再生する).
  void advance() {
    _active = null;
    _promoteNextIfIdle();
    state = FlashQueueState(active: _active, firedIds: {..._firedIds});
  }

  void _admit(FlashEvent event, DateTime now) {
    if (_firedIds.contains(event.id)) return;

    final windowStart = event.instant.subtract(flashAnimationDuration);
    if (now.isBefore(windowStart)) return; // not due yet

    // Window already closed — either fired earlier this session (handled
    // above) or missed entirely (e.g. backgrounded through it). Either way
    // it's done; mark it so a burst of past events never replays.
    _firedIds.add(event.id);
    if (now.isAfter(event.instant)) return;

    if (!_isMergeable(event)) _queue.add(event);
  }

  /// Whether [event] lands within [_flashMergeThreshold] of the currently
  /// playing flash or the last queued one — either way it's folded into
  /// that flash instead of getting its own (spec 3-5-1節).
  bool _isMergeable(FlashEvent event) {
    final nearest = _queue.isNotEmpty ? _queue.last : _active;
    if (nearest == null) return false;
    return event.instant.difference(nearest.instant).abs() <=
        _flashMergeThreshold;
  }
}
