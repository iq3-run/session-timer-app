import 'package:session_timer/features/session_plan/session_plan_entry.dart';

/// Longest name a 組 can be given — keeps its chip readable in a narrow
/// portrait row.
const int maxSessionPlanSetNameLength = 12;

/// Id given to the 組 created from a pre-組 (single list) install.
const legacySessionPlanSetId = 'default';

/// One named "組" of the session flow, e.g. a weekend programme and a
/// weekday programme the facilitator alternates between.
class SessionPlanSet {
  const SessionPlanSet({
    required this.id,
    required this.name,
    this.sessions = const [],
  });

  /// Null if [json] doesn't match the expected shape. One bad session
  /// inside only drops that session (mirrors `SessionPlanEntry`'s own
  /// tolerance), not the whole 組.
  static SessionPlanSet? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final sessions = json['sessions'];
    if (id is! String || name is! String || sessions is! List) return null;
    return SessionPlanSet(
      id: id,
      name: name,
      sessions: sessions
          .whereType<Map<String, dynamic>>()
          .map(SessionPlanEntry.tryFromJson)
          .whereType<SessionPlanEntry>()
          .toList(),
    );
  }

  final String id;
  final String name;
  final List<SessionPlanEntry> sessions;

  SessionPlanSet copyWith({String? name, List<SessionPlanEntry>? sessions}) =>
      SessionPlanSet(
        id: id,
        name: name ?? this.name,
        sessions: sessions ?? this.sessions,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sessions': sessions.map((s) => s.toJson()).toList(),
  };
}

/// Every 組 plus which one is in use. Always holds at least one 組, so the
/// screen never has to deal with "no list to add a session to".
class SessionPlanBook {
  SessionPlanBook({required List<SessionPlanSet> sets, String? activeId})
    : assert(sets.isNotEmpty, 'a book always has at least one set'),
      sets = List.unmodifiable(sets),
      activeId = sets.any((s) => s.id == activeId) ? activeId! : sets.first.id;

  /// A fresh book with a single empty 組 named [defaultSessionPlanSetName].
  factory SessionPlanBook.initial({
    String id = legacySessionPlanSetId,
    List<SessionPlanEntry> sessions = const [],
  }) => SessionPlanBook(
    sets: [
      SessionPlanSet(
        id: id,
        name: defaultSessionPlanSetName(1),
        sessions: sessions,
      ),
    ],
  );

  /// Null unless [json] holds at least one valid 組.
  static SessionPlanBook? tryFromJson(Map<String, dynamic> json) {
    final rawSets = json['sets'];
    if (rawSets is! List) return null;
    final sets = rawSets
        .whereType<Map<String, dynamic>>()
        .map(SessionPlanSet.tryFromJson)
        .whereType<SessionPlanSet>()
        .toList();
    // Ids must be unique: a duplicate would make one edit hit two 組.
    final seen = <String>{};
    sets.retainWhere((s) => seen.add(s.id));
    if (sets.isEmpty) return null;
    final activeId = json['activeId'];
    return SessionPlanBook(
      sets: sets,
      activeId: activeId is String ? activeId : null,
    );
  }

  final List<SessionPlanSet> sets;

  /// Always the id of one of [sets] (falls back to the first otherwise).
  final String activeId;

  SessionPlanSet get active => sets.firstWhere((s) => s.id == activeId);

  Map<String, dynamic> toJson() => {
    'activeId': activeId,
    'sets': sets.map((s) => s.toJson()).toList(),
  };
}

String defaultSessionPlanSetName(int number) => '組$number';
