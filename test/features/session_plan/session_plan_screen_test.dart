import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/session_plan/session_plan_controller.dart';
import 'package:session_timer/features/session_plan/session_plan_screen.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: SessionTimerTheme.dark,
        home: const SessionPlanScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _entryJson(String id, int startMinutes, int durationMinutes) =>
    '{"id":"$id","startMinutes":$startMinutes,'
    '"durationMinutes":$durationMinutes}';

String _legacyEntryJson(String id, DateTime start, DateTime end) =>
    '{"id":"$id",'
    '"startEpochMs":${start.millisecondsSinceEpoch},'
    '"endEpochMs":${end.millisecondsSinceEpoch}}';

void _seedSessions(List<String> entriesJson) {
  SharedPreferences.setMockInitialValues({
    sessionPlanJsonKey: '[${entriesJson.join(',')}]',
  });
}

void main() {
  group('SessionPlanScreen', () {
    testWidgets(
      'renders persisted sessions sorted by start time, regardless of the '
      'order they were persisted in',
      (tester) async {
        _seedSessions([
          _entryJson('later', 19 * 60, 120),
          _entryJson('sooner', 9 * 60 + 30, 210),
        ]);

        await _pumpScreen(tester);

        final soonerY = tester.getTopLeft(find.text('9:30〜13:00')).dy;
        final laterY = tester.getTopLeft(find.text('19:00〜21:00')).dy;

        expect(soonerY, lessThan(laterY));
      },
    );

    testWidgets(
      'renders a session persisted in the legacy epoch format by its time '
      'of day only',
      (tester) async {
        final start = DateTime(2020, 3, 4, 9, 30);
        final end = DateTime(2020, 3, 4, 13);
        _seedSessions([_legacyEntryJson('legacy', start, end)]);

        await _pumpScreen(tester);

        expect(find.text('9:30〜13:00'), findsOneWidget);
      },
    );

    group('組 (session sets)', () {
      testWidgets('starts on 組1 with a chip for it', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await _pumpScreen(tester);

        expect(find.text('組1'), findsOneWidget);
        expect(find.byKey(const Key('addSessionSet')), findsOneWidget);
      });

      testWidgets('adding a named 組 switches to it, and switching back shows '
          "the first 組's sessions again", (tester) async {
        _seedSessions([_entryJson('a', 9 * 60, 60)]);
        await _pumpScreen(tester);
        expect(find.text('9:00〜10:00'), findsOneWidget);

        await tester.tap(find.byKey(const Key('addSessionSet')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('sessionSetNameField')),
          '平日',
        );
        await tester.tap(find.byKey(const Key('sessionSetNameSave')));
        await tester.pumpAndSettle();

        expect(find.text('平日'), findsOneWidget);
        expect(find.text('9:00〜10:00'), findsNothing);

        await tester.tap(find.text('組1'));
        await tester.pumpAndSettle();
        expect(find.text('9:00〜10:00'), findsOneWidget);
      });

      testWidgets('a 組 can be renamed, and a blank name cannot be saved', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        await _pumpScreen(tester);

        await tester.tap(find.byKey(const Key('sessionSetMenu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('renameSessionSet')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('sessionSetNameField')),
          '   ',
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('sessionSetNameSave')),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const Key('sessionSetNameField')),
          '土日',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sessionSetNameSave')));
        await tester.pumpAndSettle();

        expect(find.text('土日'), findsOneWidget);
        expect(find.text('組1'), findsNothing);
      });

      testWidgets('the only 組 cannot be deleted', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await _pumpScreen(tester);

        await tester.tap(find.byKey(const Key('sessionSetMenu')));
        await tester.pumpAndSettle();

        final item = tester.widget<PopupMenuItem<Object?>>(
          find.byKey(const Key('removeSessionSet')),
        );
        expect(item.enabled, isFalse);
      });

      testWidgets('deleting asks first; cancelling keeps it, confirming '
          'removes it with its sessions', (tester) async {
        _seedSessions([_entryJson('a', 9 * 60, 60)]);
        await _pumpScreen(tester);
        await tester.tap(find.byKey(const Key('addSessionSet')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sessionSetNameSave')));
        await tester.pumpAndSettle();
        expect(find.text('組2'), findsOneWidget);

        await tester.tap(find.byKey(const Key('sessionSetMenu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('removeSessionSet')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('removeSetCancel')));
        await tester.pumpAndSettle();
        expect(find.text('組2'), findsOneWidget);

        await tester.tap(find.byKey(const Key('sessionSetMenu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('removeSessionSet')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('removeSetConfirm')));
        await tester.pumpAndSettle();

        expect(find.text('組2'), findsNothing);
        expect(find.text('組1'), findsOneWidget);
        expect(find.text('9:00〜10:00'), findsOneWidget);
      });

      testWidgets('many 組 with long names scroll sideways instead of '
          'overflowing a narrow screen', (tester) async {
        SharedPreferences.setMockInitialValues({
          sessionPlanBookJsonKey: jsonEncode({
            'activeId': 'a',
            'sets': [
              for (var i = 0; i < 8; i++)
                {
                  'id': i == 0 ? 'a' : 'x$i',
                  'name': '十二文字のながい名前です',
                  'sessions': <Object>[],
                },
            ],
          }),
        });
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: SessionTimerTheme.dark,
              home: const SessionPlanScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('sessionSetMenu')), findsOneWidget);
      });

      testWidgets('現在のセッションを設定 uses only the active 組', (tester) async {
        _seedSessions([_entryJson('a', 9 * 60, 60)]);
        await _pumpScreen(tester);
        await tester.tap(find.byKey(const Key('addSessionSet')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sessionSetNameSave')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('現在のセッションを設定'));
        await tester.pump();

        // The new 組 is empty, so there is nothing to apply even though
        // 組1 has a session.
        expect(find.text('該当するセッションがありません'), findsOneWidget);
      });
    });

    testWidgets('renders a session that runs past midnight', (tester) async {
      _seedSessions([_entryJson('night', 23 * 60, 180)]);

      await _pumpScreen(tester);

      expect(find.text('23:00〜2:00'), findsOneWidget);
    });

    testWidgets(
      "tapping a row's ✕ button deletes only that session, without also "
      "triggering the row's tap-to-edit gesture",
      (tester) async {
        _seedSessions([_entryJson('s1', 9 * 60, 60)]);

        await _pumpScreen(tester);
        expect(find.text('9:00〜10:00'), findsOneWidget);

        await tester.tap(find.byKey(const Key('removeSession_s1')));
        await tester.pumpAndSettle();

        expect(find.text('9:00〜10:00'), findsNothing);
        expect(find.byType(TimePickerDialog), findsNothing);
      },
    );

    testWidgets(
      'tapping the row itself (not the ✕ button) still opens the edit '
      'time picker',
      (tester) async {
        _seedSessions([_entryJson('s1', 9 * 60, 60)]);

        await _pumpScreen(tester);
        await tester.tap(find.text('9:00〜10:00'));
        await tester.pumpAndSettle();

        expect(find.byType(TimePickerDialog), findsOneWidget);
      },
    );

    testWidgets(
      'deleting one of several sessions leaves the others, still sorted',
      (tester) async {
        _seedSessions([
          _entryJson('a', 9 * 60, 30),
          _entryJson('b', 10 * 60, 30),
          _entryJson('c', 11 * 60, 30),
        ]);

        await _pumpScreen(tester);
        expect(find.byIcon(Icons.close), findsNWidgets(3));

        // Delete the middle row specifically, not just "the first close
        // button", to prove deletion targets the tapped row's own id.
        await tester.tap(find.byKey(const Key('removeSession_b')));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.close), findsNWidgets(2));
        expect(find.text('10:00〜10:30'), findsNothing);
        final firstY = tester.getTopLeft(find.text('9:00〜9:30')).dy;
        final thirdY = tester.getTopLeft(find.text('11:00〜11:30')).dy;
        expect(firstY, lessThan(thirdY));
      },
    );

    testWidgets(
      '"現在のセッションを設定" works for a legacy session whose registered '
      'date has long passed',
      (tester) async {
        // Regression for #94: this used to report 該当するセッションがありません.
        final start = DateTime(2020, 3, 4, 9);
        final end = DateTime(2020, 3, 4, 12);
        _seedSessions([_legacyEntryJson('legacy', start, end)]);

        await _pumpScreen(tester);
        await tester.tap(find.text('現在のセッションを設定'));
        await tester.pumpAndSettle();

        expect(find.text('現在のセッションを設定しました'), findsOneWidget);
        expect(find.text('該当するセッションがありません'), findsNothing);
      },
    );

    group('per-row 適用 button (#94)', () {
      ProviderContainer containerOf(WidgetTester tester) =>
          ProviderScope.containerOf(
            tester.element(find.byType(SessionPlanScreen)),
          );

      int minutesOfDay(DateTime time) => time.hour * 60 + time.minute;

      Future<
        ({
          DateTime now,
          DateTime? completion,
          DateTime? start,
          String? startTitle,
        })
      >
      applyAndRead(
        WidgetTester tester, {
        required int startOffsetMinutes,
        required int durationMinutes,
      }) async {
        final now = DateTime.now();
        final startMinutes =
            (minutesOfDay(now) + startOffsetMinutes) % (24 * 60);
        _seedSessions([_entryJson('s1', startMinutes, durationMinutes)]);

        await _pumpScreen(tester);
        await tester.tap(find.byKey(const Key('applySession_s1')));
        await tester.pumpAndSettle();

        final container = containerOf(tester);
        final completion = container
            .read(completionTimeControllerProvider)
            .value
            ?.targetEpochMs;
        final targets = container.read(timeTargetsControllerProvider).value;
        final auto = targets?.where((t) => t.id == autoSessionTargetId);
        return (
          now: now,
          completion: completion == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(completion),
          start: auto == null || auto.isEmpty
              ? null
              : DateTime.fromMillisecondsSinceEpoch(auto.first.epochMs),
          startTitle: auto == null || auto.isEmpty ? null : auto.first.title,
        );
      }

      testWidgets('an upcoming session applies as is', (tester) async {
        final r = await applyAndRead(
          tester,
          startOffsetMinutes: 120,
          durationMinutes: 60,
        );

        expect(r.start!.isAfter(r.now), isTrue);
        expect(r.completion!.difference(r.start!), const Duration(hours: 1));
        expect(r.startTitle, 'セッション開始');
        expect(find.textContaining('適用しました'), findsOneWidget);
      });

      testWidgets('a session in progress applies with a start in the past', (
        tester,
      ) async {
        final r = await applyAndRead(
          tester,
          startOffsetMinutes: -60,
          durationMinutes: 180,
        );

        expect(r.start!.isBefore(r.now), isTrue); // 残りがマイナス
        expect(r.completion!.isAfter(r.now), isTrue);
        expect(r.completion!.difference(r.start!), const Duration(hours: 3));
      });

      testWidgets('an ended session applies to tomorrow', (tester) async {
        final r = await applyAndRead(
          tester,
          startOffsetMinutes: -300,
          durationMinutes: 60,
        );

        // Started 5h ago and lasted 1h, so the next occurrence is ~19h away.
        expect(
          r.start!.difference(r.now),
          greaterThan(const Duration(hours: 15)),
        );
        expect(r.completion!.difference(r.start!), const Duration(hours: 1));
      });

      testWidgets('applying one row leaves the others untouched and does not '
          'open the edit picker', (tester) async {
        _seedSessions([
          _entryJson('a', 9 * 60, 60),
          _entryJson('b', 13 * 60, 60),
        ]);
        await _pumpScreen(tester);

        await tester.tap(find.byKey(const Key('applySession_a')));
        await tester.pumpAndSettle();

        expect(find.byType(TimePickerDialog), findsNothing);
        expect(find.text('9:00〜10:00'), findsOneWidget);
        expect(find.text('13:00〜14:00'), findsOneWidget);
        expect(find.byIcon(Icons.close), findsNWidgets(2));
      });

      testWidgets('applying a second row replaces the auto 指定時刻 rather '
          'than adding another', (tester) async {
        _seedSessions([
          _entryJson('a', 9 * 60, 60),
          _entryJson('b', 13 * 60, 60),
        ]);
        await _pumpScreen(tester);

        await tester.tap(find.byKey(const Key('applySession_a')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('applySession_b')));
        await tester.pumpAndSettle();

        final targets = containerOf(
          tester,
        ).read(timeTargetsControllerProvider).value!;
        expect(targets.where((t) => t.id == autoSessionTargetId), hasLength(1));
        final applied = DateTime.fromMillisecondsSinceEpoch(
          targets.singleWhere((t) => t.id == autoSessionTargetId).epochMs,
        );
        expect(applied.hour, 13);
      });
    });
  });
}
