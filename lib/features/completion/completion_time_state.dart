class CompletionTimeState {
  const CompletionTimeState({this.targetEpochMs});

  final int? targetEpochMs;

  DateTime? get targetTime => targetEpochMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(targetEpochMs!);
}
