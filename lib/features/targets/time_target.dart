class TimeTarget {
  const TimeTarget({required this.id, required this.epochMs});

  /// Null if [json] doesn't match the expected shape — e.g. corrupted or
  /// from a future schema — rather than throwing, so one bad entry doesn't
  /// take down the whole persisted list.
  static TimeTarget? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final epochMs = json['epochMs'];
    if (id is! String || epochMs is! int) return null;
    return TimeTarget(id: id, epochMs: epochMs);
  }

  final String id;
  final int epochMs;

  DateTime get targetTime => DateTime.fromMillisecondsSinceEpoch(epochMs);

  TimeTarget copyWith({int? epochMs}) {
    return TimeTarget(id: id, epochMs: epochMs ?? this.epochMs);
  }

  Map<String, dynamic> toJson() => {'id': id, 'epochMs': epochMs};
}
