/// A single 完了◯分前 flash point plus its own flash/notify toggles.
class FlashPointConfig {
  /// A point never notifies without also flashing — enforced here (not just
  /// in [copyWith]) so a value built straight from persisted JSON via
  /// [tryFromJson] can't smuggle in `flashEnabled: false, notifyEnabled:
  /// true`.
  const FlashPointConfig({
    required this.minutes,
    this.flashEnabled = true,
    bool notifyEnabled = true,
  }) : notifyEnabled = flashEnabled && notifyEnabled;

  /// Null if [json] doesn't match the expected shape — mirrors
  /// `TimeTarget.tryFromJson`'s "one bad entry doesn't take down the whole
  /// persisted list" approach.
  static FlashPointConfig? tryFromJson(Map<String, dynamic> json) {
    final minutes = json['minutes'];
    final flashEnabled = json['flashEnabled'];
    final notifyEnabled = json['notifyEnabled'];
    if (minutes is! int || minutes <= 0) return null;
    if (flashEnabled is! bool || notifyEnabled is! bool) return null;
    return FlashPointConfig(
      minutes: minutes,
      flashEnabled: flashEnabled,
      notifyEnabled: notifyEnabled,
    );
  }

  final int minutes;
  final bool flashEnabled;
  final bool notifyEnabled;

  Map<String, dynamic> toJson() => {
    'minutes': minutes,
    'flashEnabled': flashEnabled,
    'notifyEnabled': notifyEnabled,
  };

  FlashPointConfig copyWith({bool? flashEnabled, bool? notifyEnabled}) {
    return FlashPointConfig(
      minutes: minutes,
      flashEnabled: flashEnabled ?? this.flashEnabled,
      notifyEnabled: notifyEnabled ?? this.notifyEnabled,
    );
  }
}
