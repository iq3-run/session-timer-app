import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/targets/target_title_edit.dart';

void main() {
  group('resolveTargetTitleEdit', () {
    test(
      'a dismissed dialog (null) means keep the existing title, not clear '
      'it',
      () {
        final edit = resolveTargetTitleEdit(null);

        expect(edit.title, isNull);
        expect(edit.clearTitle, isFalse);
      },
    );

    test('confirming with blank text clears the title', () {
      final edit = resolveTargetTitleEdit('');

      expect(edit.title, isNull);
      expect(edit.clearTitle, isTrue);
    });

    test('confirming with whitespace-only text clears the title', () {
      final edit = resolveTargetTitleEdit('   ');

      expect(edit.title, isNull);
      expect(edit.clearTitle, isTrue);
    });

    test('confirming with text sets the trimmed title', () {
      final edit = resolveTargetTitleEdit('  朝礼  ');

      expect(edit.title, '朝礼');
      expect(edit.clearTitle, isFalse);
    });
  });
}
