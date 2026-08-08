import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/settings/settings_gear_button.dart';
import 'package:session_timer/features/settings/settings_sheet_widgets.dart';

Future<void> _pumpAndOpenSheet(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: SessionTimerTheme.dark,
      home: const Scaffold(body: SettingsGearButton()),
    ),
  );
  await tester.tap(find.byIcon(Icons.settings));
  await tester.pumpAndSettle();
}

void main() {
  group('SettingsSheet', () {
    testWidgets('gear button opens the sheet with all four sections', (
      tester,
    ) async {
      await _pumpAndOpenSheet(tester);

      expect(find.text('完了◯分前フラッシュ'), findsOneWidget);
      expect(find.text('通知'), findsOneWidget);
      expect(find.text('おまけ：週末（マイルストーン）'), findsOneWidget);
      expect(find.text('おまけ：時刻同期（NTP風）'), findsOneWidget);
    });

    testWidgets('shows the default flash points', (tester) async {
      await _pumpAndOpenSheet(tester);

      expect(find.text('残り 10 分'), findsOneWidget);
      expect(find.text('残り 5 分'), findsOneWidget);
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

    testWidgets('removing a flash point drops it from the list', (
      tester,
    ) async {
      await _pumpAndOpenSheet(tester);
      expect(find.text('残り 10 分'), findsOneWidget);

      await tester.tap(find.text('削除').first);
      await tester.pumpAndSettle();

      expect(find.text('残り 10 分'), findsNothing);
    });

    testWidgets('notify switch toggles without touching real state', (
      tester,
    ) async {
      await _pumpAndOpenSheet(tester);
      final switchFinder = find.byType(Switch);
      expect(tester.widget<Switch>(switchFinder).value, isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(switchFinder).value, isTrue);
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

      final milestoneItem = find.ancestor(
        of: find.textContaining('週末テスト'),
        matching: find.byType(SettingsListItem),
      );
      await tester.tap(
        find.descendant(of: milestoneItem, matching: find.text('削除')),
      );
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

      expect(find.text('通知'), findsNothing);
    });
  });
}
