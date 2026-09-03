import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/targets/time_target.dart';

void main() {
  group('TimeTarget', () {
    test('toJson/tryFromJson round-trips a titled target', () {
      const target = TimeTarget(id: 't1', epochMs: 1700000000000, title: '朝礼');

      final restored = TimeTarget.tryFromJson(target.toJson());

      expect(restored?.id, 't1');
      expect(restored?.epochMs, 1700000000000);
      expect(restored?.title, '朝礼');
    });

    test('toJson omits the title key when untitled', () {
      const target = TimeTarget(id: 't1', epochMs: 1700000000000);

      expect(target.toJson().containsKey('title'), isFalse);
    });

    test('tryFromJson defaults to untitled when the title key is absent', () {
      final restored = TimeTarget.tryFromJson({
        'id': 't1',
        'epochMs': 1700000000000,
      });

      expect(restored?.title, isNull);
    });

    test('tryFromJson rejects a non-String title', () {
      final restored = TimeTarget.tryFromJson({
        'id': 't1',
        'epochMs': 1700000000000,
        'title': 42,
      });

      expect(restored, isNull);
    });

    test('copyWith replaces the title while leaving epochMs untouched', () {
      const target = TimeTarget(id: 't1', epochMs: 1700000000000);

      final updated = target.copyWith(title: '朝礼');

      expect(updated.title, '朝礼');
      expect(updated.epochMs, 1700000000000);
    });

    test('copyWith without title keeps the existing one', () {
      const target = TimeTarget(id: 't1', epochMs: 1700000000000, title: '朝礼');

      final updated = target.copyWith(epochMs: 1700000001000);

      expect(updated.title, '朝礼');
    });

    test('copyWith(clearTitle: true) removes the title', () {
      const target = TimeTarget(id: 't1', epochMs: 1700000000000, title: '朝礼');

      final updated = target.copyWith(clearTitle: true);

      expect(updated.title, isNull);
    });
  });
}
