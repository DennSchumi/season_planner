import 'package:flutter/material.dart';
import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/data/models/user_models/flight_school_model_user_view.dart';

class EventsCalendar extends StatefulWidget {
  final List<Event> events;
  final Map<String, FlightSchoolUserView> fsById;
  final void Function(Event event)? onEventTap;

  const EventsCalendar({
    super.key,
    required this.events,
    required this.fsById,
    this.onEventTap,
  });

  @override
  State<EventsCalendar> createState() => _EventsCalendarState();
}

class _EventsCalendarState extends State<EventsCalendar> {
  late DateTime _visibleMonth;
  DateTime? _selectedDay;

  static const _weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

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

  DateTime _endOfWeek(DateTime d) => _startOfWeek(d).add(const Duration(days: 6));

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

  List<List<_WeekEvent>> _laneEventsForWeek(DateTime weekStart, DateTime weekEnd) {
    final intersecting = widget.events
        .where((e) => _eventIntersectsRange(e, weekStart, weekEnd))
        .map((e) {
      final s = _dateOnly(e.startTime);
      final t = _dateOnly(e.endTime);

      final continuesLeft = s.isBefore(weekStart);
      final continuesRight = t.isAfter(weekEnd);

      final startIdx = _clamp(s.difference(weekStart).inDays, 0, 6);
      final endIdx = _clamp(t.difference(weekStart).inDays, 0, 6);

      return _WeekEvent(e, startIdx, endIdx, continuesLeft, continuesRight);
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

  void _prevMonth() => setState(() {
    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
  });

  void _nextMonth() => setState(() {
    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
  });

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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _Header(month: _visibleMonth, onPrev: _prevMonth, onNext: _nextMonth),
            const SizedBox(height: 10),
            Row(
              children: _weekdays
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
            const Divider(height: 1),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final cellW = constraints.maxWidth / 7;
                const dayCellH = 55.0;
                const laneH = 22.0;
                const laneGap = 4.0;
                const maxLanesShown = 3;

                const dayHPad = 2.0; // horizontal padding between day cells
                const dayBorderW = 1.0;
                const dayInnerMarginH = 2.0; // your inner container margin
                const eventOuterPad = dayHPad + dayBorderW + dayInnerMarginH;
                const eventInnerPad = 2.0; // small inset inside the week row
                final cellContentW = cellW - (2 * eventOuterPad);

                return Column(
                  children: weeks.map((weekDays) {
                    final weekStart = _dateOnly(weekDays.first);
                    final weekEnd = _dateOnly(weekDays.last);
                    final lanes = _laneEventsForWeek(weekStart, weekEnd);

                    final shownLanes = lanes.length > maxLanesShown ? maxLanesShown : lanes.length;
                    final rowH = dayCellH +
                        (shownLanes == 0 ? 0 : (shownLanes * laneH + (shownLanes - 1) * laneGap)) +
                        8;

                    return SizedBox(
                      height: rowH,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Row(
                              children: weekDays.map((d) {
                                final isToday = _isSameDay(d, DateTime.now());
                                final inMonth = _isInMonth(d, _visibleMonth);

                                final fg = inMonth ? cs.onSurface : cs.onSurfaceVariant.withOpacity(0.6);
                                final fw = isToday ? FontWeight.w900 : FontWeight.w400;

                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: dayHPad),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: cs.outlineVariant.withOpacity(0.6),
                                          width: dayBorderW,
                                        ),
                                        color: _selectedDay != null && _isSameDay(d, _selectedDay!)
                                            ? cs.primaryContainer.withOpacity(0.35)
                                            : Colors.transparent,
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => setState(() => _selectedDay = d),
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(horizontal: dayInnerMarginH, vertical: 2),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.transparent,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              "${d.day}",
                                              style: TextStyle(fontWeight: fw, color: fg),
                                            ),
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
                              top: dayCellH - 10,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: eventInnerPad),
                                child: Column(
                                  children: [
                                    for (var laneIndex = 0; laneIndex < shownLanes; laneIndex++) ...[
                                      SizedBox(
                                        height: laneH,
                                        child: Stack(
                                          children: [
                                            for (final we in lanes[laneIndex])
                                              Positioned(
                                                left: we.startIdx * cellW + eventOuterPad + eventInnerPad,
                                                width: (we.endIdx - we.startIdx + 1) * cellW -
                                                    (2 * (eventOuterPad + eventInnerPad)),
                                                top: 0,
                                                bottom: 0,
                                                child: _EventBar(
                                                  event: we.event,
                                                  fs: widget.fsById[we.event.flightSchoolId],
                                                  onTap: widget.onEventTap == null ? null : () => widget.onEventTap!(we.event),
                                                  continuesLeft: we.continuesLeft,
                                                  continuesRight: we.continuesRight,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (laneIndex != shownLanes - 1) const SizedBox(height: laneGap),
                                    ],
                                    if (lanes.length > maxLanesShown)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            "+${lanes.length - maxLanesShown} more",
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _Header({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = "${_monthName(month.month)} ${month.year}";

    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          tooltip: "Previous month",
        ),
        Expanded(
          child: Center(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: "Next month",
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            "Month",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  static String _monthName(int m) {
    const names = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    return names[m - 1];
  }
}

class _EventBar extends StatelessWidget {
  final Event event;
  final FlightSchoolUserView? fs;
  final VoidCallback? onTap;
  final bool continuesLeft;
  final bool continuesRight;

  const _EventBar({
    super.key,
    required this.event,
    required this.fs,
    required this.onTap,
    required this.continuesLeft,
    required this.continuesRight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = _EventBarStyle.from(context, event);
    final logo = (fs?.logoLink ?? '').toString();
    final fsName = fs?.displayShortName ?? fs?.displayName ?? "";

    final radius = BorderRadius.only(
      topLeft: Radius.circular(continuesLeft ? 4 : 10),
      bottomLeft: Radius.circular(continuesLeft ? 4 : 10),
      topRight: Radius.circular(continuesRight ? 4 : 10),
      bottomRight: Radius.circular(continuesRight ? 4 : 10),
    );

    return Material(
      color: style.bg,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: ClipOval(
                  child: logo.isEmpty
                      ? Container(
                    color: cs.surface,
                    child: Icon(Icons.flight, size: 12, color: cs.onSurfaceVariant),
                  )
                      : Image.network(
                    logo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: cs.surface,
                      child: Icon(Icons.flight, size: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fsName.isEmpty ? event.displayName : "$fsName · ${event.displayName}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: style.fg,
                  ),
                ),
              ),
              if (continuesRight) ...[
                const SizedBox(width: 2),
                Icon(Icons.chevron_right, size: 16, color: style.fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
class _EventBarStyle {
  final Color bg;
  final Color fg;

  const _EventBarStyle(this.bg, this.fg);

  static _EventBarStyle from(BuildContext context, Event event) {
    final palette = <_EventBarStyle>[
    // Muted Blue
    _EventBarStyle(
    Color(0xFFCBD5E1), // slate-300
    Color(0xFF1E293B), // slate-800
    ),

    // Muted Green
    _EventBarStyle(
    Color(0xFFCCEDE2),
    Color(0xFF064E3B),
    ),

    // Muted Purple
    _EventBarStyle(
    Color(0xFFD8D5F0),
    Color(0xFF3C2E7E),
    ),

    // Muted Orange
    _EventBarStyle(
    Color(0xFFF1D4B8),
    Color(0xFF7C2D12),
    ),

    // Muted Teal
    _EventBarStyle(
    Color(0xFFCFE4E8),
    Color(0xFF134E4A),
    ),

    // Muted Rose
    _EventBarStyle(
    Color(0xFFE6C9D4),
    Color(0xFF701A3A),
    ),

    // Muted Yellow / Sand
    _EventBarStyle(
    Color(0xFFE8DFC2),
    Color(0xFF6B4E16),
    ),

    // Muted Indigo / Steel
    _EventBarStyle(
    Color(0xFFD6DBF2),
    Color(0xFF2C2F6B),
    ),
    ];

    final h = _stableHash(event.id.isNotEmpty ? event.id : event.displayName);
    final idx = h % palette.length;
    return palette[idx];
  }

  static int _stableHash(String s) {
    var h = 0;
    for (final unit in s.codeUnits) {
      h = 0x1fffffff & (h + unit);
      h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
      h ^= (h >> 6);
    }
    h = 0x1fffffff & (h + ((0x03ffffff & h) << 3));
    h ^= (h >> 11);
    h = 0x1fffffff & (h + ((0x00003fff & h) << 15));
    return h;
  }
}


class _WeekEvent {
  final Event event;
  final int startIdx;
  final int endIdx;
  final bool continuesLeft;
  final bool continuesRight;

  _WeekEvent(this.event, this.startIdx, this.endIdx, this.continuesLeft, this.continuesRight);
}
