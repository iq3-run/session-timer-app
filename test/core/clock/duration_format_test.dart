import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/clock/duration_format.dart';

void main() {
  group('formatElapsedTenths', () {
    test('formats zero as MM:SS.d', () {
      expect(formatElapsedTenths(Duration.zero), '00:00.0');
    });

    test('formats seconds and tenths without hours', () {
      expect(
        formatElapsedTenths(
          const Duration(minutes: 3, seconds: 7, milliseconds: 400),
        ),
        '03:07.4',
      );
    });

    test('includes hours once elapsed exceeds an hour', () {
      expect(
        formatElapsedTenths(
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 900),
        ),
        '01:02:03.9',
      );
    });
  });
}
