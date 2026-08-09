import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/completion/completion_time_state.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/flash/flash_point_config.dart';
import 'package:session_timer/features/flash/flash_points_chip_row.dart';
import 'package:session_timer/features/flash/flash_points_controller.dart';
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

class _FixedFlashPointsController extends FlashPointsController {
  _FixedFlashPointsController(this._value);
  final List<FlashPointConfig> _value;
  @override
  Future<List<FlashPointConfig>> build() async => _value;
}

class _MutableFlashPointsController extends FlashPointsController {
  _MutableFlashPointsController(this._initial);
  final List<FlashPointConfig> _initial;
  @override
  Future<List<FlashPointConfig>> build() async => _initial;

  void setPoints(List<FlashPointConfig> points) => state = AsyncData(points);
}

List<FlashPointConfig> _allEnabled(List<int> minutes) => [
  for (final m in minutes) FlashPointConfig(minutes: m),
];

Future<void> _pump(
  WidgetTester tester, {
  required DateTime now,
  CompletionTimeState completion = const CompletionTimeState(),
  Set<String> firedIds = const {},
  List<FlashPointConfig>? flashPoints,
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
        flashPointsControllerProvider.overrideWith(
          () => _FixedFlashPointsController(
            flashPoints ?? _allEnabled(defaultCompletionFlashPointsMinutes),
          ),
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

    testWidgets('renders nothing when the flash-point list is empty', (
      tester,
    ) async {
      final target = DateTime(2099, 1, 1, 12);
      await _pump(
        tester,
        now: target.subtract(const Duration(hours: 3)),
        completion: CompletionTimeState(
          targetEpochMs: target.millisecondsSinceEpoch,
        ),
        flashPoints: const [],
      );

      expect(find.byType(FlashPointsChipRow), findsOneWidget);
      expect(find.textContaining('フラッシュ'), findsNothing);
    });

    testWidgets('shows all points without paging when there are fewer than '
        'a full window', (tester) async {
      final target = DateTime(2099, 1, 1, 12);
      await _pump(
        tester,
        now: target.subtract(const Duration(hours: 3)),
        completion: CompletionTimeState(
          targetEpochMs: target.millisecondsSinceEpoch,
        ),
        flashPoints: _allEnabled(const [10, 5]),
      );

      expect(find.text('残10分フラッシュ'), findsOneWidget);
      expect(find.text('残5分フラッシュ'), findsOneWidget);
      expect(find.text('…'), findsNothing);
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

    testWidgets(
      'reclamps a swiped-to window when the point list shrinks under it, '
      'instead of rendering blank until the idle revert fires',
      (tester) async {
        final target = DateTime(2099, 1, 1, 12);
        final flashPointsController = _MutableFlashPointsController(
          _allEnabled(defaultCompletionFlashPointsMinutes),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              nowProvider.overrideWith(
                (ref) =>
                    Stream.value(target.subtract(const Duration(hours: 3))),
              ),
              completionTimeControllerProvider.overrideWith(
                () => _FixedCompletionController(
                  CompletionTimeState(
                    targetEpochMs: target.millisecondsSinceEpoch,
                  ),
                ),
              ),
              flashQueueControllerProvider.overrideWith(
                () => _FixedFlashQueueController(const {}),
              ),
              flashPointsControllerProvider.overrideWith(
                () => flashPointsController,
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(body: FlashPointsChipRow()),
            ),
          ),
        );
        await tester.pump();

        await tester.fling(
          find.byType(FlashPointsChipRow),
          const Offset(-300, 0),
          800,
        );
        await tester.pump();
        expect(find.text('残45分フラッシュ'), findsOneWidget);

        flashPointsController.setPoints(_allEnabled(const [10, 5, 1]));
        await tester.pump();

        expect(find.text('残10分フラッシュ'), findsOneWidget);
        expect(find.text('残5分フラッシュ'), findsOneWidget);
        expect(find.text('残1分フラッシュ'), findsOneWidget);
      },
    );

    testWidgets('hides a point whose flash is off, but keeps one whose only '
        'notify is off', (tester) async {
      final target = DateTime(2099, 1, 1, 12);
      await _pump(
        tester,
        now: target.subtract(const Duration(hours: 3)),
        completion: CompletionTimeState(
          targetEpochMs: target.millisecondsSinceEpoch,
        ),
        flashPoints: const [
          FlashPointConfig(minutes: 10, flashEnabled: false),
          FlashPointConfig(minutes: 5, notifyEnabled: false),
        ],
      );

      expect(find.text('残10分フラッシュ'), findsNothing);
      expect(find.text('残5分フラッシュ'), findsOneWidget);
    });
  });
}
