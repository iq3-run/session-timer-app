import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/flash/flash_overlay.dart';
import 'package:session_timer/features/flash/flash_queue_controller.dart';

class _FakeFlashQueueController extends FlashQueueController {
  @override
  FlashQueueState build() => const FlashQueueState(firedIds: {});

  void setActive(FlashEvent? event) {
    state = FlashQueueState(firedIds: state.firedIds, active: event);
  }
}

double _overlayOpacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.byType(Opacity)).opacity;

void main() {
  testWidgets(
    'blinks while a flash is active and calls advance() when it finishes',
    (tester) async {
      final fake = _FakeFlashQueueController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [flashQueueControllerProvider.overrideWith(() => fake)],
          child: const MaterialApp(home: FlashOverlay()),
        ),
      );

      expect(_overlayOpacity(tester), 0);

      // instant is set to "now + duration" so the window just opened
      // (elapsed progress ~= 0), matching a flash admitted right on time.
      fake.setActive(
        FlashEvent(
          id: 'x',
          instant: DateTime.now().add(flashAnimationDuration),
          label: 'test',
        ),
      );
      await tester.pump();
      expect(_overlayOpacity(tester), 0); // first blink segment: invisible

      await tester.pump(const Duration(milliseconds: 260));
      expect(_overlayOpacity(tester), 1); // second segment: visible

      await tester.pump(flashAnimationDuration);
      expect(_overlayOpacity(tester), 0);
      expect(fake.state.active, isNull); // advance() ran on completion
    },
  );

  testWidgets(
    'starts from elapsed progress when its window opened before this '
    'widget noticed, so it still ends at event.instant instead of late',
    (tester) async {
      final fake = _FakeFlashQueueController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [flashQueueControllerProvider.overrideWith(() => fake)],
          child: const MaterialApp(home: FlashOverlay()),
        ),
      );

      // windowStart (instant - duration) is ~1s in the past, simulating a
      // FlashQueueController tick that admitted this event ~1s after its
      // window actually opened — so ~2s of animation should remain.
      const lateBy = Duration(seconds: 1);
      final remaining = flashAnimationDuration - lateBy;
      fake.setActive(
        FlashEvent(
          id: 'late',
          instant: DateTime.now().add(remaining),
          label: 'test',
        ),
      );
      await tester.pump();

      // A fresh (progress 0) animation would need the full 3s and still be
      // mid-flight here; one that correctly started ~1s in only needs the
      // ~2s remaining.
      await tester.pump(remaining + const Duration(milliseconds: 300));
      expect(fake.state.active, isNull);
    },
  );
}
