import 'dart:async';

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

  String? _lastActiveId;

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      ref.read(flashQueueControllerProvider.notifier).advance();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(flashQueueControllerProvider).active;

    if (active != null && active.id != _lastActiveId) {
      _lastActiveId = active.id;
      _controller.stop();
      unawaited(_controller.forward(from: 0));
    } else if (active == null) {
      _lastActiveId = null;
    }

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

  bool _isVisibleSegment(FlashEvent? active) {
    if (active == null) return false;
    final segment = (_controller.value * _flashSegmentCount).floor().clamp(
      0,
      _flashSegmentCount - 1,
    );
    return segment.isOdd;
  }
}
