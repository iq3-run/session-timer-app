import 'package:session_timer/core/clock/epoch_bounds.dart';

class TimeTarget {
  const TimeTarget({required this.id, required this.epochMs, this.title});

  /// Null if [json] doesn't match the expected shape — e.g. corrupted, from
  /// a future schema, or an out-of-range epoch — rather than throwing, so
  /// one bad entry doesn't take down the whole persisted list.
  static TimeTarget? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final epochMs = json['epochMs'];
    if (id is! String || epochMs is! int) return null;
    if (epochMs.abs() > maxEpochMs) return null;
    // title is genuinely nullable (absent = untitled), so unlike id/epochMs
    // an absent key is fine — only a present-but-wrong-typed value rejects
    // the whole entry.
    final rawTitle = json['title'];
    if (rawTitle != null && rawTitle is! String) return null;
    return TimeTarget(id: id, epochMs: epochMs, title: rawTitle as String?);
  }

  final String id;
  final int epochMs;

  /// Optional label shown instead of the generic "指定時刻" text and used in
  /// the flash/notification wording. `null` means untitled.
  final String? title;

  DateTime get targetTime => DateTime.fromMillisecondsSinceEpoch(epochMs);

  /// [clearTitle] exists because `title: null` alone can't distinguish "keep
  /// the current title" from "remove it" — mirrors the pattern needed for
  /// any nullable field under a merge-style copyWith.
  TimeTarget copyWith({int? epochMs, String? title, bool clearTitle = false}) {
    return TimeTarget(
      id: id,
      epochMs: epochMs ?? this.epochMs,
      title: clearTitle ? null : (title ?? this.title),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'epochMs': epochMs,
    if (title != null) 'title': title,
  };
}
