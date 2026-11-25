enum TandemDutyStatus {
  confirmed('confirmed', 'Bestätigt'),
  requestedByPilot('requested_by_pilot', 'Angefragt (Pilot)'),
  requestedByAdmin('requested_by_admin', 'Angefragt (Admin)'),
  cancellationRequested('cancellation_requested', 'Absage angefragt'),
  declined('declined', 'Abgelehnt');

  final String wireValue;
  final String label;
  const TandemDutyStatus(this.wireValue, this.label);

  static TandemDutyStatus parse(dynamic raw) {
    final s = (raw ?? 'confirmed').toString().trim().toLowerCase();
    for (final v in TandemDutyStatus.values) {
      if (v.wireValue == s || v.name.toLowerCase() == s) return v;
    }
    return TandemDutyStatus.confirmed;
  }

  /// True für alle nicht abgelehnten Status, die eine Doppelbelegung blockieren.
  bool get blocksSchedule =>
      this == TandemDutyStatus.confirmed ||
      this == TandemDutyStatus.requestedByPilot ||
      this == TandemDutyStatus.requestedByAdmin ||
      this == TandemDutyStatus.cancellationRequested;
}

class TandemDuty {
  final String id;
  final String flightSchoolId;
  final String userId;
  final DateTime startDate;
  final DateTime endDate;
  final bool isFullDay;
  final TandemDutyStatus status;
  final String notes;
  final String createdBy;

  const TandemDuty({
    required this.id,
    required this.flightSchoolId,
    required this.userId,
    required this.startDate,
    required this.endDate,
    this.isFullDay = true,
    this.status = TandemDutyStatus.confirmed,
    this.notes = '',
    this.createdBy = '',
  });

