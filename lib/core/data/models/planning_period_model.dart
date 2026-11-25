enum PlanningStage {
  availability(1, 'Stufe 1 – Verfügbarkeit'),
  application(2, 'Stufe 2 – Bewerbung'),
  production(3, 'Stufe 3 – Produktion');

  final int value;
  final String label;
  const PlanningStage(this.value, this.label);

  String get shortLabel {
    switch (this) {
      case PlanningStage.availability:
        return 'Stufe 1: Verfügbarkeit';
      case PlanningStage.application:
        return 'Stufe 2: Bewerbung';
      case PlanningStage.production:
        return 'Stufe 3: Produktion';
    }
  }

  static PlanningStage fromInt(int? v) {
    switch (v) {
      case 1:
        return PlanningStage.availability;
      case 2:
        return PlanningStage.application;
      case 3:
      default:
        return PlanningStage.production;
    }
  }
}

class PlanningPeriod {
  final String id;
  final String flightSchoolId;
  final String seasonLabel;
  final PlanningStage stage;
  final DateTime? startDate;
  final DateTime? endDate;

  const PlanningPeriod({
    required this.id,
    required this.flightSchoolId,
    required this.seasonLabel,
    required this.stage,
    this.startDate,
    this.endDate,
  });

  factory PlanningPeriod.fromMap(String id, Map<String, dynamic> map) {
    final stageRaw = map['stage'];
    final stageInt = stageRaw is int ? stageRaw : int.tryParse('$stageRaw');
    return PlanningPeriod(
      id: id,
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      seasonLabel: (map['season_label'] ?? 'Saison').toString(),
      stage: PlanningStage.fromInt(stageInt),
      startDate: map['start_date'] != null && map['start_date'].toString().isNotEmpty
          ? DateTime.tryParse(map['start_date'].toString())
          : null,
      endDate: map['end_date'] != null && map['end_date'].toString().isNotEmpty
          ? DateTime.tryParse(map['end_date'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'flight_school_id': flightSchoolId,
        'season_label': seasonLabel,
        'stage': stage.value,
        'start_date': startDate?.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
      };

  bool get hasDateRange => startDate != null && endDate != null;

  /// Prüft inklusiv nach Kalendertag, ob [date] im Gültigkeitszeitraum dieser Saison liegt.
  bool containsDate(DateTime date) {
    if (startDate == null || endDate == null) return false;
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final e = DateTime(endDate!.year, endDate!.month, endDate!.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  /// Prüft, ob sich der Zeitraum dieser Saison mit einem anderen Zeitraum überschneidet.
  bool overlapsRange(DateTime otherStart, DateTime otherEnd) {
    if (startDate == null || endDate == null) return false;
    final s1 = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final e1 = DateTime(endDate!.year, endDate!.month, endDate!.day);
    final s2 = DateTime(otherStart.year, otherStart.month, otherStart.day);
    final e2 = DateTime(otherEnd.year, otherEnd.month, otherEnd.day);
    return !e1.isBefore(s2) && !s1.isAfter(e2);
  }

  String get dateRangeLabel {
    if (startDate == null || endDate == null) return 'Kein Zeitraum festgelegt';
    String f(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return '${f(startDate!)} – ${f(endDate!)}';
  }

  PlanningPeriod copyWith({
    String? id,
    String? flightSchoolId,
    String? seasonLabel,
    PlanningStage? stage,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return PlanningPeriod(
      id: id ?? this.id,
      flightSchoolId: flightSchoolId ?? this.flightSchoolId,
      seasonLabel: seasonLabel ?? this.seasonLabel,
      stage: stage ?? this.stage,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }
}

/// Ermittelt die maßgebliche Saison für ein Event-Datum.
/// Primär zählt immer der Gültigkeitszeitraum (`startDate`–`endDate`) der Saisons.
/// Überschneiden sich mehrere Saisons, gewinnt die spezifischste (kürzester Zeitraum).
/// Nur falls keine Saison per Zeitraum passt, greift ein Fallback auf [fallbackPeriodId]
/// (sofern diese Alt-Periode keinen eigenen Zeitraum hat).
PlanningPeriod? resolvePlanningPeriod(
  List<PlanningPeriod> periods,
  DateTime eventDate, {
  String? fallbackPeriodId,
}) {
  if (periods.isEmpty) return null;

  final matching = periods.where((p) => p.containsDate(eventDate)).toList();
  if (matching.isNotEmpty) {
    matching.sort((a, b) {
      final durA = a.endDate!.difference(a.startDate!).inDays;
      final durB = b.endDate!.difference(b.startDate!).inDays;
      return durA.compareTo(durB);
    });
    return matching.first;
  }

  if (fallbackPeriodId != null && fallbackPeriodId.isNotEmpty) {
    for (final p in periods) {
      if (p.id == fallbackPeriodId && !p.hasDateRange) {
        return p;
      }
    }
  }

  return null;
}

enum AvailabilityKind {
  available('Verfügbar'),
  blackout('Abwesend / Blackout');

  final String label;
  const AvailabilityKind(this.label);

  static AvailabilityKind parse(dynamic raw) {
    final s = (raw ?? 'available').toString();
    return AvailabilityKind.values.firstWhere(
      (e) => e.name == s,
      orElse: () => AvailabilityKind.available,
    );
  }
}

class AvailabilitySubmission {
  final String id;
  final String userId;
  final String flightSchoolId;
  final String? planningPeriodId;
  final AvailabilityKind kind;
  final DateTime startDate;
  final DateTime endDate;
  final String notes;

  const AvailabilitySubmission({
    required this.id,
    required this.userId,
    required this.flightSchoolId,
    this.planningPeriodId,
    required this.kind,
    required this.startDate,
    required this.endDate,
    this.notes = '',
  });

  bool overlaps(DateTime start, DateTime end) {
    final sDay = DateTime(startDate.year, startDate.month, startDate.day);
    final eDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    return !end.isBefore(sDay) && !start.isAfter(eDay);
  }

  factory AvailabilitySubmission.fromMap(String id, Map<String, dynamic> map) {
    return AvailabilitySubmission(
      id: id,
      userId: (map['user_id'] ?? '').toString(),
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      planningPeriodId: map['planning_period_id']?.toString(),
      kind: AvailabilityKind.parse(map['kind']),
      startDate: DateTime.tryParse((map['start_date'] ?? '').toString()) ??
          DateTime.now(),
      endDate: DateTime.tryParse((map['end_date'] ?? '').toString()) ??
          DateTime.now(),
      notes: (map['notes'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'user_id': userId,
        'flight_school_id': flightSchoolId,
        'planning_period_id': planningPeriodId,
        'kind': kind.name,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'notes': notes,
      };
}
