import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/settings/settings_gear_button.dart';
import 'package:session_timer/features/settings/settings_sheet_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpAndOpenSheet(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: SessionTimerTheme.dark,
        home: const Scaffold(body: SettingsGearButton()),
      ),
    ),
  );
  await tester.tap(find.byIcon(Icons.settings));
  await tester.pumpAndSettle();
}

/// Finds the `削除` button inside the `SettingsListItem` whose label
/// contains [text] — needed once a section has more than one deletable
/// row, since a bare `find.text('削除')` would be ambiguous. Used for the
/// milestone section, which still uses the shared `SettingsListItem`.
Finder _deleteButtonFor(String text) {
  final item = find.ancestor(
    of: find.textContaining(text),
    matching: find.byType(SettingsListItem),
  );
  return find.descendant(of: item, matching: find.text('削除'));
}

void main() {
  group('SettingsSheet', () {
    testWidgets('gear button opens the sheet with all three sections', (
      tester,
    ) async {
      await _pumpAndOpenSheet(tester);

      expect(find.text('完了◯分前フラッシュ'), findsOneWidget);
      expect(find.text('おまけ：週末（マイルストーン）'), findsOneWidget);
      expect(find.text('おまけ：時刻同期（NTP風）'), findsOneWidget);
    });

    testWidgets('seeds the default 12 flash points on first launch', (
      tester,
    ) async {
      await _pumpAndOpenSheet(tester);

      expect(find.text('残り 120 分'), findsOneWidget);
      expect(find.text('残り 10 分'), findsOneWidget);
      expect(find.text('残り 1 分'), findsOneWidget);
    });

    testWidgets('adding a flash point inserts it into the list', (
      tester,
    ) async {
      await _pumpAndOpenSheet(tester);

      await tester.enterText(find.byKey(const Key('flashMinutesField')), '7');
      await tester.tap(find.byKey(const Key('addFlashPointButton')));
      await tester.pumpAndSettle();

      expect(find.text('残り 7 分'), findsOneWidget);
    });

    testWidgets('removing a flash point drops only that point from the '
        'list', (tester) async {
      await _pumpAndOpenSheet(tester);
      expect(find.text('残り 1 分'), findsOneWidget);

      await tester.tap(find.byKey(const Key('removeFlashPoint_1')));
      await tester.pumpAndSettle();

      expect(find.text('残り 1 分'), findsNothing);
      expect(find.text('残り 120 分'), findsOneWidget);
    });

    testWidgets('flash points start with both toggles on', (tester) async {
      await _pumpAndOpenSheet(tester);

      expect(
        tester.widget<Switch>(find.byKey(const Key('flashToggle_1'))).value,
        isTrue,
      );
      expect(
        tester.widget<Switch>(find.byKey(const Key('notifyToggle_1'))).value,
        isTrue,
      );
    });

    testWidgets(
      "turning a point's flash off also forces its notify off and locks "
      'the notify switch',
      (tester) async {
        await _pumpAndOpenSheet(tester);

        await tester.tap(find.byKey(const Key('flashToggle_1')));
        await tester.pumpAndSettle();

        final notifySwitch = tester.widget<Switch>(
          find.byKey(const Key('notifyToggle_1')),
        );
        expect(notifySwitch.value, isFalse);
        expect(notifySwitch.onChanged, isNull);
      },
    );

    testWidgets(
      'turning flash back on does not automatically restore notify',
      (tester) async {
        await _pumpAndOpenSheet(tester);

        await tester.tap(find.byKey(const Key('flashToggle_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('flashToggle_1')));
        await tester.pumpAndSettle();

        final notifySwitch = tester.widget<Switch>(
          find.byKey(const Key('notifyToggle_1')),
        );
        expect(notifySwitch.value, isFalse);
        expect(notifySwitch.onChanged, isNotNull);
      },
    );

    testWidgets('toggling notify alone leaves flash on', (tester) async {
      await _pumpAndOpenSheet(tester);

      await tester.tap(find.byKey(const Key('notifyToggle_1')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Switch>(find.byKey(const Key('flashToggle_1'))).value,
        isTrue,
      );
      expect(
        tester.widget<Switch>(find.byKey(const Key('notifyToggle_1'))).value,
        isFalse,
      );
    });

    testWidgets('adding a milestone requires a picked date', (tester) async {
      await _pumpAndOpenSheet(tester);
      final itemCountBefore = find.byType(SettingsListItem).evaluate().length;

      await tester.enterText(
        find.byKey(const Key('milestoneLabelField')),
        '週末テスト',
      );
      await tester.tap(find.byKey(const Key('addMilestoneButton')));
      await tester.pumpAndSettle();

      expect(
        find.byType(SettingsListItem).evaluate().length,
        itemCountBefore,
      );
    });

    testWidgets('picking a date and adding creates a milestone entry', (
      tester,
    ) async {
      await _pumpAndOpenSheet(tester);

      await tester.enterText(
        find.byKey(const Key('milestoneLabelField')),
        '週末テスト',
      );
      await tester.tap(find.byKey(const Key('milestoneDateButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addMilestoneButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('週末テスト'), findsOneWidget);
    });

    testWidgets('removing a milestone drops it from the list', (
      tester,
    ) async {
      await _pumpAndOpenSheet(tester);

      await tester.enterText(
        find.byKey(const Key('milestoneLabelField')),
        '週末テスト',
      );
      await tester.tap(find.byKey(const Key('milestoneDateButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addMilestoneButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('週末テスト'), findsOneWidget);

      await tester.tap(_deleteButtonFor('週末テスト'));
      await tester.pumpAndSettle();

      expect(find.textContaining('週末テスト'), findsNothing);
    });

    testWidgets('ntp sync button flips the status text', (tester) async {
      await _pumpAndOpenSheet(tester);
      expect(find.text('未同期（端末時刻を使用中）'), findsOneWidget);

      await tester.tap(find.text('サーバー時刻に同期'));
      await tester.pumpAndSettle();

      expect(find.text('未同期（端末時刻を使用中）'), findsNothing);
      expect(find.text('同期は未実装です（実装予定: issue #1）'), findsOneWidget);
    });

    testWidgets('close button dismisses the sheet', (tester) async {
      await _pumpAndOpenSheet(tester);

      await tester.tap(find.byKey(const Key('closeSettingsSheetButton')));
      await tester.pumpAndSettle();

      expect(find.text('完了◯分前フラッシュ'), findsNothing);
    });
  });
}
