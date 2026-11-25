import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';

enum TimesheetStatus {
  draft('draft', 'Entwurf'),
  submitted('submitted', 'Abgesendet');

  final String wireValue;
  final String label;
  const TimesheetStatus(this.wireValue, this.label);

  static TimesheetStatus parse(dynamic raw) {
    final s = (raw ?? 'draft').toString().trim().toLowerCase();
    for (final v in TimesheetStatus.values) {
      if (v.wireValue == s || v.name.toLowerCase() == s) return v;
    }
    return TimesheetStatus.draft;
  }
}

/// Standard-Regel (Default für 1C): Fluglehrer, Sicherheitstrainer und Anwärter
/// sind standardmäßig stundenzettelpflichtig, solange der Admin keine abweichende
/// Auswahl konfiguriert hat.
bool isDefaultTimesheetQualificationName(String name) {
  final n = name.trim().toLowerCase();
  return n.contains('lehrer') ||
      n.contains('trainer') ||
      n.contains('anwärter') ||
      n.contains('anwaerter');
}

/// Liefert die effektiv stundenzettelpflichtigen Qualifikations-IDs einer Schule.
/// Ist `configuredIds` leer, greifen automatisch die Standard-Qualifikationen
/// (Fluglehrer, Sicherheitstrainer, Anwärter).
Set<String> resolveEffectiveTimesheetQualificationIds({
  required List<Qualification> allQualifications,
  required List<String> configuredIds,
}) {
  final cleaned = configuredIds
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();
  if (cleaned.isNotEmpty) return cleaned;

  return allQualifications
      .where((q) => isDefaultTimesheetQualificationName(q.name))
      .map((q) => q.id)
      .toSet();
}

/// Prüft, ob ein Mitglied anhand seiner zugeteilten Qualifikationen in einer
/// Flugschule stundenzettelpflichtig ist.
bool memberQualifiesForTimesheet({
  required bool timesheetEnabled,
  required List<Qualification> schoolQualifications,
  required List<String> configuredQualIds,
  required List<String> memberQualificationIds,
}) {
  if (!timesheetEnabled) return false;
  if (memberQualificationIds.isEmpty) return false;
  final effectiveIds = resolveEffectiveTimesheetQualificationIds(
    allQualifications: schoolQualifications,
    configuredIds: configuredQualIds,
  );
  for (final qId in memberQualificationIds) {
    if (effectiveIds.contains(qId)) return true;
  }
  // Fallback falls Qualifikations-Liste noch nicht geladen war und keine Custom-IDs existieren
  if (configuredQualIds.isEmpty && schoolQualifications.isEmpty) {
    return memberQualificationIds.any(isDefaultTimesheetQualificationName);
  }
  return false;
}

/// Einzelner Kalendertag innerhalb eines Event-Stundenzettels.
class TimesheetDayEntry {
  /// ISO-Datum `YYYY-MM-DD`.
  final String dateIso;

  /// True = Mitarbeiter war an diesem Tag im Einsatz; False = Kein Einsatz (0 Std.).
  final bool active;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final int breakMinutes;

  const TimesheetDayEntry({
    required this.dateIso,
    this.active = true,
    this.startHour = 9,
    this.startMinute = 0,
    this.endHour = 17,
    this.endMinute = 0,
    this.breakMinutes = 30,
  });

  DateTime get date {
    final parts = dateIso.split('-');
    if (parts.length == 3) {
      return DateTime(
        int.tryParse(parts[0]) ?? 2025,
        int.tryParse(parts[1]) ?? 1,
        int.tryParse(parts[2]) ?? 1,
      );
    }
    return DateTime.now();
  }

  TimeOfDay get startTime => TimeOfDay(hour: startHour, minute: startMinute);
  TimeOfDay get endTime => TimeOfDay(hour: endHour, minute: endMinute);

  int get startTotalMinutes => startHour * 60 + startMinute;
  int get endTotalMinutes => endHour * 60 + endMinute;

  /// Brutto-Minuten ohne Pause (kann <= 0 sein, falls Ende <= Beginn).
  int get grossMinutes => active ? (endTotalMinutes - startTotalMinutes) : 0;

  /// Netto-Arbeitszeit in Minuten (mindestens 0).
  int get netMinutes {
    if (!active) return 0;
    final raw = grossMinutes - breakMinutes;
    return raw > 0 ? raw : 0;
  }

