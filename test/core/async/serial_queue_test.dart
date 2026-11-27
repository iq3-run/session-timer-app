import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/async/serial_queue.dart';

void main() {
  test('runs tasks one at a time, in queued order', () async {
    final queue = SerialQueue();
    final log = <String>[];
    final gate = Completer<void>();

    final first = queue.run(() async {
      log.add('first:start');
      await gate.future;
      log.add('first:end');
    });
    final second = queue.run(() async => log.add('second'));

    await Future<void>.delayed(Duration.zero);
    expect(log, ['first:start']);

    gate.complete();
    await Future.wait([first, second]);
    expect(log, ['first:start', 'first:end', 'second']);
  });

  test('returns the task result', () async {
    expect(await SerialQueue().run(() async => 42), 42);
  });

  test(
    'a failing task fails only its own future; later tasks still run',
    () async {
      final queue = SerialQueue();
      final failing = queue.run<void>(() async => throw StateError('boom'));
      final after = queue.run(() async => 'ok');

      await expectLater(failing, throwsStateError);
      expect(await after, 'ok');
    },
  );

  test('a failing task does not raise an uncaught error in the zone', () async {
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      final queue = SerialQueue();
      await queue
          .run<void>(() async => throw StateError('boom'))
          .then(
            (_) {},
            onError: (Object _) {},
          );
      await queue.run(() async {});
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => uncaught.add(error));

    expect(uncaught, isEmpty);
  });
}
