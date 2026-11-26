import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:session_timer/features/schedule/session_schedule_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpScreen(
  WidgetTester tester, {
  Map<String, Object> initialValues = const {},
  Size surfaceSize = const Size(1000, 1400),
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: SessionTimerTheme.dark,
        home: const SessionScheduleSettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pickDateAndAdd(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('scheduleDateButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('addScheduleEventButton')));
  await tester.pumpAndSettle();
}

void main() {
  group('SessionScheduleSettingsScreen', () {
    testWidgets('the add button stays disabled until a date is picked', (
      tester,
    ) async {
      await _pumpScreen(tester);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('addScheduleEventButton')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'picking a date and adding creates a row labeled 1WE (the default '
      'type)',
      (tester) async {
        await _pumpScreen(tester);

        await _pickDateAndAdd(tester);

        expect(find.text('1WE'), findsOneWidget);
      },
    );

    testWidgets('deleting a row removes it from the list', (tester) async {
      await _pumpScreen(tester);
      await _pickDateAndAdd(tester);
      expect(find.text('1WE'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('1WE'), findsNothing);
    });

    group('delete all', () {
      Map<String, Object> seeded(List<SessionEvent> events) => {
        sessionEventsJsonKey: jsonEncode([for (final e in events) e.toJson()]),
      };

      final twoEvents = [
        SessionEvent(
          id: 'a',
          type: SessionEventType.weekend,
          date: DateTime(2026, 8, 21),
        ),
        SessionEvent(
          id: 'b',
          type: SessionEventType.workday,
          date: DateTime(2026, 9, 5),
        ),
      ];

      testWidgets('the delete-all button is disabled when nothing is '
          'registered', (tester) async {
        await _pumpScreen(tester);

        final button = tester.widget<IconButton>(
          find.byKey(const Key('deleteAllScheduleEvents')),
        );
        expect(button.onPressed, isNull);
      });

      testWidgets('asks for confirmation, stating the count, before '
          'deleting', (tester) async {
        await _pumpScreen(tester, initialValues: seeded(twoEvents));

        await tester.tap(find.byKey(const Key('deleteAllScheduleEvents')));
        await tester.pumpAndSettle();

        expect(find.text('すべての日程を削除'), findsOneWidget);
        expect(find.textContaining('2件'), findsOneWidget);
        // Nothing is deleted just by opening the dialog.
        expect(find.text('1WE'), findsOneWidget);
        expect(find.text('1WD'), findsOneWidget);
      });

      testWidgets('cancelling keeps every event', (tester) async {
        await _pumpScreen(tester, initialValues: seeded(twoEvents));

        await tester.tap(find.byKey(const Key('deleteAllScheduleEvents')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('deleteAllCancel')));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('1WE'), findsOneWidget);
        expect(find.text('1WD'), findsOneWidget);
      });

      testWidgets('dismissing the dialog without choosing keeps every '
          'event', (tester) async {
        await _pumpScreen(tester, initialValues: seeded(twoEvents));

        await tester.tap(find.byKey(const Key('deleteAllScheduleEvents')));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5)); // the barrier
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('1WE'), findsOneWidget);
        expect(find.text('1WD'), findsOneWidget);
      });

      testWidgets('confirming removes every event', (tester) async {
        await _pumpScreen(tester, initialValues: seeded(twoEvents));

        await tester.tap(find.byKey(const Key('deleteAllScheduleEvents')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('deleteAllConfirm')));
        await tester.pumpAndSettle();

        expect(find.text('1WE'), findsNothing);
        expect(find.text('1WD'), findsNothing);
        expect(find.text('登録されている日程はありません'), findsOneWidget);
        final button = tester.widget<IconButton>(
          find.byKey(const Key('deleteAllScheduleEvents')),
        );
        expect(button.onPressed, isNull);
      });
    });

    testWidgets('shows every registered CR, not just today/next', (
      tester,
    ) async {
      final events = [
        SessionEvent(
          id: 'cr-past',
          type: SessionEventType.classroom,
          date: DateTime(2020),
        ),
        SessionEvent(
          id: 'cr-future',
          type: SessionEventType.classroom,
          date: DateTime(2030),
        ),
      ];
      await _pumpScreen(
        tester,
        initialValues: {
          sessionEventsJsonKey: jsonEncode(
            events.map((e) => e.toJson()).toList(),
          ),
        },
      );

      expect(find.text('CR'), findsNWidgets(2));
    });

    testWidgets(
      'a WD row has a visibility toggle, defaulting to on, absent for '
      '1WE/CS/CR',
      (tester) async {
        final events = [
          SessionEvent(
            id: 'we1',
            type: SessionEventType.weekend,
            date: DateTime(2026, 8, 21),
          ),
          SessionEvent(
            id: 'wd1',
            type: SessionEventType.workday,
            date: DateTime(2026, 9, 5),
          ),
          SessionEvent(
            id: 'cs',
            type: SessionEventType.completion,
            date: DateTime(2027, 6, 25),
          ),
          SessionEvent(
            id: 'cr',
            type: SessionEventType.classroom,
            date: DateTime(2026, 9, 18),
          ),
        ];
        await _pumpScreen(
          tester,
          initialValues: {
            sessionEventsJsonKey: jsonEncode(
              events.map((e) => e.toJson()).toList(),
            ),
          },
        );

        expect(
          tester
              .widget<Switch>(find.byKey(const Key('visibilityToggle_wd1')))
              .value,
          isTrue,
        );
        expect(find.byKey(const Key('visibilityToggle_we1')), findsNothing);
        expect(find.byKey(const Key('visibilityToggle_cs')), findsNothing);
        expect(find.byKey(const Key('visibilityToggle_cr')), findsNothing);
        expect(find.text('常に表示'), findsNWidgets(3));
      },
    );

    testWidgets('toggling a WD row off flips the switch to off', (
      tester,
    ) async {
      final events = [
        SessionEvent(
          id: 'wd1',
          type: SessionEventType.workday,
          date: DateTime(2026, 9, 5),
        ),
      ];
      await _pumpScreen(
        tester,
        initialValues: {
          sessionEventsJsonKey: jsonEncode(
            events.map((e) => e.toJson()).toList(),
          ),
        },
      );

      await tester.tap(find.byKey(const Key('visibilityToggle_wd1')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Switch>(find.byKey(const Key('visibilityToggle_wd1')))
            .value,
        isFalse,
      );
    });

    testWidgets(
      'the manual number field shows for WE (the default type) and hides '
      'for OR',
      (tester) async {
        await _pumpScreen(tester);

        expect(
          find.byKey(const Key('scheduleManualNumberField')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('scheduleTypeDropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('オリエンテーション(OR)').last);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('scheduleManualNumberField')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'the add button disables when the manual number is non-empty but '
      'invalid',
      (tester) async {
        await _pumpScreen(tester);
        await tester.tap(find.byKey(const Key('scheduleDateButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('scheduleManualNumberField')),
          '0',
        );
        await tester.pumpAndSettle();

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('addScheduleEventButton')),
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets('adding with a manual number uses it as the label', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.tap(find.byKey(const Key('scheduleDateButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('scheduleManualNumberField')),
        '7',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('addScheduleEventButton')));
      await tester.pumpAndSettle();

      expect(find.text('7WE'), findsOneWidget);
      expect(find.text('1WE'), findsNothing);
    });

    testWidgets(
      "tapping a WE row's number opens an editor; saving a new number "
      'updates the label',
      (tester) async {
        final events = [
          SessionEvent(
            id: 'we1',
            type: SessionEventType.weekend,
            date: DateTime(2026, 8, 21),
          ),
        ];
        await _pumpScreen(
          tester,
          initialValues: {
            sessionEventsJsonKey: jsonEncode(
              events.map((e) => e.toJson()).toList(),
            ),
          },
        );
        expect(find.text('1WE'), findsOneWidget);

        await tester.tap(find.byKey(const Key('editNumber_we1')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('manualNumberDialogField')),
          '4',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('manualNumberDialogSave')));
        await tester.pumpAndSettle();

        expect(find.text('4WE'), findsOneWidget);
        expect(find.text('1WE'), findsNothing);
      },
    );

    testWidgets(
      "a WE row's number opens the editor via keyboard focus + Enter, not "
      'just tap',
      (tester) async {
        final events = [
          SessionEvent(
            id: 'we1',
            type: SessionEventType.weekend,
            date: DateTime(2026, 8, 21),
          ),
        ];
        await _pumpScreen(
          tester,
          initialValues: {
            sessionEventsJsonKey: jsonEncode(
              events.map((e) => e.toJson()).toList(),
            ),
          },
        );

        // Focus.of walks upward from the given context, so it must start
        // from a descendant of the InkWell (its Text child) — the InkWell's
        // own context is the Focus widget's ancestor, not a descendant of
        // it, and wouldn't find it.
        final element = tester.element(find.text('1WE'));
        Focus.of(element).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('manualNumberDialogField')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'saving an empty number in the editor reverts to the auto-assigned '
      'number',
      (tester) async {
        final events = [
          SessionEvent(
            id: 'we1',
            type: SessionEventType.weekend,
            date: DateTime(2026, 8, 21),
            manualNumber: 4,
          ),
        ];
        await _pumpScreen(
          tester,
          initialValues: {
            sessionEventsJsonKey: jsonEncode(
              events.map((e) => e.toJson()).toList(),
            ),
          },
        );
        expect(find.text('4WE'), findsOneWidget);

        await tester.tap(find.byKey(const Key('editNumber_we1')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('manualNumberDialogField')),
          '',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('manualNumberDialogSave')));
        await tester.pumpAndSettle();

        expect(find.text('1WE'), findsOneWidget);
      },
    );

    testWidgets(
      'the manual-number save button disables for an invalid entry',
      (tester) async {
        final events = [
          SessionEvent(
            id: 'we1',
            type: SessionEventType.weekend,
            date: DateTime(2026, 8, 21),
          ),
        ];
        await _pumpScreen(
          tester,
          initialValues: {
            sessionEventsJsonKey: jsonEncode(
              events.map((e) => e.toJson()).toList(),
            ),
          },
        );

        await tester.tap(find.byKey(const Key('editNumber_we1')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('manualNumberDialogField')),
          'abc',
        );
        await tester.pumpAndSettle();

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('manualNumberDialogSave')),
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets(
      "tapping a row's date opens a picker pre-selected to its current "
      'date; confirming updates it',
      (tester) async {
        final events = [
          SessionEvent(
            id: 'we1',
            type: SessionEventType.weekend,
            date: DateTime(2026, 8, 21),
          ),
        ];
        await _pumpScreen(
          tester,
          initialValues: {
            sessionEventsJsonKey: jsonEncode(
              events.map((e) => e.toJson()).toList(),
            ),
          },
        );
        expect(find.text('8/21(金)'), findsOneWidget);

        await tester.tap(find.byKey(const Key('editDate_we1')));
        await tester.pumpAndSettle();

        final picker = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        expect(picker.initialDate, DateTime(2026, 8, 21));

        await tester.tap(find.text('22'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(find.text('8/22(土)'), findsOneWidget);
        expect(find.text('8/21(金)'), findsNothing);
      },
    );

    testWidgets('OR/CR/CS numbers are not tappable', (tester) async {
      final events = [
        SessionEvent(
          id: 'or',
          type: SessionEventType.orientation,
          date: DateTime(2026, 8, 7),
        ),
        SessionEvent(
          id: 'cr',
          type: SessionEventType.classroom,
          date: DateTime(2026, 9, 18),
        ),
        SessionEvent(
          id: 'cs',
          type: SessionEventType.completion,
          date: DateTime(2027, 6, 25),
        ),
      ];
      await _pumpScreen(
        tester,
        initialValues: {
          sessionEventsJsonKey: jsonEncode(
            events.map((e) => e.toJson()).toList(),
          ),
        },
      );

      expect(find.byKey(const Key('editNumber_or')), findsNothing);
      expect(find.byKey(const Key('editNumber_cr')), findsNothing);
      expect(find.byKey(const Key('editNumber_cs')), findsNothing);
    });
  });

  group('A/B schedule selector', () {
    Future<void> chooseType(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const Key('scheduleTypeDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    final selector = find.byKey(const Key('scheduleTrackSelector'));

    testWidgets('shows for WE (the default) and WD, but not other types', (
      tester,
    ) async {
      await _pumpScreen(tester);
      expect(selector, findsOneWidget);

      await chooseType(tester, 'ワークデー(WD)');
      expect(selector, findsOneWidget);

      for (final name in [
        'オリエンテーション(OR)',
        'クラスルーム(CR)',
        '特別セッション(SS)',
        '完了セッション(CS)',
      ]) {
        await chooseType(tester, name);
        expect(selector, findsNothing, reason: name);
      }
    });

    testWidgets('starts on 共通, so a plain add stays a plain 1WE', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await _pickDateAndAdd(tester);

      expect(find.text('1WE'), findsOneWidget);
    });

    testWidgets('adding as A and as B gives 1WE(A) and 1WE(B)', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.descendant(of: selector, matching: find.text('A')));
      await tester.pumpAndSettle();
      await _pickDateAndAdd(tester);
      await tester.tap(find.descendant(of: selector, matching: find.text('B')));
      await tester.pumpAndSettle();
      await _pickDateAndAdd(tester);

      expect(find.text('1WE(A)'), findsOneWidget);
      expect(find.text('1WE(B)'), findsOneWidget);
    });

    testWidgets('goes back to 共通 after each add, so it is not carried over', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await tester.tap(find.descendant(of: selector, matching: find.text('A')));
      await tester.pumpAndSettle();
      await _pickDateAndAdd(tester);
      // No selector change: this one must be common, not A again.
      await _pickDateAndAdd(tester);

      expect(find.text('1WE(A)'), findsOneWidget);
      expect(find.text('2WE'), findsOneWidget);
    });

    testWidgets('a leftover A/B choice is dropped when the type changes', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.tap(find.descendant(of: selector, matching: find.text('A')));
      await tester.pumpAndSettle();

      await chooseType(tester, 'クラスルーム(CR)');
      await chooseType(tester, '週末(WE)');
      await _pickDateAndAdd(tester);

      expect(find.text('1WE'), findsOneWidget);
      expect(find.text('1WE(A)'), findsNothing);
    });

    testWidgets('registered A/B events show their schedule in the list', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        initialValues: {
          sessionEventsJsonKey: jsonEncode([
            SessionEvent(
              id: 'a',
              type: SessionEventType.weekend,
              date: DateTime(2026, 8, 21),
              track: SessionTrack.a,
            ).toJson(),
            SessionEvent(
              id: 'b',
              type: SessionEventType.weekend,
              date: DateTime(2026, 8, 28),
              track: SessionTrack.b,
            ).toJson(),
          ]),
        },
      );

      expect(find.text('1WE(A)'), findsOneWidget);
      expect(find.text('1WE(B)'), findsOneWidget);
    });

    testWidgets('fits a narrow portrait screen without overflowing', (
      tester,
    ) async {
      await _pumpScreen(tester, surfaceSize: const Size(360, 800));

      expect(selector, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
