import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/persistence/persistence_error_toast.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/flash/flash_points_controller.dart';
import 'package:session_timer/features/session_plan/session_plan_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FlakyStore extends InMemorySharedPreferencesStore {
  _FlakyStore.empty() : super.empty();

  bool failWrites = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (failWrites) return Future.value(false);
    return super.setValue(valueType, key, value);
  }
}

final Finder _toast = find.byKey(const Key('persistenceErrorToast'));

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<Override> overrides = const [],
  bool retry = false,
}) async {
  final container = ProviderContainer(
    overrides: overrides,
    // No automatic retry unless asked: a failed load is otherwise retried
    // (and shown as "loading") for a while before the error is published.
    retry: retry ? null : (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) =>
            PersistenceErrorToast(child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (context) => const SizedBox(height: 200),
              ),
              child: const Text('open sheet'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

_FlakyStore _installFlakyStore() {
  final previousStore = SharedPreferencesStorePlatform.instance;
  addTearDown(() => SharedPreferencesStorePlatform.instance = previousStore);
  SharedPreferences.setMockInitialValues({});
  final store = _FlakyStore.empty();
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

void main() {
  testWidgets('says nothing while everything loads and saves', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final container = await _pump(tester);
    await container
        .read(sessionPlanControllerProvider.notifier)
        .addSession(startMinutes: 600, durationMinutes: 60);
    await tester.pumpAndSettle();

    expect(_toast, findsNothing);
  });

  testWidgets('tells the user when a save fails, then goes away on its own', (
    tester,
  ) async {
    final store = _installFlakyStore();
    final container = await _pump(tester);
    final notifier = container.read(sessionPlanControllerProvider.notifier);
    await notifier.addSession(startMinutes: 600, durationMinutes: 60);
    await tester.pumpAndSettle();
    expect(_toast, findsNothing);

    store.failWrites = true;
    await notifier.addSession(startMinutes: 700, durationMinutes: 60);
    await tester.pump();
    expect(find.text(saveFailedMessage), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(_toast, findsNothing);
  });

  testWidgets('a tap dismisses it', (tester) async {
    final store = _installFlakyStore()..failWrites = true;
    final container = await _pump(tester);
    await container
        .read(sessionPlanControllerProvider.notifier)
        .addSession(startMinutes: 600, durationMinutes: 60);
    await tester.pump();
    expect(_toast, findsOneWidget);

    await tester.tap(_toast);
    await tester.pump();

    expect(_toast, findsNothing);
    expect(store.failWrites, isTrue);
  });

  testWidgets('is drawn above an open modal sheet, where a SnackBar would be '
      'hidden behind the barrier', (tester) async {
    final store = _installFlakyStore();
    final container = await _pump(tester);
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    store.failWrites = true;
    await container
        .read(sessionPlanControllerProvider.notifier)
        .addSession(startMinutes: 600, durationMinutes: 60);
    await tester.pump();

    expect(_toast.hitTestable(), findsOneWidget);
  });

  testWidgets('a second failure while the first is shown replaces it', (
    tester,
  ) async {
    final store = _installFlakyStore()..failWrites = true;
    final container = await _pump(tester);
    final notifier = container.read(sessionPlanControllerProvider.notifier);

    await notifier.addSession(startMinutes: 600, durationMinutes: 60);
    await tester.pump(const Duration(seconds: 3));
    await notifier.addSession(startMinutes: 700, durationMinutes: 60);
    await tester.pump(const Duration(seconds: 3));

    // 6s after the first failure, 3s after the second: still showing.
    expect(_toast, findsOneWidget);
    expect(store.failWrites, isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(_toast, findsNothing);
  });

  testWidgets('also covers the flash points edited in the settings sheet', (
    tester,
  ) async {
    final store = _installFlakyStore();
    final container = await _pump(tester);
    await container.read(flashPointsControllerProvider.future);
    store.failWrites = true;

    await container.read(flashPointsControllerProvider.notifier).addPoint(99);
    await tester.pump();

    expect(find.text(saveFailedMessage), findsOneWidget);
  });

  testWidgets('also covers the completion time', (tester) async {
    _installFlakyStore().failWrites = true;
    final container = await _pump(tester);
    await container.read(completionTimeControllerProvider.future);

    await container
        .read(completionTimeControllerProvider.notifier)
        .setTarget(DateTime.now().add(const Duration(hours: 1)));
    await tester.pump();

    expect(find.text(saveFailedMessage), findsOneWidget);
  });

  testWidgets('tells the user when stored data could not be loaded', (
    tester,
  ) async {
    await _pump(
      tester,
      overrides: [
        sharedPreferencesProvider.overrideWith(
          (ref) async => throw Exception('storage unavailable'),
        ),
      ],
    );

    expect(find.text(loadFailedMessage), findsOneWidget);
  });

  testWidgets('a load failure that the retry recovers from shows nothing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var attempts = 0;
    await _pump(
      tester,
      retry: true,
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async {
          attempts++;
          if (attempts == 1) throw Exception('transient');
          return SharedPreferences.getInstance();
        }),
      ],
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(attempts, greaterThan(1));
    expect(_toast, findsNothing);
  });
}
