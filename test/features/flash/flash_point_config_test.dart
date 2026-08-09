import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/flash/flash_point_config.dart';

void main() {
  group('FlashPointConfig', () {
    test('toJson/tryFromJson round-trip', () {
      const point = FlashPointConfig(
        minutes: 10,
        flashEnabled: false,
        notifyEnabled: false,
      );

      final decoded = FlashPointConfig.tryFromJson(point.toJson());

      expect(decoded?.minutes, 10);
      expect(decoded?.flashEnabled, isFalse);
      expect(decoded?.notifyEnabled, isFalse);
    });

    test('tryFromJson rejects a non-positive minutes value', () {
      expect(
        FlashPointConfig.tryFromJson({
          'minutes': 0,
          'flashEnabled': true,
          'notifyEnabled': true,
        }),
        isNull,
      );
    });

    test('tryFromJson rejects a missing or wrong-typed field', () {
      expect(FlashPointConfig.tryFromJson({'minutes': 10}), isNull);
      expect(
        FlashPointConfig.tryFromJson({
          'minutes': '10',
          'flashEnabled': true,
          'notifyEnabled': true,
        }),
        isNull,
      );
    });

    test('copyWith(flashEnabled: false) also forces notifyEnabled off', () {
      const point = FlashPointConfig(minutes: 5);

      final updated = point.copyWith(flashEnabled: false);

      expect(updated.flashEnabled, isFalse);
      expect(updated.notifyEnabled, isFalse);
    });

    test(
      'copyWith(flashEnabled: false, notifyEnabled: true) still forces '
      'notifyEnabled off — flashEnabled wins',
      () {
        const point = FlashPointConfig(minutes: 5);

        final updated = point.copyWith(
          flashEnabled: false,
          notifyEnabled: true,
        );

        expect(updated.notifyEnabled, isFalse);
      },
    );

    test(
      'copyWith(notifyEnabled: ...) alone leaves flashEnabled untouched',
      () {
        const point = FlashPointConfig(minutes: 5);

        final updated = point.copyWith(notifyEnabled: false);

        expect(updated.flashEnabled, isTrue);
        expect(updated.notifyEnabled, isFalse);
      },
    );

    test('copyWith with no arguments returns an equivalent config', () {
      const point = FlashPointConfig(
        minutes: 5,
        flashEnabled: false,
        notifyEnabled: false,
      );

      final updated = point.copyWith();

      expect(updated.minutes, point.minutes);
      expect(updated.flashEnabled, point.flashEnabled);
      expect(updated.notifyEnabled, point.notifyEnabled);
    });
  });
}
