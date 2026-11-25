import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/models/audit_log_model.dart';
import 'package:season_planner/core/services/audit_log_service.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/user/user_provider.dart';

class AuditLogView extends StatefulWidget {
  const AuditLogView({super.key});

  @override
  State<AuditLogView> createState() => _AuditLogViewState();
}

class _AuditLogViewState extends State<AuditLogView> {
  static const int _pageSize = 50;
  List<AuditLogEntry> _entries = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    setState(() {
      _loading = true;
      _hasMore = true;
    });
    final list = await AuditLogService().listLogs(
      flightSchoolId: fs.id,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _entries = list;
      _hasMore = list.length >= _pageSize;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _entries.isEmpty) return;
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    setState(() => _loadingMore = true);
    final next = await AuditLogService().listLogs(
      flightSchoolId: fs.id,
      limit: _pageSize,
      cursorAfter: _entries.last.id,
    );
    if (!mounted) return;
    setState(() {
      _entries = [..._entries, ...next];
      _hasMore = next.length >= _pageSize;
      _loadingMore = false;
    });
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    final currentUser = context.watch<UserProvider>().user;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Audit-Log / Protokoll')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                ? const EmptyStateView(
                    icon: Icons.history,
                    title: 'Noch keine Protokolleinträge',
                    subtitle:
                        'Änderungen an Events, Mitgliedern, Qualifikationen und Planungsstufen werden hier protokolliert.',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _entries.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        if (index >= _entries.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: OutlinedButton.icon(
                                onPressed: _loadingMore ? null : _loadMore,
                                icon: _loadingMore
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.expand_more),
                                label: Text(
                                  _loadingMore
                                      ? 'Lade ältere Einträge…'
                                      : 'Ältere Einträge laden',
                                ),
                              ),
                            ),
                          );
                        }

                        final e = _entries[index];
                        final fallback = currentUser != null &&
                                e.userId == currentUser.id
                            ? (currentUser.name.isNotEmpty
                                ? currentUser.name
                                : currentUser.mail)
                            : null;
                        final actor = fs.resolveMemberName(
                          e.userId,
                          fallbackName: fallback,
                          emptyLabel: 'System',
                        );
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(
                              e.action,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${e.details.isNotEmpty ? "${e.details}\n" : ""}$actor · ${_fmt(e.timestamp)}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
