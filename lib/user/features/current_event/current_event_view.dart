import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/widgets/event_role_docs_section.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/user_provider.dart';

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
          (e) => e.isOwnBindingAssignment && e.endTime.isAfter(now),
        )
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    if (events.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Aktuelles Event'),
          actions: _buildAppBarActions(),
        ),
        body: const EmptyStateView(
          icon: Icons.access_time_outlined,
          title: 'Kein aktives oder kommendes Event',
          subtitle:
              'Sobald du für ein Event fest eingeteilt oder bestätigt wurdest, erscheint es hier mit Countdown, Checkliste und Arbeitsanweisungen.',
        ),
      );
    }

    return PageView.builder(
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isOngoing =
            event.startTime.isBefore(now) && event.endTime.isAfter(now);
        final daysUntil = event.startTime.difference(now).inDays;
        final fs = user.flightSchools.firstWhere(
          (fs) => fs.id == event.flightSchoolId,
        );
        final effectiveStage = fs.effectiveStageFor(event);
        final fsName = fs.displayShortName.isNotEmpty
            ? fs.displayShortName
            : fs.displayName;
        final fsLogo = fs.logoLink;

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(
              isOngoing
                  ? 'Laufendes Event'
                  : daysUntil == 0
                      ? 'Event startet heute'
                      : 'Nächstes Event in $daysUntil ${daysUntil == 1 ? "Tag" : "Tagen"}',
            ),
            actions: _buildAppBarActions(),
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
                  title: 'Allgemein',
                  children: [
                    if (event.identifier.isNotEmpty)
                      _InfoRow(
                        icon: Icons.badge_outlined,
                        label: 'Kennung',
                        value: event.identifier,
                      ),
                    _InfoRow(
                      icon: Icons.schedule,
                      label: 'Beginn',
                      value: _formatDate(event.startTime),
                    ),
                    _InfoRow(
                      icon: Icons.schedule_outlined,
                      label: 'Ende',
                      value: _formatDate(event.endTime),
                    ),
                    _InfoRow(
                      icon: Icons.flag_outlined,
                      label: 'Status',
                      value: event.status.label,
                    ),
                    _InfoRow(
                      icon: Icons.account_circle_outlined,
                      label: 'Deine Rolle',
                      value: event.roleLabel,
                    ),
                    if (event.location.isNotEmpty)
                      _InfoRow(
                        icon: Icons.place_outlined,
                        label: 'Ort',
                        value: event.location,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                EventRoleDocsSection(
                  event: event,
                  flightSchool: fs,
                  userId: user.id,
                ),
                // Team-Besetzung der anderen Positionen nur in Planungsstufe 2 & 3 sichtbar
                if (effectiveStage >= 2) ...[
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Team',
                    children: event.team.isEmpty
                        ? [
                            Text(
                              'Keine Teammitglieder eingeteilt.',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ]
                        : event.team
                            .map(
                              (t) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    UserAvatar(
                                      avatarUrl: t.avatarUrl,
                                      name: t.isSlot ? '' : t.name,
                                      radius: 15,
                                      isOpenSlot: t.isSlot,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        t.isSlot
                                            ? 'Offene Stelle'
                                            : (t.name.isEmpty
                                                ? 'Teammitglied'
                                                : t.name),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      t.roleLabel,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Notizen',
                  children: [
                    event.notes.isEmpty
                        ? const Text(
                            'Keine Notizen vorhanden.',
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

  List<Widget> _buildAppBarActions() {
    return [
      const AppModeSwitchChip(isAdminMode: false),
      const AppBarActionDivider(),
      ConnectionStatusAction(
        isLoading: widget.isLoading,
        hasConnection: widget.hasConnection,
        lastUpdated: widget.lastUpdated,
      ),
    ];
  }

  static String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                            Icon(Icons.flight, color: cs.onSurfaceVariant),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    fsName,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _Pill(
                        icon: Icons.assignment_ind_outlined,
                        text: event.assignmentStatus.label(
                          context: EventUserStatusLabelContext.userView,
                        ),
                      ),
                      _Pill(
                        icon: Icons.badge_outlined,
                        text: event.roleLabel,
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

  const _SectionCard({required this.title, required this.children});

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
            width: 105,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