  bool get hasInvalidRange =>
      active && (endTotalMinutes <= startTotalMinutes || breakMinutes < 0 || grossMinutes < breakMinutes);

  String get startLabel =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';

  String get endLabel =>
      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';

  String get formattedDate {
    final d = date;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String get weekdayShort {
    const names = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return names[(date.weekday - 1).clamp(0, 6)];
  }

  String get formattedNetHours => formatMinutesAsHours(netMinutes);

  factory TimesheetDayEntry.fromJson(Map<String, dynamic> map) {
    final startStr = (map['start'] ?? '09:00').toString();
    final endStr = (map['end'] ?? '17:00').toString();
    final sParts = startStr.split(':');
    final eParts = endStr.split(':');
    final rawBreak = map['breakMinutes'];
    final breakMins = rawBreak is int
        ? rawBreak
        : (int.tryParse('${rawBreak ?? 30}') ?? 30);

    return TimesheetDayEntry(
      dateIso: (map['date'] ?? '').toString(),
      active: map['active'] != false,
      startHour: (int.tryParse(sParts.isNotEmpty ? sParts[0] : '9') ?? 9).clamp(0, 23),
      startMinute: (int.tryParse(sParts.length > 1 ? sParts[1] : '0') ?? 0).clamp(0, 59),
      endHour: (int.tryParse(eParts.isNotEmpty ? eParts[0] : '17') ?? 17).clamp(0, 23),
      endMinute: (int.tryParse(eParts.length > 1 ? eParts[1] : '0') ?? 0).clamp(0, 59),
      breakMinutes: breakMins < 0 ? 0 : breakMins,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': dateIso,
        'active': active,
        'start': startLabel,
        'end': endLabel,
        'breakMinutes': breakMinutes,
      };

  TimesheetDayEntry copyWith({
    String? dateIso,
    bool? active,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    int? breakMinutes,
  }) {
    return TimesheetDayEntry(
      dateIso: dateIso ?? this.dateIso,
      active: active ?? this.active,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
      breakMinutes: breakMinutes ?? this.breakMinutes,
    );
  }
}

/// Formatiert Minuten als z. B. `7:30 Std.` oder `0:00 Std.`.
String formatMinutesAsHours(int totalMinutes) {
  final safe = totalMinutes < 0 ? 0 : totalMinutes;
  final h = safe ~/ 60;
  final m = safe % 60;
  return '$h:${m.toString().padLeft(2, '0')} Std.';
}

/// Formatiert Minuten als Dezimalstunden mit Komma (für Excel/PDF-Summen), z. B. `7,50`.
String formatMinutesAsDecimal(int totalMinutes) {
  final safe = totalMinutes < 0 ? 0 : totalMinutes;
  return (safe / 60.0).toStringAsFixed(2).replaceAll('.', ',');
}

String _toIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Erzeugt die vorkonfigurierten Kalendertage für ein Event.
List<TimesheetDayEntry> buildDefaultTimesheetEntriesForEvent(Event event) {
  final startLocal = event.startTime.toLocal();
  final endLocal = event.endTime.toLocal();
  final firstDay = DateTime(startLocal.year, startLocal.month, startLocal.day);
  final lastDay = DateTime(endLocal.year, endLocal.month, endLocal.day);
  final safeLast = lastDay.isBefore(firstDay) ? firstDay : lastDay;
  final daySpan = safeLast.difference(firstDay).inDays.clamp(0, 90);

  final entries = <TimesheetDayEntry>[];
  for (int i = 0; i <= daySpan; i++) {
    final d = firstDay.add(Duration(days: i));
    final isFirst = i == 0;
    final isLast = i == daySpan;

    int sH = isFirst ? startLocal.hour : 9;
    int sM = isFirst ? startLocal.minute : 0;
    int eH = isLast ? endLocal.hour : 17;
    int eM = isLast ? endLocal.minute : 0;

    // Sinnvolle Defaults, falls Start/Ende am selben Tag unplausibel sind (z. B. 00:00)
    if (eH * 60 + eM <= sH * 60 + sM) {
      sH = 9;
      sM = 0;
      eH = 17;
      eM = 0;
    }

    final gross = (eH * 60 + eM) - (sH * 60 + sM);
    final defaultBreak = gross >= 360 ? 30 : 0;

    entries.add(
      TimesheetDayEntry(
        dateIso: _toIsoDate(d),
        active: true,
        startHour: sH,
        startMinute: sM,
        endHour: eH,
        endMinute: eM,
        breakMinutes: defaultBreak,
      ),
    );
  }
  return entries;
}

class EventTimesheet {
  final String id;
  final String flightSchoolId;
  final String eventId;
  final String assignmentId;
  final String userId;
  final String eventName;
  final String roleName;
  final DateTime eventStart;
  final DateTime eventEnd;
  final List<TimesheetDayEntry> entries;
  final TimesheetStatus status;
  final String? signatureFileId;
  final DateTime? submittedAt;
  final DateTime updatedAt;

  const EventTimesheet({
    required this.id,
    required this.flightSchoolId,
    required this.eventId,
    required this.assignmentId,
    required this.userId,
    required this.eventName,
    required this.roleName,
    required this.eventStart,
    required this.eventEnd,
    required this.entries,
    this.status = TimesheetStatus.draft,
    this.signatureFileId,
    this.submittedAt,
    required this.updatedAt,
  });

  bool get isSubmitted => status == TimesheetStatus.submitted;

  int get totalMinutes =>
      entries.fold<int>(0, (sum, e) => sum + e.netMinutes);

  int get activeDays => entries.where((e) => e.active && e.netMinutes > 0).length;

  String get formattedTotalHours => formatMinutesAsHours(totalMinutes);

  bool get hasAnyInvalidDay => entries.any((e) => e.hasInvalidRange);

  factory EventTimesheet.fromMap(String id, Map<String, dynamic> map) {
    List<TimesheetDayEntry> parsedEntries = const [];
    final rawEntries = (map['entries_json'] ?? '').toString().trim();
    if (rawEntries.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawEntries);
        if (decoded is List) {
          parsedEntries = decoded
              .whereType<Map>()
              .map(
                (m) => TimesheetDayEntry.fromJson(
                  Map<String, dynamic>.from(m),
                ),
              )
              .toList();
        }
      } catch (_) {}
    }

    DateTime? parseDt(dynamic raw) {
      if (raw == null) return null;
      final s = raw.toString().trim();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s)?.toLocal();
    }

