/// Legacy-Fallback-Rollen-Enum.
/// Neue Rollen werden dynamisch je Flugschule in `core_db.team_roles` verwaltet.
enum EventRoleEnum {
  leader('Fluglehrer'),
  co_leader('Anwärter'),
  additional_support('Sicherheitstrainer'),
  trainee('Tandempilot'),
  camera_crew('Kamerateam');

  final String label;
  const EventRoleEnum(this.label);

  /// Übersetzt alte Enum-Keys in lesbare Namen und gibt dynamische Rollennamen 1:1 zurück.
  static String displayLabel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Ohne Rolle';
    for (final e in EventRoleEnum.values) {
      if (e.name == trimmed) return e.label;
    }
    return trimmed;
  }
}
