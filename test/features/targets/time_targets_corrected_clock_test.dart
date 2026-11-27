import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/home_widget/next_time_target.dart';
import 'package:session_timer/features/targets/time_target.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A moment 30s ahead of the device clock has already passed once the
// NTP-corrected clock runs 60s ahead of it.
const _offsetMs = 60000;

ProviderContainer _container({required int offsetMs}) {
  final container = ProviderContainer(
    overrides: [ntpOffsetMsProvider.overrideWithValue(offsetMs)],
  );
  addTearDown(container.dispose);
  return container;
}

int _soonEpochMs() =>
    DateTime.now().add(const Duration(seconds: 30)).millisecondsSinceEpoch;

void main() {
  group('absolute times use the NTP-corrected clock', () {
    test('a stored time target that has passed by the corrected clock is '
        'dropped on load', () async {
      SharedPreferences.setMockInitialValues({
        timeTargetsJsonKey: jsonEncode([
          TimeTarget(id: 't', epochMs: _soonEpochMs()).toJson(),
        ]),
      });

      final targets = await _container(
        offsetMs: _offsetMs,
      ).read(timeTargetsControllerProvider.future);

      expect(targets, isEmpty);
    });

    test(
      'the same target is kept while the device clock is accurate',
      () async {
        SharedPreferences.setMockInitialValues({
          timeTargetsJsonKey: jsonEncode([
            TimeTarget(id: 't', epochMs: _soonEpochMs()).toJson(),
          ]),
        });

        final targets = await _container(
          offsetMs: 0,
        ).read(timeTargetsControllerProvider.future);

        expect(targets, hasLength(1));
      },
    );

    test('a stored completion time that has passed by the corrected clock '
        'is cleared on load', () async {
      SharedPreferences.setMockInitialValues({
        completionTimeEpochMsKey: _soonEpochMs(),
      });

      final state = await _container(
        offsetMs: _offsetMs,
      ).read(completionTimeControllerProvider.future);

      expect(state.targetEpochMs, isNull);
    });

    test('the next time target skips one that has passed by the corrected '
        'clock', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _container(offsetMs: _offsetMs);
      await container.read(timeTargetsControllerProvider.future);
      final notifier = container.read(timeTargetsControllerProvider.notifier);
      // Added after the load, so only the corrected clock can rule it out.
      await notifier.upsertTarget(
        'soon',
        DateTime.now().add(const Duration(seconds: 30)),
      );
      await notifier.upsertTarget(
        'later',
        DateTime.now().add(const Duration(minutes: 10)),
      );

      expect(container.read(nextTimeTargetProvider)?.id, 'later');
    });
  });
}
