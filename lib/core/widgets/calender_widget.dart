import 'package:flutter/material.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';

typedef FlightSchoolResolver = dynamic Function(String flightSchoolId);

enum _CalendarDisplayMode { month, agenda }

class EventsCalendar extends StatefulWidget {
  final List<Event> events;
  final bool showFlightSchool;
  final bool redactStage1;

  final FlightSchoolResolver flightSchoolById;

  /// Zeiträume in Planungsstufe 1 – werden im Kalender farblich hervorgehoben.
  final List<PlanningPeriod> stage1Periods;

  /// Eingetragene Verfügbarkeiten & Abwesenheiten (Nutzer: eigene; Admin: Team).
  final List<AvailabilitySubmission> availabilityEntries;

  /// True in der Admin-Ansicht, damit bei Verfügbarkeiten Namen & Zähler angezeigt werden.
  final bool isAdminAvailabilityView;

  /// Optionaler Resolver für Benutzernamen (Admin-Verfügbarkeits- & Tandemanzeige).
  final String Function(String userId)? resolveUserName;

  final void Function(Event event)? onEventTap;

  /// Optional (Admin): erlaubt direktes Erstellen eines Events für ein bestimmtes Datum.
  final void Function(DateTime date)? onCreateEventForDay;

  /// Optional (Nutzer): erlaubt direktes Eintragen von Verfügbarkeit/Abwesenheit ab dem gewählten Tag.
  final void Function(DateTime date, AvailabilityKind kind)?
      onCreateAvailabilityForDay;

  /// Optional (Nutzer): erlaubt Löschen einer eigenen Verfügbarkeit/Abwesenheit aus dem Tages-Sheet.
  final Future<void> Function(AvailabilitySubmission submission)?
      onDeleteAvailability;

  /// Optional: informiert Parent über den aktuell ausgewählten Tag (z. B. für FAB-Vorauswahl).
  final ValueChanged<DateTime?>? onSelectedDayChanged;

  /// Optional: informiert Parent beim Monatswechsel (z. B. um Archivdaten bei Bedarf nachzuladen).
  final ValueChanged<DateTime>? onVisibleMonthChanged;

  /// Tandemplanung: schaltet den unteren schmalen Bereich in jeder Tageskachel frei.
  final bool showTandemSection;
  final List<TandemDuty> tandemDuties;
  final List<TandemDemand> tandemDemands;
  final bool isAdminTandemView;
  final String? currentUserId;
  final void Function(DateTime date)? onAdminAssignTandem;
  final void Function(DateTime date)? onManageTandemDemand;
  final void Function(DateTime date)? onPilotRequestTandem;
  final Future<void> Function(TandemDuty duty, bool approve)? onDecideTandemDuty;
  final Future<void> Function(TandemDuty duty)? onDeleteTandemDuty;
  final void Function(TandemDuty duty)? onOwnTandemDutyTap;

  const EventsCalendar({
    super.key,
    required this.events,
    required this.flightSchoolById,
    this.stage1Periods = const [],
    this.availabilityEntries = const [],
    this.isAdminAvailabilityView = false,
    this.resolveUserName,
    this.onEventTap,
    this.onCreateEventForDay,
    this.onCreateAvailabilityForDay,
    this.onDeleteAvailability,
    this.onSelectedDayChanged,
    this.onVisibleMonthChanged,
    this.showFlightSchool = true,
    this.redactStage1 = false,
    this.showTandemSection = false,
    this.tandemDuties = const [],
    this.tandemDemands = const [],
    this.isAdminTandemView = false,
    this.currentUserId,
    this.onAdminAssignTandem,
    this.onManageTandemDemand,
    this.onPilotRequestTandem,
    this.onDecideTandemDuty,
    this.onDeleteTandemDuty,
    this.onOwnTandemDutyTap,
  });

  @override
  State<EventsCalendar> createState() => _EventsCalendarState();
}

class _EventsCalendarState extends State<EventsCalendar> {
  late DateTime _visibleMonth;
  DateTime? _selectedDay;
  _CalendarDisplayMode _displayMode = _CalendarDisplayMode.month;
  bool _legendExpanded = false;

