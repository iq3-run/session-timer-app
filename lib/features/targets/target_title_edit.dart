/// The title change to apply, mirroring `TimeTargetsController.updateTarget`
/// 's `title`/`clearTitle` parameters.
typedef TargetTitleEdit = ({String? title, bool clearTitle});

/// Turns a title-prompt dialog's raw result into an explicit title update.
///
/// `null` means the dialog was dismissed without pressing OK (back button,
/// tap outside) — that means "leave the title as is", not "clear it", so a
/// null [rawTitle] must NOT be treated the same as a confirmed empty one
/// (confirming with blank text does mean "clear it").
TargetTitleEdit resolveTargetTitleEdit(String? rawTitle) {
  if (rawTitle == null) return (title: null, clearTitle: false);
  final trimmed = rawTitle.trim();
  final normalized = trimmed.isEmpty ? null : trimmed;
  return (title: normalized, clearTitle: normalized == null);
}
