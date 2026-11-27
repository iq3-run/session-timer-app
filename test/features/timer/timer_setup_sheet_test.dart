import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/features/timer/timer_setup_sheet.dart';
import 'package:session_timer/features/timer/timer_state.dart';

Future<TimerSetupResult?> _openSheet(
  WidgetTester tester,
  Future<void> Function() interact,
) async {
  TimerSetupResult? result;
  // The sheet is about 312px tall and a modal bottom sheet may use only 9/16
  // of the screen, so the default 600px-high test surface overflows it.
  tester.view
    ..physicalSize = const Size(800, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showModalBottomSheet<TimerSetupResult>(
                context: context,
                builder: (context) => const TimerSetupSheet(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await interact();
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('starts a normal 5 minute timer by default', (tester) async {
    final result = await _openSheet(tester, () async {
      await tester.tap(find.text('この設定でスタート'));
    });

    expect(result?.mode, TimerMode.normal);
    expect(result?.duration, const Duration(minutes: 5));
  });

  testWidgets('returns the linked mode once it is selected', (tester) async {
    final result = await _openSheet(tester, () async {
      await tester.tap(find.text('連動タイマー'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この設定でスタート'));
    });

    expect(result?.mode, TimerMode.linked);
  });

  testWidgets('dismissing the sheet returns nothing', (tester) async {
    final result = await _openSheet(tester, () async {
      await tester.tapAt(const Offset(10, 10));
    });

    expect(result, isNull);
  });
}
