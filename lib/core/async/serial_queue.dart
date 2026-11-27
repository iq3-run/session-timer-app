/// Runs async tasks one at a time, in the order they were queued.
///
/// A task starts only after every task queued before it has finished, so
/// read-modify-write sequences and cancel-then-rebuild sequences can't
/// interleave. A failing task fails only its own [run] future; the queue
/// itself keeps going, and the error does not surface as an unhandled
/// rejection on the internal chain.
class SerialQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
