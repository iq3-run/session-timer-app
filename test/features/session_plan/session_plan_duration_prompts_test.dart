import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/features/session_plan/session_plan_duration_prompts.dart';

void main() {
  test('minutesOfTimeOfDay counts minutes since midnight', () {
    expect(minutesOfTimeOfDay(const TimeOfDay(hour: 0, minute: 0)), 0);
    expect(minutesOfTimeOfDay(const TimeOfDay(hour: 9, minute: 30)), 570);
    expect(minutesOfTimeOfDay(const TimeOfDay(hour: 23, minute: 59)), 1439);
  });

  test('timeOfDayFromMinutes is the inverse of minutesOfTimeOfDay', () {
    for (final minutes in [0, 1, 59, 60, 570, 1439]) {
      expect(minutesOfTimeOfDay(timeOfDayFromMinutes(minutes)), minutes);
    }
    expect(
      timeOfDayFromMinutes(570),
      const TimeOfDay(hour: 9, minute: 30),
    );
  });
}
