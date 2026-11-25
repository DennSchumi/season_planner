enum EventStatusEnum {
  scheduled('Geplant'),
  provisional('Zugesagt'),
  canceled('Abgesagt'),
  done('Abgeschlossen');

  final String label;

  const EventStatusEnum(this.label);

  static EventStatusEnum parse(dynamic raw) {
    final s = (raw ?? 'scheduled').toString();
    return EventStatusEnum.values.firstWhere(
      (e) => e.name == s,
      orElse: () => EventStatusEnum.scheduled,
    );
  }
}
