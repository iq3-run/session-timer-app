import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/persistence/persistence_error_snack_bar.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
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

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  // No automatic retry: a failed load is otherwise retried (and shown as
  // "loading") for several seconds before the error is published.
  final container = ProviderContainer(
    overrides: overrides,
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: PersistenceErrorSnackBar(child: Scaffold(body: SizedBox())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('says nothing while everything loads and saves', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final container = await _pump(tester);
    await container
        .read(sessionPlanControllerProvider.notifier)
        .addSession(startMinutes: 600, durationMinutes: 60);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('tells the user when a save fails', (tester) async {
    final previousStore = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previousStore);
    SharedPreferences.setMockInitialValues({});
    final store = _FlakyStore.empty();
    SharedPreferencesStorePlatform.instance = store;
    final container = await _pump(tester);
    final notifier = container.read(sessionPlanControllerProvider.notifier);
    await notifier.addSession(startMinutes: 600, durationMinutes: 60);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    store.failWrites = true;
    await notifier.addSession(startMinutes: 700, durationMinutes: 60);
    await tester.pumpAndSettle();

    expect(find.text(saveFailedMessage), findsOneWidget);
  });

  testWidgets('a second failure shows a fresh message', (tester) async {
    final previousStore = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previousStore);
    SharedPreferences.setMockInitialValues({});
    final store = _FlakyStore.empty();
    SharedPreferencesStorePlatform.instance = store;
    final container = await _pump(tester);
    final notifier = container.read(sessionPlanControllerProvider.notifier);
    store.failWrites = true;

    await notifier.addSession(startMinutes: 600, durationMinutes: 60);
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold)),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    await notifier.addSession(startMinutes: 700, durationMinutes: 60);
    await tester.pumpAndSettle();

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
}
