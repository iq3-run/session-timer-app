/// Ephemeral, UI-only entry for the settings sheet's "週末（マイルストーン）"
/// section. Not persisted — see plans/feat-settings-sheet-shell.md.
class WeekendMilestone {
  const WeekendMilestone({
    required this.id,
    required this.label,
    required this.date,
  });

  final int id;
  final String label;
  final DateTime date;
}
