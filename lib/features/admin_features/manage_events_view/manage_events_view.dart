import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/data/enums/event_status_enum.dart';
import 'package:season_planer/services/flight_school_service.dart';
import 'package:season_planer/services/providers/flight_school_provider.dart';
import 'package:season_planer/data/models/event_model.dart';

import '../../../services/database_service.dart';
import '../widgets/event_upsert_view.dart';

class ManageEventsView extends StatefulWidget {
  const ManageEventsView({super.key});

  @override
  State<ManageEventsView> createState() => _ManageEventsViewState();
}

class _ManageEventsViewState extends State<ManageEventsView> {
  final _flightSchoolService = FlightSchoolService();
  final TextEditingController _searchCtrl = TextEditingController();

  String _search = "";
  dynamic _statusFilter;
  final bool _sortAsc = true;

  DateTimeRange? _dateRange;

  bool _showPastEvents = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = _dateRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day).add(const Duration(days: 7)),
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: initial,
    );

    if (!mounted) return;
    if (picked != null) setState(() => _dateRange = picked);
  }

  void _clearDateRange() => setState(() => _dateRange = null);

  bool _matchesSearch(Event e) {
    if (_search.trim().isEmpty) return true;
    final q = _search.toLowerCase();
    return e.displayName.toLowerCase().contains(q) ||
        e.identifier.toLowerCase().contains(q);
  }

  bool _matchesStatus(Event e) {
    if (_statusFilter == null) return true;
    return e.status == _statusFilter;
  }

  bool _matchesDateRange(Event e) {
    if (_dateRange == null) return true;

    final start = DateTime(_dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day, 0, 0, 0);
    final end = DateTime(_dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day, 23, 59, 59);

    return (e.startTime.isAtSameMomentAs(start) || e.startTime.isAfter(start)) &&
        (e.startTime.isAtSameMomentAs(end) || e.startTime.isBefore(end));
  }

  bool _matchesTimeWindow(Event e) {
    if (_showPastEvents) return true;

    final now = DateTime.now();


    return e.endTime.isAfter(now) || e.endTime.isAtSameMomentAs(now);
  }

  List<Event> _applyFilters(List<Event> input) {
    final filtered = input
        .where((e) =>
    _matchesTimeWindow(e) &&
        _matchesSearch(e) &&
        _matchesStatus(e) &&
        _matchesDateRange(e))
        .toList();

    filtered.sort((a, b) {
      final cmp = a.startTime.compareTo(b.startTime);
      return _sortAsc ? cmp : -cmp;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<FlightSchoolProvider>(context);
    final flightSchool = provider.flightSchool;

    if (flightSchool == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final allEvents = flightSchool.events;
    final events = _applyFilters(allEvents);

    final statusValues = allEvents.map((e) => e.status).toSet().toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Your Events"),
        automaticallyImplyLeading: false,
        actions: [

        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: "Search (Name / Identifier)",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = "");
                        },
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 8),

                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Show past Events"),
                    value: _showPastEvents,
                    onChanged: (v) => setState(() => _showPastEvents = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<dynamic>(
                          initialValue: _statusFilter,
                          decoration: const InputDecoration(
                            labelText: "Status",
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<EventStatusEnum?>(
                              value: null,
                              child: Text("Alle"),
                            ),
                            ...EventStatusEnum.values.map(
                                  (status) => DropdownMenuItem<EventStatusEnum?>(
                                value: status,
                                child: Text(
                                  status.label,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _statusFilter = v),
                        ),
                      ),
                      const SizedBox(width: 8),

                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.date_range),
                          label: Text(
                            _dateRange == null
                                ? "Zeitraum"
                                : "${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}",
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: _pickDateRange,
                        ),
                      ),
                      const SizedBox(width: 8),

                      IconButton(
                        tooltip: "Zeitraum zurücksetzen",
                        onPressed: _dateRange == null ? null : _clearDateRange,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: events.isEmpty
                  ? const Center(child: Text("No Events found."))
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: events.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final e = events[index];

                  return Card(
                    elevation: 2,
                    child: ListTile(
                      title: Text(e.displayName),
                      subtitle: Text(
                        "${e.identifier} • ${_formatDateTime(e.startTime)} – ${_formatDateTime(e.endTime)}",
                      ),
                      trailing: Text(
                        e.status.toString().split('.').last,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EventUpsertView(
                                initialEvent: e,
                                onSave: (updated) async {
                                  final db = DatabaseService();
                                  await db.updateEventWithTeam(
                                    context: context,
                                    event: updated,
                                  );
                                  context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
                                    _flightSchoolService.getFlightSchool,
                                  );

                                },
                              ),
                            ),
                          );
                        debugPrint("Event tapped: ${e.id}");
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: "New Event",
        onPressed: () {
          final flightSchool = context.read<FlightSchoolProvider>().flightSchool!;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EventUpsertView(
                initialEvent: null,
                onSave: (event) async {
                  final db = DatabaseService();
                  await db.createEventWithTeam(
                    context: context,
                    event: event,
                  );
                  context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
                    _flightSchoolService.getFlightSchool,
                  );
                },
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),


    );
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(dt.day)}.${two(dt.month)}.${dt.year}";
  }

  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}";
  }
}
