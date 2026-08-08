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

      fake.setActive(
        FlashEvent(id: 'x', instant: DateTime.now(), label: 'test'),
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
}