    final start = parseDt(map['event_start']) ?? DateTime.now();
    final end = parseDt(map['event_end']) ?? start;
    final sigRaw = (map['signature_file_id'] ?? '').toString().trim();

    return EventTimesheet(
      id: id,
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      eventId: (map['event_id'] ?? '').toString(),
      assignmentId: (map['assignment_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      eventName: (map['event_name'] ?? '').toString(),
      roleName: (map['role_name'] ?? '').toString(),
      eventStart: start,
      eventEnd: end.isBefore(start) ? start : end,
      entries: parsedEntries,
      status: TimesheetStatus.parse(map['status']),
      signatureFileId: sigRaw.isEmpty ? null : sigRaw,
      submittedAt: parseDt(map['submitted_at']),
      updatedAt: parseDt(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'flight_school_id': flightSchoolId,
        'event_id': eventId,
        'assignment_id': assignmentId,
        'user_id': userId,
        'event_name': eventName,
        'role_name': roleName,
        'event_start': eventStart.toUtc().toIso8601String(),
        'event_end': eventEnd.toUtc().toIso8601String(),
        'entries_json': jsonEncode(entries.map((e) => e.toJson()).toList()),
        'total_minutes': totalMinutes,
        'active_days': activeDays,
        'status': status.wireValue,
        'signature_file_id': signatureFileId,
        'submitted_at': submittedAt?.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  EventTimesheet copyWith({
    String? id,
    List<TimesheetDayEntry>? entries,
    TimesheetStatus? status,
    String? signatureFileId,
    bool clearSignature = false,
    DateTime? submittedAt,
    bool clearSubmittedAt = false,
    DateTime? updatedAt,
  }) {
    return EventTimesheet(
      id: id ?? this.id,
      flightSchoolId: flightSchoolId,
      eventId: eventId,
      assignmentId: assignmentId,
      userId: userId,
      eventName: eventName,
      roleName: roleName,
      eventStart: eventStart,
      eventEnd: eventEnd,
      entries: entries ?? this.entries,
      status: status ?? this.status,
      signatureFileId:
          clearSignature ? null : (signatureFileId ?? this.signatureFileId),
      submittedAt:
          clearSubmittedAt ? null : (submittedAt ?? this.submittedAt),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