  static const _weekdays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];

  double _horizontalSwipeDelta = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _startOfWeek(DateTime d) {
    final weekday = d.weekday;
    return _dateOnly(d).subtract(Duration(days: weekday - 1));
  }

  DateTime _endOfWeek(DateTime d) =>
      _startOfWeek(d).add(const Duration(days: 6));

  List<DateTime> _daysForMonthGrid(DateTime monthFirstDay) {
    final start = _startOfWeek(monthFirstDay);
    final nextMonth = DateTime(monthFirstDay.year, monthFirstDay.month + 1, 1);
    final end = _endOfWeek(nextMonth.subtract(const Duration(days: 1)));

    final days = <DateTime>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    return days;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isInMonth(DateTime d, DateTime monthFirstDay) =>
      d.year == monthFirstDay.year && d.month == monthFirstDay.month;

  bool _eventIntersectsRange(Event e, DateTime start, DateTime end) {
    final s = _dateOnly(e.startTime);
    final t = _dateOnly(e.endTime);
    return !(t.isBefore(start) || s.isAfter(end));
  }

  int _clamp(int v, int min, int max) => v < min ? min : (v > max ? max : v);

  int _effectiveStageFor(Event event) {
    final fs = widget.flightSchoolById(event.flightSchoolId);
    if (fs != null) {
      try {
        final s = (fs as dynamic).effectiveStageFor(event);
        if (s is int) return s;
      } catch (_) {}
    }
    return event.planningStage;
  }

  bool _isAppliedEvent(Event event) =>
      widget.redactStage1 &&
      !event.isSwapOfferFromOther &&
      event.assignmentStatus == EventUserStatusEnum.pending_flight_school &&
      !event.isOwnBindingAssignment;

  bool _isDirectRequestEvent(Event event) =>
      widget.redactStage1 &&
      !event.isSwapOfferFromOther &&
      event.assignmentStatus == EventUserStatusEnum.pending_user &&
      !event.isOwnBindingAssignment;

  bool _isExtendedTeamFor(Event event) {
    final fs = widget.flightSchoolById(event.flightSchoolId);
    if (fs != null) {
      try {
        final v = (fs as dynamic).isExtendedTeam;
        if (v is bool) return v;
      } catch (_) {}
    }
    return false;
  }

  bool _isExtendedTeamRedacted(Event event) =>
      widget.redactStage1 &&
      _isExtendedTeamFor(event) &&
      !event.isOwnBindingAssignment &&
      !_isAppliedEvent(event) &&
      !_isDirectRequestEvent(event);

  bool _isOpenOpportunityEvent(Event event) =>
      widget.redactStage1 &&
      !_isExtendedTeamRedacted(event) &&
      !event.isOwnBindingAssignment &&
      _effectiveStageFor(event) >= 2 &&
      (event.isSwapOfferFromOther ||
          event.assignmentStatus == EventUserStatusEnum.open);

  bool _isStage1Redacted(Event event) =>
      widget.redactStage1 &&
      !_isExtendedTeamRedacted(event) &&
      _effectiveStageFor(event) == 1 &&
      !event.isOwnBindingAssignment &&
      !_isAppliedEvent(event) &&
      !_isDirectRequestEvent(event);

  List<PlanningPeriod> _stage1PeriodsForDay(DateTime day) {
    return widget.stage1Periods
        .where((p) => p.stage == PlanningStage.availability && p.containsDate(day))
        .toList();
  }

  List<PlanningPeriod> _stage1PeriodsForMonth(DateTime monthFirstDay) {
    final start = DateTime(monthFirstDay.year, monthFirstDay.month, 1);
    final end = DateTime(monthFirstDay.year, monthFirstDay.month + 1, 0);
    return widget.stage1Periods
        .where(
          (p) =>
              p.stage == PlanningStage.availability &&
              p.overlapsRange(start, end),
        )
        .toList();
  }

  bool _availabilityIntersectsRange(
    AvailabilitySubmission s,
    DateTime start,
    DateTime end,
  ) {
    final a = _dateOnly(s.startDate);
    final b = _dateOnly(s.endDate);
    return !(b.isBefore(start) || a.isAfter(end));
  }

  List<AvailabilitySubmission> _availabilitiesForDay(DateTime day) {
    final d = _dateOnly(day);
    return widget.availabilityEntries
        .where((s) => _availabilityIntersectsRange(s, d, d))
        .toList()
      ..sort((a, b) {
        if (a.kind != b.kind) {
          return a.kind == AvailabilityKind.available ? -1 : 1;
        }
        return a.startDate.compareTo(b.startDate);
      });
  }

  List<List<_WeekAvailability>> _laneAvailabilitiesForWeek(
    DateTime weekStart,
    DateTime weekEnd,
  ) {
    if (widget.availabilityEntries.isEmpty) return const [];

    final intersecting =
        widget.availabilityEntries
            .where((s) => _availabilityIntersectsRange(s, weekStart, weekEnd))
            .map((s) {
              final a = _dateOnly(s.startDate);
              final b = _dateOnly(s.endDate);

              final continuesLeft = a.isBefore(weekStart);
              final continuesRight = b.isAfter(weekEnd);

              final startIdx = _clamp(a.difference(weekStart).inDays, 0, 6);
              final endIdx = _clamp(b.difference(weekStart).inDays, 0, 6);

              return _WeekAvailability(
                s,
                startIdx,
                endIdx,
                continuesLeft,
                continuesRight,
              );
            })
            .toList()
          ..sort((a, b) {
            if (a.submission.kind != b.submission.kind) {
              return a.submission.kind == AvailabilityKind.available ? -1 : 1;
            }
            final c = a.startIdx.compareTo(b.startIdx);
            if (c != 0) return c;
            return (b.endIdx - b.startIdx).compareTo(a.endIdx - a.startIdx);
          });

    final lanes = <List<_WeekAvailability>>[];
    bool overlaps(_WeekAvailability x, _WeekAvailability y) =>
        !(x.endIdx < y.startIdx || y.endIdx < x.startIdx);

    for (final wa in intersecting) {
      var placed = false;
      for (final lane in lanes) {
        if (lane.every((x) => !overlaps(x, wa))) {
          lane.add(wa);
          placed = true;
          break;
        }
      }
      if (!placed) lanes.add([wa]);
    }

    for (final lane in lanes) {
      lane.sort((a, b) => a.startIdx.compareTo(b.startIdx));
    }
    return lanes;
  }

  String _availabilityLabel(AvailabilitySubmission s) {
    final kindLabel =
        s.kind == AvailabilityKind.available ? 'Verfügbar' : 'Abwesend';
    final rangeLabel = '${_fmtDate(s.startDate)} – ${_fmtDate(s.endDate)}';
    if (widget.isAdminAvailabilityView) {
      final name = widget.resolveUserName?.call(s.userId) ?? 'Mitglied';
      return '$kindLabel: $name ($rangeLabel)';
    }
    return '$kindLabel ($rangeLabel)';
  }

  List<Event> _eventsForDay(DateTime day) {
    final d = _dateOnly(day);
    return widget.events.where((e) => _eventIntersectsRange(e, d, d)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  List<Event> _eventsForMonth(DateTime monthFirstDay) {
    final start = DateTime(monthFirstDay.year, monthFirstDay.month, 1);
    final end = DateTime(monthFirstDay.year, monthFirstDay.month + 1, 0);
    return widget.events
        .where((e) => _eventIntersectsRange(e, start, end))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  List<List<_WeekEvent>> _laneEventsForWeek(
    DateTime weekStart,
    DateTime weekEnd,
  ) {
    final intersecting =
        widget.events
            .where((e) => _eventIntersectsRange(e, weekStart, weekEnd))
            .map((e) {
              final s = _dateOnly(e.startTime);
              final t = _dateOnly(e.endTime);

              final continuesLeft = s.isBefore(weekStart);
              final continuesRight = t.isAfter(weekEnd);

              final startIdx = _clamp(s.difference(weekStart).inDays, 0, 6);
              final endIdx = _clamp(t.difference(weekStart).inDays, 0, 6);

              return _WeekEvent(
                e,
                startIdx,
                endIdx,
                continuesLeft,
                continuesRight,
              );
            })
            .toList()
          ..sort((a, b) {
            final c = a.startIdx.compareTo(b.startIdx);
            if (c != 0) return c;
            return (b.endIdx - b.startIdx).compareTo(a.endIdx - a.startIdx);
          });

    final lanes = <List<_WeekEvent>>[];

    bool overlaps(_WeekEvent a, _WeekEvent b) =>
        !(a.endIdx < b.startIdx || b.endIdx < a.startIdx);

    for (final we in intersecting) {
      var placed = false;
      for (final lane in lanes) {
        if (lane.every((x) => !overlaps(x, we))) {
          lane.add(we);
          placed = true;
          break;
        }
      }
      if (!placed) lanes.add([we]);
    }

    for (final lane in lanes) {
      lane.sort((a, b) => a.startIdx.compareTo(b.startIdx));
    }

    return lanes;
  }

  void _prevMonth() {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    setState(() => _visibleMonth = next);
    widget.onVisibleMonthChanged?.call(next);
  }

  void _nextMonth() {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    setState(() => _visibleMonth = next);
    widget.onVisibleMonthChanged?.call(next);
  }

  void _jumpToToday() {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final monthFirst = DateTime(now.year, now.month, 1);
    setState(() {
      _visibleMonth = monthFirst;
      _selectedDay = today;
    });
    widget.onSelectedDayChanged?.call(today);
    widget.onVisibleMonthChanged?.call(monthFirst);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  List<TandemDuty> _tandemDutiesForDay(DateTime day) {
    if (!widget.showTandemSection || widget.tandemDuties.isEmpty) {
      return const [];
    }
    final list = widget.tandemDuties
        .where(
          (d) => d.status != TandemDutyStatus.declined && d.coversDay(day),
        )
        .toList();
    int rank(TandemDuty d) => switch (d.status) {
          TandemDutyStatus.confirmed => 0,
          TandemDutyStatus.cancellationRequested => 1,
          TandemDutyStatus.requestedByPilot => 2,
          TandemDutyStatus.requestedByAdmin => 3,
          TandemDutyStatus.declined => 4,
        };
    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  int? _tandemTargetForDay(DateTime day) {
    if (!widget.showTandemSection || widget.tandemDemands.isEmpty) return null;
    return resolveTargetPilotsForDay(widget.tandemDemands, day);
  }

  bool _isOwnTandemDuty(TandemDuty d) =>
      widget.currentUserId != null &&
      widget.currentUserId!.isNotEmpty &&
      d.userId == widget.currentUserId;

  Widget _buildCellTandemStrip(DateTime day, {required bool inMonth}) {
    final cs = Theme.of(context).colorScheme;
    final duties = _tandemDutiesForDay(day);
    final confirmedCount =
        duties.where((d) => d.status == TandemDutyStatus.confirmed).length;
    final pendingPilotCount = duties
        .where((d) => d.status == TandemDutyStatus.requestedByPilot)
        .length;
    final pendingAdminCount = duties
        .where((d) => d.status == TandemDutyStatus.requestedByAdmin)
        .length;
    final target = _tandemTargetForDay(day);

    Widget? badge;
    String tooltipText = 'Tandemplanung';

    if (widget.isAdminTandemView) {
      if (target != null && target > 0) {
        final ok = confirmedCount >= target;
        final bg = ok
            ? AppTheme.successBg
            : (confirmedCount == 0 ? AppTheme.dangerBg : AppTheme.warningBg);
        final fg = ok
            ? AppTheme.successColor
            : (confirmedCount == 0
                ? AppTheme.dangerColor
                : AppTheme.warningColor);
        tooltipText = ok
            ? 'Tandem besetzt: $confirmedCount/$target Piloten'
            : 'Tandem: $confirmedCount/$target Piloten (noch ${target - confirmedCount} offen)';
        if (pendingPilotCount > 0) {
          tooltipText += ' · $pendingPilotCount offene Anfrage(n)';
        }
        badge = _TandemCellPill(
          label: '$confirmedCount/$target',
          bg: bg,
          fg: fg,
          showDot: pendingPilotCount > 0,
          dotColor: AppTheme.infoColor,
        );
      } else if (confirmedCount > 0) {
        tooltipText = '$confirmedCount Tandempilot(en) bestätigt';
        if (pendingPilotCount > 0) {
          tooltipText += ' · $pendingPilotCount Anfrage(n)';
        }
        badge = _TandemCellPill(
          label: '$confirmedCount',
          bg: AppTheme.successBg,
          fg: AppTheme.successColor,
          showDot: pendingPilotCount > 0,
          dotColor: AppTheme.infoColor,
        );
      } else if (pendingPilotCount > 0 || pendingAdminCount > 0) {
        final openCnt = pendingPilotCount + pendingAdminCount;
        tooltipText = '$openCnt offene Tandem-Anfrage(n)';
        badge = _TandemCellPill(
          label: '?$openCnt',
          bg: AppTheme.warningBg,
          fg: AppTheme.warningColor,
        );
      }
    } else {
      final ownDuties = duties.where(_isOwnTandemDuty).toList();
      final ownDuty = ownDuties.firstOrNull;
      if (ownDuty != null) {
        if (ownDuty.status == TandemDutyStatus.confirmed) {
          tooltipText = 'Du bist als Tandempilot eingeteilt';
          badge = const _TandemCellPill(
            label: 'Tandem',
            bg: AppTheme.successBg,
            fg: AppTheme.successColor,
          );
        } else if (ownDuty.status == TandemDutyStatus.cancellationRequested) {
          tooltipText = 'Tandem-Absage angefragt – wartet auf Bestätigung';
          badge = const _TandemCellPill(
            label: 'Absage?',
            bg: AppTheme.warningBg,
            fg: AppTheme.warningColor,
          );
        } else if (ownDuty.status == TandemDutyStatus.requestedByAdmin) {
          tooltipText = 'Tandem-Anfrage der Flugschule – bitte bestätigen';
          badge = const _TandemCellPill(
            label: 'Anfrage',
            bg: AppTheme.warningBg,
            fg: AppTheme.warningColor,
          );
        } else {
          tooltipText = 'Deine Tandem-Anfrage wartet auf Freigabe';
          badge = const _TandemCellPill(
            label: 'Angefragt',
            bg: Color(0xFFECEEF3),
            fg: Color(0xFF4B5563),
          );
        }
      } else if (target != null && confirmedCount < target) {
        final missing = target - confirmedCount;
        tooltipText =
            'Noch $missing Tandempilot${missing == 1 ? '' : 'en'} gesucht ($confirmedCount/$target)';
        badge = _TandemCellPill(
          label: '+$missing',
          bg: AppTheme.infoBg,
          fg: AppTheme.infoColor,
        );
      } else if (confirmedCount > 0) {
        tooltipText = 'Tandempiloten eingeteilt';
        badge = _TandemCellPill(
          label: '',
          bg: cs.outlineVariant.withValues(alpha: 0.35),
          fg: cs.onSurfaceVariant,
        );
      }
    }

    return Opacity(
      opacity: inMonth ? 1.0 : 0.48,
      child: Container(
        height: 22,
        padding: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.45),
              width: 0.75,
            ),
          ),
        ),
        child: Center(
          child: badge != null
              ? Tooltip(message: tooltipText, child: badge)
              : Icon(
                  Icons.paragliding_rounded,
                  size: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.18),
                ),
        ),
      ),
    );
  }

  void _handleDayTap(DateTime day) {
    final normalized = _dateOnly(day);
    setState(() => _selectedDay = normalized);
    widget.onSelectedDayChanged?.call(normalized);

    final dayEvents = _eventsForDay(normalized);
    final dayAvails = _availabilitiesForDay(normalized);
    final dayStage1 = _stage1PeriodsForDay(normalized);

    // Admin ohne Events & ohne Verfügbarkeiten & ohne aktive Tandemplanung -> direkt Event anlegen
    if (!widget.showTandemSection &&
        dayEvents.isEmpty &&
        dayAvails.isEmpty &&
        widget.onCreateEventForDay != null &&
        widget.onCreateAvailabilityForDay == null) {
      widget.onCreateEventForDay!(normalized);
      return;
    }

    _showEventsBottomSheet(
      title: _fmtDate(normalized),
      events: dayEvents,
      availabilities: dayAvails,
      stage1Periods: dayStage1,
      selectedDate: normalized,
      createForDate: widget.onCreateEventForDay != null ? normalized : null,
    );
  }

  Widget _buildSheetTandemSection(
    BuildContext sheetCtx,
    DateTime selectedDate, {
    bool mutedByEventConflict = false,
    bool isPastDay = false,
  }) {
    final cs = Theme.of(sheetCtx).colorScheme;
    final duties = _tandemDutiesForDay(selectedDate);
    final confirmed =
        duties.where((d) => d.status == TandemDutyStatus.confirmed).toList();
    final target = _tandemTargetForDay(selectedDate);

    if (widget.isAdminTandemView) {
      final demandLabel = target != null && target > 0
          ? '${confirmed.length} / $target besetzt'
          : '${confirmed.length} bestätigt';
      final demandOk = target == null || confirmed.length >= target;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.paragliding_rounded,
                size: 16,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 6),
              Text(
                'Tandemplanung',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: demandLabel,
                foreground:
                    demandOk ? AppTheme.successColor : AppTheme.warningColor,
                background: demandOk ? AppTheme.successBg : AppTheme.warningBg,
                fontSize: 10.5,
              ),
              const Spacer(),
              if (widget.onAdminAssignTandem != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    widget.onAdminAssignTandem!(selectedDate);
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Pilot'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (duties.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                target != null && target > 0
                    ? 'Noch kein Tandempilot eingeteilt (Bedarf: $target).'
                    : 'Noch kein Tandempilot für diesen Tag eingeteilt.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            )
          else
            ...duties.map((d) {
              final pilotName =
                  widget.resolveUserName?.call(d.userId) ?? 'Tandempilot';
              final isConfirmed = d.status == TandemDutyStatus.confirmed;
              final isPilotReq = d.status == TandemDutyStatus.requestedByPilot;
              final color = isConfirmed
                  ? AppTheme.successColor
                  : (isPilotReq ? AppTheme.infoColor : AppTheme.warningColor);
              final statusText = isConfirmed
                  ? 'Bestätigt'
                  : (isPilotReq ? 'Pilot fragt an' : 'Admin-Anfrage offen');

              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: color.withValues(alpha: 0.14),
                            child: Icon(
                              Icons.paragliding_rounded,
                              size: 15,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pilotName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  '${d.dateRangeLabel} · ${d.timeWindowLabel}'
                                  '${d.notes.isNotEmpty ? ' · ${d.notes}' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StatusPill(
                            label: statusText,
                            foreground: color,
                            background: color.withValues(alpha: 0.13),
                            fontSize: 10.5,
                          ),
                          if (widget.onDeleteTandemDuty != null)
                            IconButton(
                              tooltip: 'Einteilung entfernen',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: AppTheme.dangerColor,
                              ),
                              onPressed: () async {
                                Navigator.pop(sheetCtx);
                                await widget.onDeleteTandemDuty!(d);
                              },
                            ),
                        ],
                      ),
                      if ((isPilotReq ||
                              d.status ==
                                  TandemDutyStatus.cancellationRequested) &&
                          widget.onDecideTandemDuty != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: d.status ==
                                          TandemDutyStatus.cancellationRequested
                                      ? AppTheme.dangerColor
                                      : null,
                                ),
                                onPressed: () async {
                                  Navigator.pop(sheetCtx);
                                  await widget.onDecideTandemDuty!(d, true);
                                },
                                icon: const Icon(Icons.check, size: 16),
                                label: Text(
                                  d.status ==
                                          TandemDutyStatus.cancellationRequested
                                      ? 'Absage bestätigen'
                                      : 'Freigeben',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: d.status ==
                                          TandemDutyStatus.cancellationRequested
                                      ? null
                                      : AppTheme.dangerColor,
                                ),
                                onPressed: () async {
                                  Navigator.pop(sheetCtx);
                                  await widget.onDecideTandemDuty!(d, false);
                                },
                                icon: const Icon(Icons.close, size: 16),
                                label: Text(
                                  d.status ==
                                          TandemDutyStatus.cancellationRequested
                                      ? 'Bleibt aktiv'
                                      : 'Ablehnen',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
        ],
      );
    }

    // Nutzer-Ansicht (nur für berechtigte Tandempiloten aktiv)
    final ownDuties = duties.where(_isOwnTandemDuty).toList();
    final ownDuty = ownDuties.firstOrNull;
    final isOwnConfirmed = ownDuty?.status == TandemDutyStatus.confirmed;
    final isOwnCancelReq =
        ownDuty?.status == TandemDutyStatus.cancellationRequested;
    final isOwnScheduled = isOwnConfirmed || isOwnCancelReq;
    final otherConfirmed = isOwnScheduled
        ? confirmed.where((d) => !_isOwnTandemDuty(d)).toList()
        : const <TandemDuty>[];
    final missing =
        target != null && confirmed.length < target ? target - confirmed.length : 0;
    final disableTandemByEvent = mutedByEventConflict && !isOwnScheduled;
    final disableTandemByPast = isPastDay && !isOwnScheduled;
    final disableTandemActions = disableTandemByEvent || disableTandemByPast;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.paragliding_rounded,
              size: 16,
              color: disableTandemActions
                  ? cs.onSurfaceVariant
                  : AppTheme.primaryColor,
            ),
            const SizedBox(width: 6),
            Text(
              'Tandem',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            if (disableTandemByPast)
              StatusPill(
                label: 'Vergangener Tag',
                foreground: cs.onSurfaceVariant,
                background: cs.outlineVariant.withValues(alpha: 0.35),
                fontSize: 10.5,
              )
            else if (disableTandemByEvent)
              StatusPill(
                label: 'Bereits in Event eingeplant',
                foreground: cs.onSurfaceVariant,
                background: cs.outlineVariant.withValues(alpha: 0.35),
                fontSize: 10.5,
              )
            else if (missing > 0)
              StatusPill(
                label: 'Noch $missing gesucht (${confirmed.length}/$target)',
                foreground: AppTheme.infoColor,
                background: AppTheme.infoBg,
                fontSize: 10.5,
              )
            else if (confirmed.isNotEmpty)
              StatusPill(
                label: isOwnConfirmed
                    ? 'Du bist eingeteilt'
                    : 'Piloten eingeteilt',
                foreground:
                    isOwnConfirmed ? AppTheme.successColor : cs.onSurfaceVariant,
                background: isOwnConfirmed
                    ? AppTheme.successBg
                    : cs.outlineVariant.withValues(alpha: 0.35),
                fontSize: 10.5,
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (ownDuty != null)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: (isOwnScheduled && widget.onOwnTandemDutyTap != null)
                  ? () {
                      Navigator.pop(sheetCtx);
                      widget.onOwnTandemDutyTap!(ownDuty);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: (isOwnConfirmed
                                  ? AppTheme.successColor
                                  : AppTheme.warningColor)
                              .withValues(alpha: 0.14),
                          child: Icon(
                            Icons.paragliding_rounded,
                            size: 15,
                            color: isOwnConfirmed
                                ? AppTheme.successColor
                                : AppTheme.warningColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isOwnConfirmed
                                    ? 'Dein Tandem-Einsatz (Bestätigt)'
                                    : isOwnCancelReq
                                        ? 'Dein Tandem-Einsatz (Absage angefragt)'
                                        : ownDuty.status ==
                                                TandemDutyStatus
                                                    .requestedByAdmin
                                            ? 'Tandem-Anfrage der Flugschule'
                                            : 'Deine Tandem-Anfrage (offen)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              Text(
                                '${ownDuty.dateRangeLabel} · ${ownDuty.timeWindowLabel}'
                                '${ownDuty.notes.isNotEmpty ? ' · ${ownDuty.notes}' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isOwnScheduled &&
                            widget.onOwnTandemDutyTap != null)
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: cs.onSurfaceVariant,
                          ),
                        if (ownDuty.status ==
                                TandemDutyStatus.requestedByPilot &&
                            widget.onDeleteTandemDuty != null)
                          IconButton(
                            tooltip: 'Anfrage zurückziehen',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppTheme.dangerColor,
                            ),
                            onPressed: () async {
                              Navigator.pop(sheetCtx);
                              await widget.onDeleteTandemDuty!(ownDuty);
                            },
                          ),
                      ],
                    ),
                    if (ownDuty.status == TandemDutyStatus.requestedByAdmin &&
                        widget.onDecideTandemDuty != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                Navigator.pop(sheetCtx);
                                await widget.onDecideTandemDuty!(ownDuty, true);
                              },
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Zusagen'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: AppTheme.dangerColor,
                              ),
                              onPressed: () async {
                                Navigator.pop(sheetCtx);
                                await widget.onDecideTandemDuty!(
                                  ownDuty,
                                  false,
                                );
                              },
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Ablehnen'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        // Anforderung 7: Namen der anderen Piloten NUR anzeigen, wenn man selbst bestätigt eingeteilt ist!
        if (isOwnConfirmed && otherConfirmed.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weitere eingeteilte Tandempiloten',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: otherConfirmed.map((other) {
                      final name =
                          widget.resolveUserName?.call(other.userId) ??
                              'Tandempilot';
                      return Chip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: const Icon(
                          Icons.paragliding_rounded,
                          size: 14,
                          color: AppTheme.successColor,
                        ),
                        label: Text(
                          other.isFullDay
                              ? name
                              : '$name (${other.timeWindowLabel})',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (ownDuty == null && widget.onPilotRequestTandem != null) ...[
          OutlinedButton.icon(
            onPressed: disableTandemActions
                ? null
                : () {
                    Navigator.pop(sheetCtx);
                    widget.onPilotRequestTandem!(selectedDate);
                  },
            icon: const Icon(Icons.paragliding_rounded, size: 18),
            label: Text(
              disableTandemByPast
                  ? 'Vergangener Tag – keine Anfrage möglich'
                  : disableTandemByEvent
                      ? 'Tandem nicht verfügbar (Event eingeplant)'
                      : missing > 0
                          ? 'Für Tandem anfragen (Bedarf offen)'
                          : 'Als Tandempilot anfragen',
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );

    if (disableTandemActions) {
      return Opacity(
        opacity: 0.45,
        child: IgnorePointer(child: content),
      );
    }
    return content;
  }

  void _showEventsBottomSheet({
    required String title,
    required List<Event> events,
    List<AvailabilitySubmission> availabilities = const [],
    List<PlanningPeriod> stage1Periods = const [],
    DateTime? selectedDate,
    DateTime? createForDate,
  }) {
    showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      desktopMaxWidth: 620,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final availList = availabilities
            .where((a) => a.kind == AvailabilityKind.available)
            .toList();
        final blackoutList = availabilities
            .where((a) => a.kind == AvailabilityKind.blackout)
            .toList();

        final isUserView =
            !widget.isAdminTandemView && !widget.isAdminAvailabilityView;
        final today = _dateOnly(DateTime.now());
        final isPastDay = isUserView &&
            selectedDate != null &&
            _dateOnly(selectedDate).isBefore(today);
        final hasConfirmedEventOnDay = isUserView &&
            events.any(
              (e) =>
                  e.isOwnBindingAssignment &&
                  e.status != EventStatusEnum.canceled,
            );
        final hasConfirmedTandemOnDay = isUserView &&
            selectedDate != null &&
            widget.showTandemSection &&
            _tandemDutiesForDay(selectedDate).any(
              (d) =>
                  _isOwnTandemDuty(d) &&
                  d.status == TandemDutyStatus.confirmed,
            );
        final muteAvailabilityButtons =
            isPastDay || hasConfirmedEventOnDay || hasConfirmedTandemOnDay;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.72,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (stage1Periods.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Stufe 1 – Verfügbarkeit (${stage1Periods.map((p) => p.seasonLabel).join(', ')})',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.stage1Color,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (selectedDate != null &&
                          widget.showTandemSection &&
                          widget.isAdminTandemView &&
                          widget.onManageTandemDemand != null) ...[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            widget.onManageTandemDemand!(selectedDate);
                          },
                          icon: const Icon(Icons.paragliding_rounded, size: 17),
                          label: const Text('Bedarf'),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (createForDate != null &&
                          widget.onCreateEventForDay != null)
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            widget.onCreateEventForDay!(createForDate);
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Neues Event'),
                        ),
                    ],
                  ),
                  if (selectedDate != null &&
                      widget.onCreateAvailabilityForDay != null) ...[
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: isPastDay
                          ? 0.42
                          : (muteAvailabilityButtons ? 0.48 : 1.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: muteAvailabilityButtons
                                    ? cs.surfaceContainerHighest
                                    : AppTheme.successColor,
                                foregroundColor: muteAvailabilityButtons
                                    ? cs.onSurfaceVariant
                                    : Colors.white,
                              ),
                              onPressed: isPastDay
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      widget.onCreateAvailabilityForDay!(
                                        selectedDate,
                                        AvailabilityKind.available,
                                      );
                                    },
                              icon: const Icon(Icons.event_available, size: 18),
                              label: const Text('Verfügbar eintragen'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: muteAvailabilityButtons
                                    ? cs.onSurfaceVariant
                                    : AppTheme.dangerColor,
                                side: BorderSide(
                                  color: (muteAvailabilityButtons
                                          ? cs.outline
                                          : AppTheme.dangerColor)
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                              onPressed: isPastDay
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      widget.onCreateAvailabilityForDay!(
                                        selectedDate,
                                        AvailabilityKind.blackout,
                                      );
                                    },
                              icon: const Icon(Icons.event_busy, size: 18),
                              label: const Text('Abwesend'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (selectedDate != null && widget.showTandemSection)
                            _buildSheetTandemSection(
                              ctx,
                              selectedDate,
                              mutedByEventConflict: hasConfirmedEventOnDay,
                              isPastDay: isPastDay,
                            ),
                          if (availList.isNotEmpty || blackoutList.isNotEmpty) ...[
                            Text(
                              widget.isAdminAvailabilityView
                                  ? 'Team-Verfügbarkeiten'
                                  : 'Deine Einträge an diesem Tag',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...availabilities.map((s) {
                              final isAvail =
                                  s.kind == AvailabilityKind.available;
                              final color =
                                  isAvail
                                      ? AppTheme.successColor
                                      : AppTheme.dangerColor;
                              final name =
                                  widget.isAdminAvailabilityView
                                      ? (widget.resolveUserName?.call(
                                            s.userId,
                                          ) ??
                                          'Teammitglied')
                                      : (isAvail ? 'Verfügbar' : 'Abwesend');
                              return Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 15,
                                    backgroundColor: color.withValues(
                                      alpha: 0.14,
                                    ),
                                    child: Icon(
                                      isAvail
                                          ? Icons.event_available
                                          : Icons.event_busy,
                                      size: 16,
                                      color: color,
                                    ),
                                  ),
                                  title: Text(
                                    widget.isAdminAvailabilityView
                                        ? '$name · ${isAvail ? "Verfügbar" : "Abwesend"}'
                                        : name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${_fmtDate(s.startDate)} – ${_fmtDate(s.endDate)}'
                                    '${s.notes.isNotEmpty ? ' · ${s.notes}' : ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing:
                                      widget.onDeleteAvailability != null &&
                                              !isPastDay
                                          ? IconButton(
                                            tooltip: 'Eintrag löschen',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 19,
                                              color: AppTheme.dangerColor,
                                            ),
                                            onPressed: () async {
                                              Navigator.pop(ctx);
                                              await widget
                                                  .onDeleteAvailability!(s);
                                            },
                                          )
                                          : null,
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                          ],
                          if (events.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'Keine Events für diesen Tag eingetragen.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            )
                          else ...[
                            if (availabilities.isNotEmpty ||
                                hasConfirmedTandemOnDay) ...[
                              Row(
                                children: [
                                  Text(
                                    'Events',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  if (hasConfirmedTandemOnDay) ...[
                                    const SizedBox(width: 8),
                                    StatusPill(
                                      label: 'Bereits im Tandem eingeplant',
                                      foreground: cs.onSurfaceVariant,
                                      background: cs.outlineVariant
                                          .withValues(alpha: 0.35),
                                      fontSize: 10.5,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                            for (var i = 0; i < events.length; i++) ...[
                              () {
                                final ev = events[i];
                                final mutedByConflict =
                                    (hasConfirmedTandemOnDay || isPastDay) &&
                                    !ev.isOwnBindingAssignment;
                                return _buildAgendaTile(
                                  ev,
                                  mutedByConflict: mutedByConflict,
                                  onTap: mutedByConflict
                                      ? null
                                      : () {
                                          Navigator.pop(ctx);
                                          widget.onEventTap?.call(ev);
                                        },
                                );
                              }(),
                              if (i != events.length - 1)
                                const SizedBox(height: 8),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAgendaTile(
    Event ev, {
    VoidCallback? onTap,
    bool mutedByConflict = false,
  }) {
    final isApplied = _isAppliedEvent(ev);
    final isDirectRequest = _isDirectRequestEvent(ev);
    final isExtendedRedacted = _isExtendedTeamRedacted(ev);
    final isOpenOpp = _isOpenOpportunityEvent(ev);
    final isStage1 = _isStage1Redacted(ev);
    final style = _EventBarStyle.from(
      ev,
      isStage1Redacted: isStage1,
      isExtendedTeamRedacted: isExtendedRedacted,
      isApplied: isApplied,
      isDirectRequest: isDirectRequest,
      isOpenOpportunity: isOpenOpp,
    );
    final hasSwap =
        !isStage1 &&
        !isExtendedRedacted &&
        !isApplied &&
        (ev.isSwapOfferFromOther ||
            ev.hasOpenSwapRequest ||
            ev.team.any((t) => t.hasOpenSwapRequest));
    final fs = widget.flightSchoolById(ev.flightSchoolId);
    final fsName = _EventBar._fsName(fs);
    final isCanceled = ev.status == EventStatusEnum.canceled;
    final cs = Theme.of(context).colorScheme;

    return Opacity(
      opacity: mutedByConflict ? 0.45 : (isApplied ? 0.72 : 1.0),
      child: CanceledEventDecorator(
        isCanceled: isCanceled,
        borderRadius: BorderRadius.circular(18),
        child: Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Container(
              width: 10,
              height: 36,
              decoration: BoxDecoration(
                color: mutedByConflict ? cs.outline : style.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    ev.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: (isApplied || mutedByConflict)
                          ? cs.onSurfaceVariant
                          : null,
                      decoration:
                          isCanceled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              if (isApplied)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Beworben – wartet auf Bestätigung',
                    child: Icon(
                      Icons.hourglass_top_rounded,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),
                ),
              if (isDirectRequest)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Direktanfrage – Bestätigung offen',
                    child: Icon(
                      Icons.notifications_active_outlined,
                      size: 17,
                      color: AppTheme.warningColor,
                    ),
                  ),
                ),
              if (isOpenOpp && !ev.isSwapOfferFromOther)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Offene Stelle – jetzt bewerben',
                    child: Icon(
                      Icons.person_add_alt_1_outlined,
                      size: 17,
                      color: AppTheme.infoColor,
                    ),
                  ),
                ),
              if (hasSwap)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Offene Tauschanfrage',
                    child: Icon(
                      Icons.swap_horiz,
                      size: 18,
                      color: AppTheme.swapColor,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Text(
            [
              if (widget.showFlightSchool && fsName.isNotEmpty) fsName,
              '${_fmtDate(ev.startTime)} ${_fmtTime(ev.startTime)} – ${_fmtDate(ev.endTime)} ${_fmtTime(ev.endTime)}',
              if (isDirectRequest)
                'Angefragt${ev.role.isNotEmpty ? ' (${ev.roleLabel})' : ''} · Bitte bestätigen'
              else if (isApplied)
                'Beworben${ev.role.isNotEmpty ? ' (${ev.roleLabel})' : ''} · wartet auf Bestätigung'
              else if (isOpenOpp)
                ev.isSwapOfferFromOther
                    ? 'Tauschplatz frei${ev.role.isNotEmpty ? ' (${ev.roleLabel})' : ''}'
                    : 'Offene Stelle${ev.role.isNotEmpty ? ' (${ev.roleLabel})' : ''} · Jetzt bewerben'
              else if (isExtendedRedacted)
                null
              else if (isStage1)
                'Stufe 1 – Verfügbarkeit eintragen'
              else if (widget.redactStage1 &&
                  ev.isOwnBindingAssignment &&
                  ev.role.isNotEmpty)
                'Eingeteilt: ${ev.roleLabel}'
              else
                ev.status.label,
            ].whereType<String>().join(' · '),
            style: const TextStyle(fontSize: 12.5),
          ),
            trailing: mutedByConflict ? null : const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final days = List<DateTime>.from(_daysForMonthGrid(_visibleMonth));
    while (days.length % 7 != 0) {
      days.add(days.last.add(const Duration(days: 1)));
    }

    final weeks = <List<DateTime>>[];
    for (var i = 0; i < days.length; i += 7) {
      weeks.add(days.sublist(i, i + 7));
    }

    final now = DateTime.now();
    final isCurrentMonth =
        _visibleMonth.year == now.year && _visibleMonth.month == now.month;
    final isCompactScreen = MediaQuery.of(context).size.width < 520;

    return SizedBox.expand(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _horizontalSwipeDelta = 0,
        onHorizontalDragUpdate: (details) {
          _horizontalSwipeDelta += details.delta.dx;
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -220 || _horizontalSwipeDelta < -55) {
            _nextMonth();
          } else if (velocity > 220 || _horizontalSwipeDelta > 55) {
            _prevMonth();
          }
          _horizontalSwipeDelta = 0;
        },
        onHorizontalDragCancel: () => _horizontalSwipeDelta = 0,
        child: SoftCard(
          margin: isCompactScreen
              ? const EdgeInsets.fromLTRB(8, 4, 8, 4)
              : const EdgeInsets.all(10),
          padding: isCompactScreen
              ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
              : const EdgeInsets.all(14),
          radius: 20,
          child: Column(
            children: [
              _Header(
                month: _visibleMonth,
                isCurrentMonth: isCurrentMonth,
                displayMode: _displayMode,
                onPrev: _prevMonth,
                onNext: _nextMonth,
                onToday: _jumpToToday,
                onModeChanged: (mode) => setState(() => _displayMode = mode),
              ),
              const SizedBox(height: 6),
              Builder(
                builder: (context) {
                  final isCompact = MediaQuery.of(context).size.width < 520;
                  final legendWidget = _LegendRow(
                    showStage1:
                        widget.redactStage1 || widget.stage1Periods.isNotEmpty,
                    showApplied: widget.redactStage1,
                    showAvailability:
                        widget.availabilityEntries.isNotEmpty ||
                        widget.isAdminAvailabilityView ||
                        widget.onCreateAvailabilityForDay != null,
                    showBlackout:
                        widget.availabilityEntries.any(
                          (a) => a.kind == AvailabilityKind.blackout,
                        ) ||
                        widget.onCreateAvailabilityForDay != null,
                    showTandem: widget.showTandemSection,
                  );

                  if (!isCompact) return legendWidget;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => setState(
                          () => _legendExpanded = !_legendExpanded,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final c in const [
                                AppTheme.infoColor,
                                AppTheme.successColor,
                                AppTheme.stage1Color,
                                AppTheme.dangerColor,
                              ])
                                Container(
                                  width: 7,
                                  height: 7,
                                  margin: const EdgeInsets.only(right: 3),
                                  decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              const SizedBox(width: 4),
                              Text(
                                _legendExpanded
                                    ? 'Legende ausblenden'
                                    : 'Legende',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              Icon(
                                _legendExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_legendExpanded) ...[
                        const SizedBox(height: 6),
                        legendWidget,
                      ],
                    ],
                  );
                },
              ),
              if (_stage1PeriodsForMonth(_visibleMonth).isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.stage1Color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.stage1Color.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.layers_outlined,
                        size: 16,
                        color: AppTheme.stage1Color,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.onCreateAvailabilityForDay != null
                              ? 'Stufe 1 (${_stage1PeriodsForMonth(_visibleMonth).map((p) => p.seasonLabel).join(', ')}): Tippe auf einen Tag, um Verfügbarkeit einzutragen.'
                              : 'Stufe 1 aktiv (${_stage1PeriodsForMonth(_visibleMonth).map((p) => p.seasonLabel).join(', ')}) – Team trägt Verfügbarkeiten ein.',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.stage1Color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Divider(height: 1),
              if (_displayMode == _CalendarDisplayMode.agenda) ...[
                const SizedBox(height: 8),
                Expanded(child: _buildMonthAgenda()),
              ] else ...[
                const SizedBox(height: 8),
                Row(
                  children:
                      _weekdays
                          .map(
                            (w) => Expanded(
                              child: Center(
                                child: Text(
                                  w,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cellW = constraints.maxWidth / 7;
                      const laneH = 22.0;
                      const laneGap = 4.0;
                      const maxLanesShown = 3;

                      const availLaneH = 5.0;
                      const availLaneGap = 2.0;
                      const maxAvailLanesShown = 3;

                      const dayHPad = 2.0;
                      const dayBorderW = 1.0;
                      const dayInnerMarginH = 2.0;
                      const eventOuterPad =
                          dayHPad + dayBorderW + dayInnerMarginH;
                      const eventInnerPad = 2.0;

                      // Wochenzeilen an verfügbare Höhe anpassen, sodass der Monat
                      // möglichst ohne vertikales Scrollen vollständig ins Bild passt
                      final minRowH = (constraints.maxHeight / weeks.length)
                          .clamp(
                            widget.showTandemSection ? 68.0 : 58.0,
                            185.0,
                          );

                      return SingleChildScrollView(
                        child: Column(
                          children:
                              weeks.map((weekDays) {
                                final weekStart = _dateOnly(weekDays.first);
                                final weekEnd = _dateOnly(weekDays.last);
                                final lanes = _laneEventsForWeek(
                                  weekStart,
                                  weekEnd,
                                );
                                final availLanes = _laneAvailabilitiesForWeek(
                                  weekStart,
                                  weekEnd,
                                );

                                final shownLanes =
                                    lanes.length > maxLanesShown
                                        ? maxLanesShown
                                        : lanes.length;
                                final hasMore = lanes.length > maxLanesShown;

                                final shownAvailLanes =
                                    availLanes.length > maxAvailLanesShown
                                        ? maxAvailLanesShown
                                        : availLanes.length;
                                final availBlockH =
                                    shownAvailLanes == 0
                                        ? 0.0
                                        : (shownAvailLanes * availLaneH +
                                            (shownAvailLanes - 1) *
                                                availLaneGap +
                                            8.0);
                                final tandemBlockH =
                                    widget.showTandemSection ? 26.0 : 0.0;

                                final contentH =
                                    42.0 +
                                    (shownLanes == 0
                                        ? 0
                                        : (shownLanes * laneH +
                                            (shownLanes - 1) * laneGap)) +
                                    (hasMore ? 26 : 0) +
                                    tandemBlockH +
                                    availBlockH +
                                    10;
                                final rowH =
                                    contentH > minRowH ? contentH : minRowH;

                                return SizedBox(
                                  height: rowH,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: Row(
                                          children:
                                              weekDays.map((d) {
                                                final isToday = _isSameDay(
                                                  d,
                                                  DateTime.now(),
                                                );
                                                final inMonth = _isInMonth(
                                                  d,
                                                  _visibleMonth,
                                                );
                                                final isSelected =
                                                    _selectedDay != null &&
                                                    _isSameDay(
                                                      d,
                                                      _selectedDay!,
                                                    );
                                                final isStage1Day =
                                                    _stage1PeriodsForDay(
                                                      d,
                                                    ).isNotEmpty;
                                                final dayAvails =
                                                    _availabilitiesForDay(d);
                                                final availCount =
                                                    dayAvails
                                                        .where(
                                                          (a) =>
                                                              a.kind ==
                                                              AvailabilityKind
                                                                  .available,
                                                        )
                                                        .map((a) => a.userId)
                                                        .toSet()
                                                        .length;
                                                final blackoutCount =
                                                    dayAvails
                                                        .where(
                                                          (a) =>
                                                              a.kind ==
                                                              AvailabilityKind
                                                                  .blackout,
                                                        )
                                                        .length;

                                                final fg =
                                                    inMonth
                                                        ? cs.onSurface
                                                        : cs.onSurfaceVariant
                                                            .withValues(
                                                              alpha: 0.55,
                                                            );

                                                final cellBg =
                                                    isSelected
                                                        ? cs.primaryContainer
                                                            .withValues(
                                                              alpha: 0.35,
                                                            )
                                                        : isStage1Day
                                                        ? AppTheme.stage1Color
                                                            .withValues(
                                                              alpha:
                                                                  inMonth
                                                                      ? 0.11
                                                                      : 0.05,
                                                            )
                                                        : Colors.transparent;

                                                final cellBorderColor =
                                                    isToday
                                                        ? cs.primary
                                                        : isStage1Day
                                                        ? AppTheme.stage1Color
                                                            .withValues(
                                                              alpha:
                                                                  inMonth
                                                                      ? 0.42
                                                                      : 0.22,
                                                            )
                                                        : cs.outlineVariant
                                                            .withValues(
                                                              alpha: 0.6,
                                                            );

                                                return Expanded(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: dayHPad,
                                                        ),
                                                    child: Container(
                                                      margin:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 3,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              14,
                                                            ),
                                                        border: Border.all(
                                                          color:
                                                              cellBorderColor,
                                                          width:
                                                              isToday
                                                                  ? 1.6
                                                                  : dayBorderW,
                                                        ),
                                                        color: cellBg,
                                                      ),
                                                      child: InkWell(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              14,
                                                            ),
                                                        onTap:
                                                            () => _handleDayTap(
                                                              d,
                                                            ),
                                                        child: Container(
                                                          margin: const EdgeInsets.symmetric(
                                                            horizontal:
                                                                dayInnerMarginH,
                                                            vertical: 2,
                                                          ),
                                                          padding: EdgeInsets.fromLTRB(
                                                            5,
                                                            5,
                                                            5,
                                                            widget.showTandemSection
                                                                ? (shownAvailLanes > 0
                                                                    ? availBlockH + 2
                                                                    : 3)
                                                                : 5,
                                                          ),
                                                          child: Column(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .spaceBetween,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            children: [
                                                              Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .spaceBetween,
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Container(
                                                                    padding:
                                                                        const EdgeInsets.symmetric(
                                                                          horizontal:
                                                                              6,
                                                                          vertical:
                                                                              2,
                                                                        ),
                                                                    decoration:
                                                                        isToday
                                                                            ? BoxDecoration(
                                                                              color:
                                                                                  cs.primary,
                                                                              borderRadius: BorderRadius.circular(
                                                                                999,
                                                                              ),
                                                                            )
                                                                            : null,
                                                                    child: Text(
                                                                      "${d.day}",
                                                                      style: TextStyle(
                                                                        fontSize:
                                                                            12.5,
                                                                        fontWeight:
                                                                            isToday
                                                                                ? FontWeight.w800
                                                                                : FontWeight.w500,
                                                                        color:
                                                                            isToday
                                                                                ? cs.onPrimary
                                                                                : fg,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  if (widget
                                                                          .isAdminAvailabilityView &&
                                                                      availCount >
                                                                          0)
                                                                    Tooltip(
                                                                      message:
                                                                          '$availCount Mitarbeiter verfügbar',
                                                                      child: Container(
                                                                        padding: const EdgeInsets.symmetric(
                                                                          horizontal:
                                                                              4,
                                                                          vertical:
                                                                              1,
                                                                        ),
                                                                        decoration: BoxDecoration(
                                                                          color: AppTheme
                                                                              .successColor
                                                                              .withValues(
                                                                                alpha:
                                                                                    0.18,
                                                                              ),
                                                                          borderRadius: BorderRadius.circular(
                                                                            999,
                                                                          ),
                                                                        ),
                                                                        child: Text(
                                                                          '$availCount',
                                                                          style: const TextStyle(
                                                                            fontSize:
                                                                                10,
                                                                            fontWeight:
                                                                                FontWeight.w800,
                                                                            color:
                                                                                AppTheme.successColor,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    )
                                                                  else if (!widget
                                                                          .isAdminAvailabilityView &&
                                                                      (availCount >
                                                                              0 ||
                                                                          blackoutCount >
                                                                              0))
                                                                    Row(
                                                                      mainAxisSize:
                                                                          MainAxisSize
                                                                              .min,
                                                                      children: [
                                                                        if (availCount >
                                                                            0)
                                                                          Container(
                                                                            width:
                                                                                6,
                                                                            height:
                                                                                6,
                                                                            decoration: const BoxDecoration(
                                                                              color:
                                                                                  AppTheme.successColor,
                                                                              shape:
                                                                                  BoxShape.circle,
                                                                            ),
                                                                          ),
                                                                        if (blackoutCount >
                                                                            0) ...[
                                                                          const SizedBox(
                                                                            width:
                                                                                2,
                                                                          ),
                                                                          Container(
                                                                            width:
                                                                                6,
                                                                            height:
                                                                                6,
                                                                            decoration: const BoxDecoration(
                                                                              color:
                                                                                  AppTheme.dangerColor,
                                                                              shape:
                                                                                  BoxShape.circle,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ],
                                                                    ),
                                                                ],
                                                              ),
                                                              if (widget
                                                                  .showTandemSection)
                                                                _buildCellTandemStrip(
                                                                  d,
                                                                  inMonth:
                                                                      inMonth,
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                        ),
                                      ),
                                      if (lanes.isNotEmpty)
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          top: 34,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: eventInnerPad,
                                            ),
                                            child: Column(
                                              children: [
                                                for (
                                                  var laneIndex = 0;
                                                  laneIndex < shownLanes;
                                                  laneIndex++
                                                ) ...[
                                                  SizedBox(
                                                    height: laneH,
                                                    child: Stack(
                                                      children: [
                                                        for (final we
                                                            in lanes[laneIndex])
                                                          Positioned(
                                                            left:
                                                                we.startIdx *
                                                                    cellW +
                                                                eventOuterPad +
                                                                eventInnerPad,
                                                            width: ((we.endIdx -
                                                                            we.startIdx +
                                                                            1) *
                                                                        cellW -
                                                                    (2 *
                                                                        (eventOuterPad +
                                                                            eventInnerPad)))
                                                                .clamp(
                                                                  18.0,
                                                                  double
                                                                      .infinity,
                                                                ),
                                                            top: 0,
                                                            bottom: 0,
                                                            child: _EventBar(
                                                              event: we.event,
                                                              flightSchool: widget
                                                                  .flightSchoolById(
                                                                    we
                                                                        .event
                                                                        .flightSchoolId,
                                                                  ),
                                                              onTap:
                                                                  widget.onEventTap ==
                                                                          null
                                                                      ? null
                                                                      : () => widget
                                                                          .onEventTap!(
                                                                        we.event,
                                                                      ),
                                                              continuesLeft:
                                                                  we.continuesLeft,
                                                              continuesRight:
                                                                  we.continuesRight,
                                                              showFsName:
                                                                  widget
                                                                      .showFlightSchool,
                                                              redactStage1:
                                                                  widget
                                                                      .redactStage1,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (laneIndex !=
                                                      shownLanes - 1)
                                                    const SizedBox(
                                                      height: laneGap,
                                                    ),
                                                ],
                                                if (hasMore)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                          right: 4,
                                                        ),
                                                    child: Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: InkWell(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                        onTap: () {
                                                          final weekEvents =
                                                              widget.events
                                                                  .where(
                                                                    (
                                                                      e,
                                                                    ) => _eventIntersectsRange(
                                                                      e,
                                                                      weekStart,
                                                                      weekEnd,
                                                                    ),
                                                                  )
                                                                  .toList()
                                                                ..sort(
                                                                  (a, b) => a
                                                                      .startTime
                                                                      .compareTo(
                                                                        b.startTime,
                                                                      ),
                                                                );
                                                          _showEventsBottomSheet(
                                                            title:
                                                                'Woche ${_fmtDate(weekStart)} – ${_fmtDate(weekEnd)}',
                                                            events: weekEvents,
                                                          );
                                                        },
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: cs
                                                                .primaryContainer
                                                                .withValues(
                                                                  alpha: 0.7,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  999,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            "+${lanes.length - maxLanesShown} weitere",
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color:
                                                                  cs.onPrimaryContainer,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (shownAvailLanes > 0)
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 7,
                                          child: IgnorePointer(
                                            ignoring: false,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: eventInnerPad,
                                                  ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  for (
                                                    var aIdx = 0;
                                                    aIdx < shownAvailLanes;
                                                    aIdx++
                                                  ) ...[
                                                    SizedBox(
                                                      height: availLaneH,
                                                      child: Stack(
                                                        children: [
                                                          for (final wa
                                                              in availLanes[aIdx])
                                                            Positioned(
                                                              left:
                                                                  wa.startIdx *
                                                                      cellW +
                                                                  eventOuterPad +
                                                                  eventInnerPad,
                                                              width: ((wa.endIdx -
                                                                              wa.startIdx +
                                                                              1) *
                                                                          cellW -
                                                                      (2 *
                                                                          (eventOuterPad +
                                                                              eventInnerPad)))
                                                                  .clamp(
                                                                    10.0,
                                                                    double
                                                                        .infinity,
                                                                  ),
                                                              top: 0,
                                                              bottom: 0,
                                                              child: Tooltip(
                                                                message:
                                                                    _availabilityLabel(
                                                                      wa.submission,
                                                                    ),
                                                                child: GestureDetector(
                                                                  onTap:
                                                                      () =>
                                                                          _handleDayTap(
                                                                            weekDays[wa.startIdx],
                                                                          ),
                                                                  child: Container(
                                                                    decoration: BoxDecoration(
                                                                      color:
                                                                          wa.submission.kind ==
                                                                                  AvailabilityKind.available
                                                                              ? AppTheme.successColor
                                                                              : AppTheme.dangerColor.withValues(
                                                                                alpha: 0.78,
                                                                              ),
                                                                      borderRadius: BorderRadius.only(
                                                                        topLeft: Radius.circular(
                                                                          wa.continuesLeft
                                                                              ? 1
                                                                              : 999,
                                                                        ),
                                                                        bottomLeft: Radius.circular(
                                                                          wa.continuesLeft
                                                                              ? 1
                                                                              : 999,
                                                                        ),
                                                                        topRight: Radius.circular(
                                                                          wa.continuesRight
                                                                              ? 1
                                                                              : 999,
                                                                        ),
                                                                        bottomRight: Radius.circular(
                                                                          wa.continuesRight
                                                                              ? 1
                                                                              : 999,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                    if (aIdx !=
                                                        shownAvailLanes - 1)
                                                      const SizedBox(
                                                        height: availLaneGap,
                                                      ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }).toList(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<TandemDuty> _tandemDutiesForMonth(DateTime monthFirstDay) {
    if (!widget.showTandemSection || widget.tandemDuties.isEmpty) {
      return const [];
    }
    final start = DateTime(monthFirstDay.year, monthFirstDay.month, 1);
    final end = DateTime(monthFirstDay.year, monthFirstDay.month + 1, 0);
    return widget.tandemDuties.where((d) {
      if (d.status == TandemDutyStatus.declined) return false;
      if (!d.overlapsDayRange(start, end)) return false;
      // Nutzer sehen in der Agenda ihre eigenen Tandem-Einsätze/-Anfragen
      // (andere Piloten werden strikt nur am eigenen bestätigten Tag im Tages-Sheet gezeigt).
      if (!widget.isAdminTandemView && !_isOwnTandemDuty(d)) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  Widget _buildTandemAgendaTile(TandemDuty duty) {
    final cs = Theme.of(context).colorScheme;
    final isConfirmed = duty.status == TandemDutyStatus.confirmed;
    final isCancelReq = duty.status == TandemDutyStatus.cancellationRequested;
    final isPilotReq = duty.status == TandemDutyStatus.requestedByPilot;
    final accent = isConfirmed
        ? AppTheme.successColor
        : isCancelReq
            ? AppTheme.dangerColor
            : (isPilotReq
                ? (widget.isAdminTandemView
                    ? AppTheme.infoColor
                    : const Color(0xFF6B7280))
                : AppTheme.warningColor);

    final fs = widget.flightSchoolById(duty.flightSchoolId);
    final fsName = _EventBar._fsName(fs);

    final title = widget.isAdminTandemView
        ? 'Tandem · ${widget.resolveUserName?.call(duty.userId) ?? 'Tandempilot'}'
        : (widget.showFlightSchool && fsName.isNotEmpty
            ? 'Tandempilot · $fsName'
            : 'Tandempilot');

    final statusLabel = isConfirmed
        ? 'Bestätigt'
        : isCancelReq
            ? 'Absage angefragt'
            : isPilotReq
                ? (widget.isAdminTandemView
                    ? 'Pilot fragt an'
                    : 'Wartet auf Freigabe')
                : (widget.isAdminTandemView
                    ? 'Admin-Anfrage offen'
                    : 'Anfrage – bitte bestätigen');

    final canOpenOwnPopup = !widget.isAdminTandemView &&
        _isOwnTandemDuty(duty) &&
        (isConfirmed || isCancelReq) &&
        widget.onOwnTandemDutyTap != null;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          width: 10,
          height: 36,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        title: Row(
          children: [
            Icon(Icons.paragliding_rounded, size: 16, color: accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            StatusPill(
              label: statusLabel,
              foreground: accent,
              background: accent.withValues(alpha: 0.13),
              fontSize: 10.5,
            ),
          ],
        ),
        subtitle: Text(
          [
            duty.dateRangeLabel,
            duty.timeWindowLabel,
            if (duty.notes.isNotEmpty) duty.notes,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: canOpenOwnPopup
            ? () => widget.onOwnTandemDutyTap!(duty)
            : () => _handleDayTap(duty.startDay),
      ),
    );
  }

  Widget _buildMonthAgenda() {
    final monthEvents = _eventsForMonth(_visibleMonth);
    final monthTandem = _tandemDutiesForMonth(_visibleMonth);

    // Für Tandempiloten in der Nutzer-Agenda zählen, wie viele Tage im Monat offenen Bedarf haben
    int openDemandDaysCount = 0;
    DateTime? firstOpenDemandDay;
    if (widget.showTandemSection &&
        !widget.isAdminTandemView &&
        widget.tandemDemands.isNotEmpty) {
      final daysInMonth =
          DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
      for (var dayNum = 1; dayNum <= daysInMonth; dayNum++) {
        final d = DateTime(_visibleMonth.year, _visibleMonth.month, dayNum);
        final target = _tandemTargetForDay(d);
        if (target == null || target <= 0) continue;
        final dayDuties = _tandemDutiesForDay(d);
        final confirmedCount =
            dayDuties.where((x) => x.status == TandemDutyStatus.confirmed).length;
        final hasOwn = dayDuties.any(_isOwnTandemDuty);
        if (!hasOwn && confirmedCount < target) {
          openDemandDaysCount++;
          firstOpenDemandDay ??= d;
        }
      }
    }

    final combined = <({DateTime sortTime, Event? event, TandemDuty? tandem})>[
      for (final ev in monthEvents)
        (sortTime: ev.startTime, event: ev, tandem: null),
      for (final td in monthTandem)
        (sortTime: td.startDate, event: null, tandem: td),
    ]..sort((a, b) => a.sortTime.compareTo(b.sortTime));

    if (combined.isEmpty && openDemandDaysCount == 0) {
      return EmptyStateView(
        icon: Icons.event_note_outlined,
        title:
            'Keine Termine im ${_Header._monthName(_visibleMonth.month)} ${_visibleMonth.year}',
        subtitle:
            widget.onCreateEventForDay != null
                ? 'Tippe auf „Neues Event“ oder wechsle den Monat, um Termine zu planen.'
                : 'In diesem Monat stehen aktuell keine Termine an.',
        actionLabel: widget.onCreateEventForDay != null ? 'Neues Event' : null,
        actionIcon: Icons.add,
        onAction:
            widget.onCreateEventForDay != null
                ? () => widget.onCreateEventForDay!(
                  _selectedDay ??
                      DateTime(_visibleMonth.year, _visibleMonth.month, 1),
                )
                : null,
      );
    }

    final hasDemandBanner = openDemandDaysCount > 0;
    final totalItems = combined.length + (hasDemandBanner ? 1 : 0);

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 76),
      itemCount: totalItems,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        if (hasDemandBanner && idx == 0) {
          return Card(
            margin: EdgeInsets.zero,
            color: AppTheme.infoBg,
            child: ListTile(
              dense: true,
              leading: const CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.paragliding_rounded,
                  size: 17,
                  color: AppTheme.infoColor,
                ),
              ),
              title: Text(
                'Offener Tandem-Bedarf an $openDemandDaysCount ${openDemandDaysCount == 1 ? 'Tag' : 'Tagen'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: AppTheme.infoColor,
                ),
              ),
              subtitle: const Text(
                'Tippe zum Anfragen oder wechsle in die Monatsansicht für alle Tage.',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppTheme.infoColor,
              ),
              onTap: firstOpenDemandDay != null
                  ? () => _handleDayTap(firstOpenDemandDay!)
                  : null,
            ),
          );
        }

        final item = combined[idx - (hasDemandBanner ? 1 : 0)];
        if (item.tandem != null) {
          return _buildTandemAgendaTile(item.tandem!);
        }
        final ev = item.event!;
        return _buildAgendaTile(
          ev,
          onTap:
              widget.onEventTap == null ? null : () => widget.onEventTap!(ev),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final DateTime month;
  final bool isCurrentMonth;
  final _CalendarDisplayMode displayMode;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<_CalendarDisplayMode> onModeChanged;

  const _Header({
    required this.month,
    required this.isCurrentMonth,
    required this.displayMode,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isCompact = w < 500;
        final isVeryCompact = w < 370;
        final label = isVeryCompact
            ? "${_shortMonthName(month.month)} ${month.year}"
            : "${_monthName(month.month)} ${month.year}";

        Widget buildModeButton({
          required _CalendarDisplayMode mode,
          required IconData icon,
          required String text,
        }) {
          final selected = displayMode == mode;
          return Tooltip(
            message: text,
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => onModeChanged(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 9 : 11,
                  vertical: isCompact ? 6 : 6,
                ),
                decoration: BoxDecoration(
                  color: selected ? cs.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: selected && !isDark
                      ? const [
                          BoxShadow(
                            color: Color(0x14101828),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    ),
                    if (!isCompact) ...[
                      const SizedBox(width: 5),
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? cs.onSurface : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        return Row(
          children: [
            IconButton(
              onPressed: onPrev,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints.tightFor(
                width: isCompact ? 30 : 36,
                height: isCompact ? 32 : 36,
              ),
              icon: Icon(
                Icons.chevron_left_rounded,
                size: isCompact ? 20 : 22,
              ),
              tooltip: "Vorheriger Monat",
            ),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: isCompact ? 14.5 : 16.5,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            IconButton(
              onPressed: onNext,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints.tightFor(
                width: isCompact ? 30 : 36,
                height: isCompact ? 32 : 36,
              ),
              icon: Icon(
                Icons.chevron_right_rounded,
                size: isCompact ? 20 : 22,
              ),
              tooltip: "Nächster Monat",
            ),
            SizedBox(width: isCompact ? 4 : 6),
            Material(
              color: isCurrentMonth
                  ? cs.outlineVariant.withValues(alpha: 0.45)
                  : (isDark ? cs.primaryContainer : AppTheme.primaryTint),
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: isCurrentMonth ? null : onToday,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 9 : 11,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isCompact) ...[
                        Icon(
                          Icons.today_rounded,
                          size: 14,
                          color: isCurrentMonth
                              ? cs.onSurfaceVariant.withValues(alpha: 0.6)
                              : (isDark
                                  ? cs.onPrimaryContainer
                                  : AppTheme.primaryColor),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        'Heute',
                        style: TextStyle(
                          fontSize: isCompact ? 11.5 : 12,
                          fontWeight: FontWeight.w700,
                          color: isCurrentMonth
                              ? cs.onSurfaceVariant.withValues(alpha: 0.6)
                              : (isDark
                                  ? cs.onPrimaryContainer
                                  : AppTheme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.darkCardElevated
                    : const Color(0xFFE6E6E2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildModeButton(
                    mode: _CalendarDisplayMode.month,
                    icon: Icons.calendar_view_month_rounded,
                    text: 'Monat',
                  ),
                  buildModeButton(
                    mode: _CalendarDisplayMode.agenda,
                    icon: Icons.view_agenda_outlined,
                    text: 'Agenda',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _shortMonthName(int m) {
    const names = [
      "Jan",
      "Feb",
      "Mär",
      "Apr",
      "Mai",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Okt",
      "Nov",
      "Dez",
    ];
    return names[m - 1];
  }

  static String _monthName(int m) {
    const names = [
      "Januar",
      "Februar",
      "März",
      "April",
      "Mai",
      "Juni",
      "Juli",
      "August",
      "September",
      "Oktober",
      "November",
      "Dezember",
    ];
    return names[m - 1];
  }
}

class _LegendRow extends StatelessWidget {
  final bool showStage1;
  final bool showApplied;
  final bool showAvailability;
  final bool showBlackout;
  final bool showTandem;

  const _LegendRow({
    required this.showStage1,
    this.showApplied = false,
    this.showAvailability = false,
    this.showBlackout = false,
    this.showTandem = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        const _LegendDot(color: AppTheme.infoColor, label: 'Geplant'),
        const _LegendDot(color: AppTheme.successColor, label: 'Zugesagt'),
        const _LegendDot(color: AppTheme.swapColor, label: 'Abgeschlossen'),
        const _LegendDot(color: AppTheme.dangerColor, label: 'Abgesagt'),
        if (showApplied) ...[
          const _LegendSwatch(
            color: Color(0xFFFFFFFF),
            borderColor: AppTheme.infoColor,
            label: 'Offene Stelle',
          ),
          const _LegendDot(color: Color(0xFF9CA3AF), label: 'Beworben'),
        ],
        if (showStage1)
          _LegendSwatch(
            color: AppTheme.stage1Color.withValues(alpha: 0.22),
            borderColor: AppTheme.stage1Color,
            label: 'Stufe 1',
          ),
        if (showAvailability)
          const _LegendLine(color: AppTheme.successColor, label: 'Verfügbar'),
        if (showBlackout)
          const _LegendLine(color: AppTheme.dangerColor, label: 'Abwesend'),
        if (showTandem)
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.paragliding_rounded,
                size: 13,
                color: AppTheme.primaryColor,
              ),
              SizedBox(width: 3),
              Text('Tandem', style: TextStyle(fontSize: 11)),
            ],
          ),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 13, color: AppTheme.swapColor),
            SizedBox(width: 3),
            Text('Tausch offen', style: TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _TandemCellPill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final bool showDot;
  final Color? dotColor;

  const _TandemCellPill({
    required this.label,
    required this.bg,
    required this.fg,
    this.showDot = false,
    this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.paragliding_rounded, size: 11, color: fg),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 2.5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  height: 1.1,
                ),
              ),
            ],
            if (showDot) ...[
              const SizedBox(width: 3),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: dotColor ?? AppTheme.infoColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final String label;

  const _LegendSwatch({
    required this.color,
    required this.borderColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: borderColor, width: 1),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LegendLine extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendLine({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EventBar extends StatelessWidget {
  final Event event;
  final dynamic flightSchool;
  final VoidCallback? onTap;
  final bool continuesLeft;
  final bool continuesRight;
  final bool showFsName;
  final bool redactStage1;

  const _EventBar({
    required this.event,
    required this.flightSchool,
    required this.onTap,
    required this.continuesLeft,
    required this.continuesRight,
    required this.showFsName,
    this.redactStage1 = false,
  });

  int _effectiveStage() {
    if (flightSchool != null) {
      try {
        final s = (flightSchool as dynamic).effectiveStageFor(event);
        if (s is int) return s;
      } catch (_) {}
    }
    return event.planningStage;
  }

  static String _fsLogo(dynamic fs) {
    if (fs == null) return '';
    try {
      final v = (fs as dynamic).logoLink;
      return (v ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  static String _fsName(dynamic fs) {
    if (fs == null) return '';
    try {
      final shortName = (fs as dynamic).displayShortName?.toString() ?? '';
      if (shortName.trim().isNotEmpty) return shortName;
    } catch (_) {}
    try {
      return (fs as dynamic).displayName?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  bool _isExtendedTeam() {
    if (flightSchool != null) {
      try {
        final v = (flightSchool as dynamic).isExtendedTeam;
        if (v is bool) return v;
      } catch (_) {}
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stage = _effectiveStage();
    final isApplied =
        redactStage1 &&
        !event.isSwapOfferFromOther &&
        event.assignmentStatus == EventUserStatusEnum.pending_flight_school &&
        !event.isOwnBindingAssignment;
    final isDirectRequest =
        redactStage1 &&
        !event.isSwapOfferFromOther &&
        event.assignmentStatus == EventUserStatusEnum.pending_user &&
        !event.isOwnBindingAssignment;
    final isExtendedRedacted =
        redactStage1 &&
        _isExtendedTeam() &&
        !event.isOwnBindingAssignment &&
        !isApplied &&
        !isDirectRequest;
    final isOpenOpp =
        redactStage1 &&
        !isExtendedRedacted &&
        !event.isOwnBindingAssignment &&
        stage >= 2 &&
        (event.isSwapOfferFromOther ||
            event.assignmentStatus == EventUserStatusEnum.open);
    final isStage1 =
        redactStage1 &&
        !isExtendedRedacted &&
        stage == 1 &&
        !event.isOwnBindingAssignment &&
        !isApplied &&
        !isDirectRequest;
    final style = _EventBarStyle.from(
      event,
      isStage1Redacted: isStage1,
      isExtendedTeamRedacted: isExtendedRedacted,
      isApplied: isApplied,
      isDirectRequest: isDirectRequest,
      isOpenOpportunity: isOpenOpp,
    );

    final logo = _fsLogo(flightSchool);
    final fsName = _fsName(flightSchool);

    final radius = BorderRadius.only(
      topLeft: Radius.circular(continuesLeft ? 4 : 10),
      bottomLeft: Radius.circular(continuesLeft ? 4 : 10),
      topRight: Radius.circular(continuesRight ? 4 : 10),
      bottomRight: Radius.circular(continuesRight ? 4 : 10),
    );

    final titleText = event.displayName;
    final infoText = showFsName ? "$fsName · $titleText" : titleText;
    final hasSwap =
        !isStage1 &&
        !isExtendedRedacted &&
        !isApplied &&
        (event.isSwapOfferFromOther ||
            event.hasOpenSwapRequest ||
            event.team.any((t) => t.hasOpenSwapRequest));

    final hasBorder = isApplied || isDirectRequest || isOpenOpp;
    final isCanceled = event.status == EventStatusEnum.canceled;

    return Opacity(
      opacity: isApplied ? 0.78 : 1.0,
      child: CanceledEventDecorator(
        isCanceled: isCanceled,
        borderRadius: radius,
        stripeSpacing: 22,
        stripeWidth: 1.3,
        child: Material(
          color: style.bg,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side:
                hasBorder
                    ? BorderSide(
                      color: style.accent.withValues(
                        alpha: isOpenOpp ? 0.85 : 0.7,
                      ),
                      width: isOpenOpp ? 1.2 : 1,
                    )
                    : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: ClipOval(
                      child:
                          logo.isEmpty
                              ? Container(
                                color: cs.surface,
                                child: Icon(
                                  Icons.flight,
                                  size: 11,
                                  color: style.accent,
                                ),
                              )
                              : Image.network(
                                logo,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (_, __, ___) => Container(
                                      color: cs.surface,
                                      child: Icon(
                                        Icons.flight,
                                        size: 11,
                                        color: style.accent,
                                      ),
                                    ),
                              ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      infoText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            isApplied ? FontWeight.w600 : FontWeight.w800,
                        fontSize: 11.5,
                        color: style.fg,
                        decoration:
                            isCanceled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                if (isDirectRequest) ...[
                  const SizedBox(width: 3),
                  Tooltip(
                    message: 'Direktanfrage – Bestätigung offen',
                    child: Icon(
                      Icons.notifications_active_outlined,
                      size: 12,
                      color: style.fg,
                    ),
                  ),
                ],
                if (isOpenOpp && !event.isSwapOfferFromOther) ...[
                  const SizedBox(width: 3),
                  Tooltip(
                    message: 'Offene Stelle – tippen zum Bewerben',
                    child: Icon(
                      Icons.person_add_alt_1_outlined,
                      size: 12,
                      color: style.fg,
                    ),
                  ),
                ],
                if (isApplied) ...[
                  const SizedBox(width: 3),
                  Tooltip(
                    message: 'Beworben – wartet auf Bestätigung',
                    child: Icon(
                      Icons.hourglass_top_rounded,
                      size: 12,
                      color: style.fg,
                    ),
                  ),
                ],
                if (hasSwap) ...[
                  const SizedBox(width: 3),
                  Tooltip(
                    message: 'Offene Tauschanfrage',
                    child: Icon(Icons.swap_horiz, size: 14, color: style.fg),
                  ),
                ],
                if (continuesRight) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 14, color: style.fg),
                ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Semantische Event-Farben nach Status (bzw. Stufe 1 / Offen / Beworben) statt Zufallshash.
class _EventBarStyle {
  final Color bg;
  final Color fg;
  final Color accent;

  const _EventBarStyle(this.bg, this.fg, this.accent);

  static _EventBarStyle from(
    Event event, {
    bool isStage1Redacted = false,
    bool isExtendedTeamRedacted = false,
    bool isApplied = false,
    bool isDirectRequest = false,
    bool isOpenOpportunity = false,
  }) {
    if (isDirectRequest) {
      return const _EventBarStyle(
        AppTheme.warningBg,
        AppTheme.warningColor,
        AppTheme.warningColor,
      );
    }
    if (isApplied) {
      return const _EventBarStyle(
        Color(0xFFECEEF3),
        Color(0xFF4B5563),
        Color(0xFF9AA3B2),
      );
    }
    if (isExtendedTeamRedacted) {
      return const _EventBarStyle(
        Color(0xFFECEEF3),
        Color(0xFF6B7280),
        Color(0xFF9CA3AF),
      );
    }
    if (isOpenOpportunity) {
      if (event.isSwapOfferFromOther) {
        return const _EventBarStyle(
          AppTheme.swapBg,
          AppTheme.swapColor,
          AppTheme.swapColor,
        );
      }
      return const _EventBarStyle(
        AppTheme.infoBg,
        AppTheme.infoColor,
        AppTheme.infoColor,
      );
    }
    if (isStage1Redacted) {
      return const _EventBarStyle(
        AppTheme.stage1Bg,
        AppTheme.stage1Color,
        AppTheme.stage1Color,
      );
    }

    switch (event.status) {
      case EventStatusEnum.provisional:
        return const _EventBarStyle(
          AppTheme.successBg,
          AppTheme.successColor,
          AppTheme.successColor,
        );
      case EventStatusEnum.done:
        return const _EventBarStyle(
          AppTheme.swapBg,
          AppTheme.swapColor,
          AppTheme.swapColor,
        );
      case EventStatusEnum.canceled:
        return const _EventBarStyle(
          AppTheme.dangerBg,
          AppTheme.dangerColor,
          AppTheme.dangerColor,
        );
      case EventStatusEnum.scheduled:
        return const _EventBarStyle(
          AppTheme.infoBg,
          AppTheme.infoColor,
          AppTheme.infoColor,
        );
    }
  }
}

class _WeekEvent {
  final Event event;
  final int startIdx;
  final int endIdx;
  final bool continuesLeft;
  final bool continuesRight;

  _WeekEvent(
    this.event,
    this.startIdx,
    this.endIdx,
    this.continuesLeft,
    this.continuesRight,
  );
}

class _WeekAvailability {
  final AvailabilitySubmission submission;
  final int startIdx;
  final int endIdx;
  final bool continuesLeft;
  final bool continuesRight;

  _WeekAvailability(
    this.submission,
    this.startIdx,
    this.endIdx,
    this.continuesLeft,
    this.continuesRight,
  );
}
