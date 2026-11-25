/// Interne Team-Einstufung eines Mitglieds innerhalb einer Flugschule.
/// Für das Mitglied selbst in der UI vollständig unsichtbar.
enum TeamTierEnum {
  /// Reguläres Stammteam: voller Zugriff auf Event-Details & offene Stellen.
  core('core', 'Stammteam'),

  /// Erweitertes Team: sieht fremde/nicht zugewiesene Events nur grau & ohne
  /// Details, kann sich nicht selbst bewerben (nur direkte Admin-Anfragen/-Einteilungen).
  extended('extended', 'Erweitertes Team');

  final String wireValue;
  final String label;
  const TeamTierEnum(this.wireValue, this.label);

  static TeamTierEnum parse(dynamic raw) {
    final s = (raw ?? 'core').toString().trim().toLowerCase();
    for (final v in TeamTierEnum.values) {
      if (v.wireValue == s || v.name.toLowerCase() == s) return v;
    }
    return TeamTierEnum.core;
  }
}
