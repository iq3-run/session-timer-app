import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/app.dart';

void main() {
  group('resolveDeviceLocale', () {
    test(
      'picks the first (most preferred) device locale when it is '
      'supported',
      () {
        final resolved = resolveDeviceLocale(
          [const Locale('fr'), const Locale('en'), const Locale('ja')],
          const [Locale('ja'), Locale('en')],
        );

        expect(resolved, const Locale('fr'));
      },
    );

    test(
      'skips device locales flutter_localizations has no translation for',
      () {
        final resolved = resolveDeviceLocale(
          [const Locale('xx'), const Locale('en')],
          const [Locale('ja'), Locale('en')],
        );

        expect(resolved, const Locale('en'));
      },
    );

    test('falls back to Japanese when no device locale is supported', () {
      final resolved = resolveDeviceLocale(
        [const Locale('xx'), const Locale('yy')],
        const [Locale('ja'), Locale('en')],
      );

      expect(resolved, const Locale('ja'));
    });

    test('falls back to Japanese when the device locale list is null', () {
      final resolved = resolveDeviceLocale(null, const [Locale('ja')]);

      expect(resolved, const Locale('ja'));
    });
  });
}
