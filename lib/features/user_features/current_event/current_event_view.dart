import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/data/enums/event_user_status_enum.dart';
import 'package:season_planner/data/models/event_model.dart';
import 'package:season_planner/services/providers/user_provider.dart';

class CurrentEventView extends StatefulWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const CurrentEventView({
    super.key,
    required this.isLoading,
    required this.hasConnection,
    required this.lastUpdated,
  });

  @override
  State<CurrentEventView> createState() => _CurrentEventViewState();
}

class _CurrentEventViewState extends State<CurrentEventView> {
  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final now = DateTime.now();

    final events = user.events
        .where(
          (e) =>
      (e.assignmentStatus == EventUserStatusEnum.accepted_user ||
          e.assignmentStatus ==
              EventUserStatusEnum.accepted_flight_school) &&
          e.endTime.isAfter(now),
    )
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return events.isEmpty
        ? Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Current Event',
          style: TextStyle(fontSize: 22),
        ),
        actions: [_buildStatusIcon()],
      ),
      body: const Center(
        child: Text(
          'No current or upcoming events.',
          style: TextStyle(fontSize: 16),
        ),
      ),
    )
        : PageView.builder(
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isOngoing =
            event.startTime.isBefore(now) && event.endTime.isAfter(now);
        final daysUntil = event.startTime.difference(now).inDays;
        final fs = user.flightSchools
            .firstWhere((fs) => fs.id == event.flightSchoolId);
        final fsName =
            fs.displayShortName ?? fs.displayName ?? 'Flight School';
        final fsLogo = fs.logoLink ?? '';

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(
              isOngoing
                  ? 'Ongoing Event'
                  : 'Upcoming Event in $daysUntil day${daysUntil == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 20),
            ),
            actions: [_buildStatusIcon()],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                _HeaderCard(
                  fsName: fsName,
                  fsLogoLink: fsLogo,
                  event: event,
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'General',
                  children: [
                    _InfoRow(
                      icon: Icons.badge_outlined,
                      label: 'Identifier',
                      value: event.identifier,
                    ),
                    _InfoRow(
                      icon: Icons.schedule,
                      label: 'Start',
                      value: _formatDate(event.startTime),
                    ),
                    _InfoRow(
                      icon: Icons.schedule_outlined,
                      label: 'End',
                      value: _formatDate(event.endTime),
                    ),
                    _InfoRow(
                      icon: Icons.flag_outlined,
                      label: 'Event status',
                      value: event.status.label,
                    ),
                    _InfoRow(
                      icon: Icons.account_circle_outlined,
                      label: 'Your role',
                      value: event.role.label,
                    ),
                    if (event.location.isNotEmpty)
                      _InfoRow(
                        icon: Icons.place_outlined,
                        label: 'Location',
                        value: event.location,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Team',
                  children: event.team.isEmpty
                      ? const [
                    Text(
                      'No team members assigned.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ]
                      : event.team
                      .map(
                        (t) => Padding(
                      padding:
                      const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            t.role,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .toList(),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Notes',
                  children: [
                    event.notes.isEmpty
                        ? const Text(
                      'No notes.',
                      style: TextStyle(color: Colors.black54),
                    )
                        : Text(event.notes),
                  ],
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIcon() {
    return IconButton(
      icon: widget.isLoading
          ? const Icon(Icons.sync, color: Colors.blue)
          : widget.hasConnection
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.error, color: Colors.red),
      onPressed: () {
        if (widget.lastUpdated == null) return;

        final time =
            '${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:${widget.lastUpdated!.minute.toString().padLeft(2, '0')}';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.hasConnection
                  ? 'Last update: $time'
                  : 'Offline · Last update: $time',
            ),
          ),
        );
      },
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}




class _HeaderCard extends StatelessWidget {
  final String fsName;
  final String fsLogoLink;
  final Event event;

  const _HeaderCard({
    required this.fsName,
    required this.fsLogoLink,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: cs.surface,
              child: fsLogoLink.isEmpty
                  ? Icon(Icons.flight, color: cs.onSurfaceVariant)
                  : ClipOval(
                child: Image.network(
                  fsLogoLink,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.flight,
                          color: cs.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fsName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _Pill(
                        icon: Icons.assignment_ind_outlined,
                        text:event.assignmentStatus.label(context: EventUserStatusLabelContext.userView)
                        ),
                      _Pill(
                        icon: Icons.badge_outlined,
                        text: event.role.label,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