  factory TandemDuty.fromMap(String id, Map<String, dynamic> map) {
    final rawStart = DateTime.tryParse((map['start_date'] ?? '').toString()) ??
        DateTime.now();
    final rawEnd = DateTime.tryParse((map['end_date'] ?? '').toString()) ??
        rawStart;
    final start = rawStart.toLocal();
    final end = rawEnd.toLocal();
    return TandemDuty(
      id: id,
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      startDate: start,
      endDate: end.isBefore(start) ? start : end,
      isFullDay: map['is_full_day'] != false,
      status: TandemDutyStatus.parse(map['status']),
      notes: (map['notes'] ?? '').toString(),
      createdBy: (map['created_by'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'flight_school_id': flightSchoolId,
        'user_id': userId,
        'start_date': startDate.toUtc().toIso8601String(),
        'end_date': endDate.toUtc().toIso8601String(),
        'is_full_day': isFullDay,
        'status': status.wireValue,
        'notes': notes,
        'created_by': createdBy,
      };

  factory TandemDuty.fromJson(Map<String, dynamic> json) =>
      TandemDuty.fromMap((json['id'] ?? '').toString(), json);

  Map<String, dynamic> toJson() => {'id': id, ...toMap()};

  DateTime get startDay =>
      DateTime(startDate.year, startDate.month, startDate.day);

  DateTime get endDay => DateTime(endDate.year, endDate.month, endDate.day);

  /// Effektiver Start-Zeitpunkt für Überschneidungsprüfungen.
  DateTime get effectiveStart => isFullDay
      ? DateTime(startDate.year, startDate.month, startDate.day, 0, 0)
      : startDate;

  /// Effektiver End-Zeitpunkt für Überschneidungsprüfungen.
  DateTime get effectiveEnd => isFullDay
      ? DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59)
      : endDate;

  bool get isSingleDay => startDay == endDay;

  int get dayCount => endDay.difference(startDay).inDays + 1;

  bool coversDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(startDay) && !d.isAfter(endDay);
  }

  bool overlapsDayRange(DateTime rangeStart, DateTime rangeEnd) {
    final a = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final b = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
    return !(endDay.isBefore(a) || startDay.isAfter(b));
  }

  /// Präzise Zeit-Überschneidungsprüfung (verhindert Doppelbelegung auch bei
  /// teilweisen Zeitfenstern, erlaubt z. B. aber überschneidungsfreie Zeiten nicht
  /// wenn Ganztagesdienst vorliegt).
  bool overlapsTimeWindow(
    DateTime otherStart,
    DateTime otherEnd, {
    bool otherIsFullDay = false,
  }) {
    final aStart = effectiveStart;
    final aEnd = effectiveEnd;
    final bStart = otherIsFullDay
        ? DateTime(otherStart.year, otherStart.month, otherStart.day, 0, 0)
        : otherStart;
    final bEnd = otherIsFullDay
        ? DateTime(otherEnd.year, otherEnd.month, otherEnd.day, 23, 59, 59)
        : otherEnd;
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  String get dateRangeLabel {
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.${x.year}';
    return isSingleDay ? d(startDate) : '${d(startDate)} – ${d(endDate)}';
  }

  String get timeWindowLabel {
    if (isFullDay) return 'Ganztägig';
    String hm(DateTime x) =>
        '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
    return '${hm(startDate)}–${hm(endDate)} Uhr';
  }

  TandemDuty copyWith({
    String? id,
    String? flightSchoolId,
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    bool? isFullDay,
    TandemDutyStatus? status,
    String? notes,
    String? createdBy,
  }) {
    return TandemDuty(
      id: id ?? this.id,
      flightSchoolId: flightSchoolId ?? this.flightSchoolId,
      userId: userId ?? this.userId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isFullDay: isFullDay ?? this.isFullDay,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}

class TandemDemand {
  final String id;
  final String flightSchoolId;
  final DateTime startDate;
  final DateTime endDate;
  final int targetPilots;

  /// ISO-Wochentage 1 (Mo) bis 7 (So).
  final Set<int> weekdays;
  final String label;

  const TandemDemand({
    required this.id,
    required this.flightSchoolId,
    required this.startDate,
    required this.endDate,
    required this.targetPilots,
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.label = '',
  });

  factory TandemDemand.fromMap(String id, Map<String, dynamic> map) {
    final rawStart = DateTime.tryParse((map['start_date'] ?? '').toString()) ??
        DateTime.now();
    final rawEnd = DateTime.tryParse((map['end_date'] ?? '').toString()) ??
        rawStart;
    final rawTarget = map['target_pilots'];
    final target =
        rawTarget is int ? rawTarget : (int.tryParse('$rawTarget') ?? 1);

    final rawWd = (map['weekdays'] ?? '1,2,3,4,5,6,7').toString();
    final parsedWd = rawWd
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .where((w) => w >= 1 && w <= 7)
        .toSet();

    final start = rawStart.toLocal();
    final end = rawEnd.toLocal();
    return TandemDemand(
      id: id,
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      startDate: DateTime(start.year, start.month, start.day),
      endDate: DateTime(
        end.isBefore(start) ? start.year : end.year,
        end.isBefore(start) ? start.month : end.month,
        end.isBefore(start) ? start.day : end.day,
      ),
      targetPilots: target < 0 ? 0 : target,
      weekdays: parsedWd.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : parsedWd,
      label: (map['label'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    final sortedWd = weekdays.toList()..sort();
    return {
      'flight_school_id': flightSchoolId,
      'start_date':
          DateTime(startDate.year, startDate.month, startDate.day, 12)
              .toUtc()
              .toIso8601String(),
      'end_date': DateTime(endDate.year, endDate.month, endDate.day, 12)
          .toUtc()
          .toIso8601String(),
      'target_pilots': targetPilots,
      'weekdays': sortedWd.join(','),
      'label': label,
    };
  }

  factory TandemDemand.fromJson(Map<String, dynamic> json) =>
      TandemDemand.fromMap((json['id'] ?? '').toString(), json);

  Map<String, dynamic> toJson() => {'id': id, ...toMap()};

  DateTime get startDay =>
      DateTime(startDate.year, startDate.month, startDate.day);

  DateTime get endDay => DateTime(endDate.year, endDate.month, endDate.day);

  bool appliesToDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(startDay) || d.isAfter(endDay)) return false;
    return weekdays.contains(d.weekday);
  }

  String get dateRangeLabel {
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.${x.year}';
    return startDay == endDay ? d(startDay) : '${d(startDay)} – ${d(endDay)}';
  }

  String get weekdaysLabel {
    if (weekdays.length == 7) return 'Täglich';
    if (weekdays.length == 5 &&
        weekdays.containsAll(const {1, 2, 3, 4, 5})) {
      return 'Mo–Fr';
    }
    if (weekdays.length == 2 && weekdays.containsAll(const {6, 7})) {
      return 'Sa–So';
    }
    const names = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final sorted = weekdays.toList()..sort();
    return sorted.map((w) => names[w - 1]).join(', ');
  }
}

/// Ermittelt den Soll-Bedarf für einen Tag aus allen konfigurierten Bedarfszeiträumen.
/// Gibt `null` zurück, wenn kein Bedarf festgelegt wurde (Option B).
/// Überschneiden sich mehrere Regeln (z. B. Mo–So: 2 und Sa–So: 4), gewinnt der höhere Wert.
int? resolveTargetPilotsForDay(List<TandemDemand> demands, DateTime day) {
  int? result;
  for (final dem in demands) {
    if (!dem.appliesToDay(day)) continue;
    if (result == null || dem.targetPilots > result) {
      result = dem.targetPilots;
    }
  }
  return result;
}

/// Zusammengefasster Tandem-Zeitraum für die kompakte Darstellung auf der Startseite.
class TandemDutyBundle {
  final String flightSchoolId;
  final String userId;
  final DateTime startDate;
  final DateTime endDate;
  final bool isFullDay;
  final List<TandemDuty> duties;

  const TandemDutyBundle({
    required this.flightSchoolId,
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.isFullDay,
    required this.duties,
  });

  DateTime get startDay =>
      DateTime(startDate.year, startDate.month, startDate.day);

  DateTime get endDay => DateTime(endDate.year, endDate.month, endDate.day);

  int get dayCount => endDay.difference(startDay).inDays + 1;

  String get dateRangeLabel {
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.${x.year}';
    return startDay == endDay ? d(startDay) : '${d(startDay)} – ${d(endDay)}';
  }

  String get timeLabel {
    if (duties.length == 1 && !duties.first.isFullDay) {
      return duties.first.timeWindowLabel;
    }
    return isFullDay ? 'Ganztägig' : 'Zeitlich begrenzt';
  }

  bool get hasCancellationRequest =>
      duties.any((d) => d.status == TandemDutyStatus.cancellationRequested);

  bool get allCancellationRequested =>
      duties.isNotEmpty &&
      duties.every((d) => d.status == TandemDutyStatus.cancellationRequested);

  String get combinedNotes => duties
      .map((d) => d.notes.trim())
      .where((n) => n.isNotEmpty)
      .toSet()
      .join(' · ');
}

/// Bündelt zusammenhängende (direkt aneinander anschließende) bestätigte
/// Tandem-Dienste derselben Flugschule in kompakte Zeiträume für die Startseite.
List<TandemDutyBundle> bundleConsecutiveTandemDuties(List<TandemDuty> input) {
  if (input.isEmpty) return const [];
  final sorted = List<TandemDuty>.from(input)
    ..sort((a, b) {
      final sc = a.flightSchoolId.compareTo(b.flightSchoolId);
      if (sc != 0) return sc;
      return a.startDate.compareTo(b.startDate);
    });

  final bundles = <TandemDutyBundle>[];
  for (final duty in sorted) {
    if (bundles.isNotEmpty) {
      final last = bundles.last;
      final sameSchool = last.flightSchoolId == duty.flightSchoolId &&
          last.userId == duty.userId;
      final canMerge = sameSchool &&
          last.isFullDay &&
          duty.isFullDay &&
          !duty.startDay.isAfter(last.endDay.add(const Duration(days: 1)));

      if (canMerge) {
        final mergedEnd =
            duty.endDate.isAfter(last.endDate) ? duty.endDate : last.endDate;
        bundles[bundles.length - 1] = TandemDutyBundle(
          flightSchoolId: last.flightSchoolId,
          userId: last.userId,
          startDate: last.startDate,
          endDate: mergedEnd,
          isFullDay: true,
          duties: [...last.duties, duty],
        );
        continue;
      }
    }

    bundles.add(
      TandemDutyBundle(
        flightSchoolId: duty.flightSchoolId,
        userId: duty.userId,
        startDate: duty.startDate,
        endDate: duty.endDate,
        isFullDay: duty.isFullDay,
        duties: [duty],
      ),
    );
  }

  bundles.sort((a, b) => a.startDate.compareTo(b.startDate));
  return bundles;
}
