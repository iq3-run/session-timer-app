/// A single 完了◯分前 flash point plus its own flash/notify toggles.
class FlashPointConfig {
  const FlashPointConfig({
    required this.minutes,
    this.flashEnabled = true,
    this.notifyEnabled = true,
  });

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

  /// Turning [flashEnabled] off always forces [notifyEnabled] off too — a
  /// point never notifies without also flashing — so this is the one place
  /// that constraint is enforced, rather than every call site remembering
  /// to check it.
  FlashPointConfig copyWith({bool? flashEnabled, bool? notifyEnabled}) {
    final nextFlashEnabled = flashEnabled ?? this.flashEnabled;
    return FlashPointConfig(
      minutes: minutes,
      flashEnabled: nextFlashEnabled,
      notifyEnabled: nextFlashEnabled && (notifyEnabled ?? this.notifyEnabled),
    );
  }
}
