import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/flash/flash_queue_controller.dart';

const int _flashSegmentCount = flashBlinkCount * 2;

/// Full-screen amber strobe, played whenever `FlashQueueController` reports
/// an active event. Owns its own [AnimationController] rather than the 1Hz
/// `nowProvider` tick, since the blink pattern needs sub-second granularity.
class FlashOverlay extends ConsumerStatefulWidget {
  const FlashOverlay({super.key});

  @override
  ConsumerState<FlashOverlay> createState() => _FlashOverlayState();
}

class _FlashOverlayState extends ConsumerState<FlashOverlay>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: flashAnimationDuration,
  )..addStatusListener(_onStatusChanged);

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      ref.read(flashQueueControllerProvider.notifier).advance();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // A window that had already fully elapsed by the time this event was
  // promoted (e.g. resuming from background through several missed
  // windows) would otherwise call forward(from: 1.0). AnimationController
  // treats that as a zero-duration no-op and skips notifying listeners
  // when the controller's last reported status is already `completed`
  // (true here, from the previous event finishing normally) — so
  // _onStatusChanged never fires and advance() never gets called, leaving
  // the overlay stuck fully opaque. Advance directly instead.
  void _onActiveEventChanged(FlashQueueState? previous, FlashQueueState next) {
    final event = next.active;
    if (event == null || event.id == previous?.active?.id) return;
    _controller.stop();
    final progress = _elapsedProgress(event);
    if (progress >= 1.0) {
      ref.read(flashQueueControllerProvider.notifier).advance();
      return;
    }
    _controller.forward(from: progress);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(flashQueueControllerProvider, _onActiveEventChanged);
    final active = ref.watch(flashQueueControllerProvider).active;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Opacity(
          opacity: _isVisibleSegment(active) ? 1 : 0,
          child: const ColoredBox(
            color: SessionTimerColors.amber,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  /// How far into [flashAnimationDuration] [event]'s window already is,
  /// as a 0–1 fraction. `FlashQueueController` only admits events once per
  /// ~1s `nowProvider` tick, so a window can open up to ~1s before this
  /// widget notices — starting from this fraction instead of always 0
  /// keeps the strobe ending at `event.instant` rather than up to ~1s late.
  double _elapsedProgress(FlashEvent event) {
    final elapsedMs = DateTime.now()
        .difference(event.windowStart)
        .inMilliseconds;
    return (elapsedMs / flashAnimationDuration.inMilliseconds).clamp(0.0, 1.0);
  }

  bool _isVisibleSegment(FlashEvent? active) {
    if (active == null) return false;
    final segment = (_controller.value * _flashSegmentCount).floor().clamp(
      0,
      _flashSegmentCount - 1,
    );
    return segment.isOdd;
  }
}
