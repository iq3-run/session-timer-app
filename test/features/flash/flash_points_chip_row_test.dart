import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/completion/completion_time_state.dart';
import 'package:session_timer/features/flash/flash_points_chip_row.dart';
import 'package:session_timer/features/flash/flash_queue_controller.dart';

class _FixedCompletionController extends CompletionTimeController {
  _FixedCompletionController(this._value);
  final CompletionTimeState _value;
  @override
  Future<CompletionTimeState> build() async => _value;
}

class _FixedFlashQueueController extends FlashQueueController {
  _FixedFlashQueueController(this._firedIds);
  final Set<String> _firedIds;
  @override
  FlashQueueState build() => FlashQueueState(firedIds: _firedIds);
}

Future<void> _pump(
  WidgetTester tester, {
  required DateTime now,
  CompletionTimeState completion = const CompletionTimeState(),
  Set<String> firedIds = const {},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nowProvider.overrideWith((ref) => Stream.value(now)),
        completionTimeControllerProvider.overrideWith(
          () => _FixedCompletionController(completion),
        ),
        flashQueueControllerProvider.overrideWith(
          () => _FixedFlashQueueController(firedIds),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: FlashPointsChipRow())),
    ),
  );
  await tester.pump();
}

void main() {
  group('FlashPointsChipRow', () {
    testWidgets('renders nothing when no completion time is set', (
      tester,
    ) async {
      await _pump(tester, now: DateTime(2099));

      expect(find.text('残120分フラッシュ'), findsNothing);
    });

    testWidgets('shows the next 3 not-yet-fired points by default', (
      tester,
    ) async {
      final target = DateTime(2099, 1, 1, 12);
      await _pump(
        tester,
        now: target.subtract(const Duration(hours: 3)),
        completion: CompletionTimeState(
          targetEpochMs: target.millisecondsSinceEpoch,
        ),
      );

      expect(find.text('残120分フラッシュ'), findsOneWidget);
      expect(find.text('残90分フラッシュ'), findsOneWidget);
      expect(find.text('残60分フラッシュ'), findsOneWidget);
      expect(find.text('残45分フラッシュ'), findsNothing);
      expect(find.text('…'), findsOneWidget); // trailing ellipsis only
    });

    testWidgets('skips fired points to find the default window', (
      tester,
    ) async {
      final target = DateTime(2099, 1, 1, 12);
      final targetEpochMs = target.millisecondsSinceEpoch;
      await _pump(
        tester,
        now: target.subtract(const Duration(minutes: 80)),
        completion: CompletionTimeState(targetEpochMs: targetEpochMs),
        firedIds: {
          'completion:$targetEpochMs:120',
          'completion:$targetEpochMs:90',
        },
      );

      expect(find.text('残60分フラッシュ'), findsOneWidget);
      expect(find.text('残45分フラッシュ'), findsOneWidget);
      expect(find.text('残30分フラッシュ'), findsOneWidget);
      expect(find.text('…'), findsNWidgets(2)); // leading and trailing
    });

    testWidgets('swipe pages the window and reverts after 5s idle', (
      tester,
    ) async {
      final target = DateTime(2099, 1, 1, 12);
      await _pump(
        tester,
        now: target.subtract(const Duration(hours: 3)),
        completion: CompletionTimeState(
          targetEpochMs: target.millisecondsSinceEpoch,
        ),
      );

      await tester.fling(
        find.byType(FlashPointsChipRow),
        const Offset(-300, 0),
        800,
      );
      await tester.pump();

      expect(find.text('残45分フラッシュ'), findsOneWidget);
      expect(find.text('残120分フラッシュ'), findsNothing);

      await tester.pump(const Duration(seconds: 6));

      expect(find.text('残120分フラッシュ'), findsOneWidget);
    });
  });
}
