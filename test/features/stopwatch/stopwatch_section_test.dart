import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/stopwatch/stopwatch_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(stopwatchControllerProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StopwatchSection())),
      ),
    );
    return container;
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('adjustStopwatch')));
    await tester.pumpAndSettle();
  }

  testWidgets('adjusting sets the elapsed time of a paused stopwatch', (
    tester,
  ) async {
    final container = await pump(tester);
    await openDialog(tester);

    await tester.enterText(find.byKey(const Key('adjustMinutes')), '3');
    await tester.enterText(find.byKey(const Key('adjustSeconds')), '0');
    await tester.tap(find.byKey(const Key('adjustConfirm')));
    await tester.pumpAndSettle();

    final state = container.read(stopwatchControllerProvider).value!;
    expect(state.accumulatedMs, 180000);
    expect(find.text('03:00.0'), findsOneWidget);
  });

  testWidgets('cancel leaves the stopwatch untouched', (tester) async {
    final container = await pump(tester);
    await openDialog(tester);

    await tester.enterText(find.byKey(const Key('adjustMinutes')), '9');
    await tester.tap(find.byKey(const Key('adjustCancel')));
    await tester.pumpAndSettle();

    expect(container.read(stopwatchControllerProvider).value!.accumulatedMs, 0);
  });

  testWidgets('invalid input shows an error and keeps the dialog open', (
    tester,
  ) async {
    final container = await pump(tester);
    await openDialog(tester);

    await tester.enterText(find.byKey(const Key('adjustSeconds')), '75');
    await tester.tap(find.byKey(const Key('adjustConfirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adjustConfirm')), findsOneWidget);
    expect(find.textContaining('整数で入力'), findsOneWidget);
    expect(container.read(stopwatchControllerProvider).value!.accumulatedMs, 0);
  });

  testWidgets('the dialog is prefilled with the current elapsed time', (
    tester,
  ) async {
    final container = await pump(tester);
    await container
        .read(stopwatchControllerProvider.notifier)
        .setElapsed(const Duration(minutes: 2, seconds: 30));
    await tester.pump();
    await openDialog(tester);

    expect(find.widgetWithText(TextField, '2'), findsOneWidget);
    expect(find.widgetWithText(TextField, '30'), findsOneWidget);
  });
}
