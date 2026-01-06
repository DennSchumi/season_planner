import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/data/enums/event_user_status_enum.dart';
import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/services/database_service.dart';
import 'package:season_planer/services/providers/user_provider.dart';

import '../../../../data/models/user_models/user_model_userView.dart';

class EventDetailView extends StatefulWidget {
  final Event event;

  const EventDetailView({super.key, required this.event});

  @override
  State<EventDetailView> createState() => _EventDetailViewState();
}

class _EventDetailViewState extends State<EventDetailView> {
  late UserModelUserView user;

  @override
  void initState() {
    super.initState();
    // Sauber: direkt read() nutzen (kein Future.microtask nötig)
    user = context.read<UserProvider>().user!;
  }

  Future<bool> _request() async {
    final success = await DatabaseService().changeEventAssignmentStatus(
      user: user,
      event: widget.event,
      newStatus: EventUserStatusEnum.pending_flight_school,
    );
    if (success) {
      final updatedEvents = await DatabaseService().loadUserEvents(user);
      if (!mounted) return false;
      context.read<UserProvider>().updateEvents(updatedEvents);
    }
    return success;
  }

  Future<bool> _accept() async {
    final success = await DatabaseService().changeEventAssignmentStatus(
      user: user,
      event: widget.event,
      newStatus: EventUserStatusEnum.accepted_user,
    );
    if (success) {
      final updatedEvents = await DatabaseService().loadUserEvents(user);
      if (!mounted) return false;
      context.read<UserProvider>().updateEvents(updatedEvents);
    }
    return success;
  }

  Future<bool> _change() async {
    final success = await DatabaseService().changeEventAssignmentStatus(
      user: user,
      event: widget.event,
      newStatus: EventUserStatusEnum.open,
    );
    if (success) {
      final updatedEvents = await DatabaseService().loadUserEvents(user);
      if (!mounted) return false;
      context.read<UserProvider>().updateEvents(updatedEvents);
    }
    return success;
  }

  void _showActionDialog({
    required String title,
    required String message,
    required Future<bool> Function() action,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ActionDialog(
        title: title,
        message: message,
        action: action,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userFromProvider = context.watch<UserProvider>().user;

    if (userFromProvider == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Event aus Provider holen (falls sich Status/Team geändert hat)
    final event = userFromProvider.events.firstWhere(
          (e) => e.id == widget.event.id,
      orElse: () => widget.event,
    );

    // FlightSchool Infos wieder aus User holen (Liste aller FS)
    final flightSchools = userFromProvider.flightSchools;
    final fs = flightSchools.cast<dynamic>().firstWhere(
          (x) => x.id == event.flightSchoolId,
      orElse: () => null,
    );

    final String fsName = fs == null
        ? "Unknown flight school"
        : ((fs.displayShortName ?? fs.displayName ?? "").toString().isEmpty
        ? "Flight school"
        : (fs.displayShortName ?? fs.displayName).toString());

    final String fsLogoLink =
    fs == null ? "" : (fs.logoLink ?? fs.logo_link ?? "").toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          event.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      bottomNavigationBar: _BottomActionBar(
        status: event.assignmentStatus,
        onRequest: () => _showActionDialog(
          title: "Request assignment",
          message: "Do you want to request this assignment?",
          action: _request,
        ),
        onAccept: () => _showActionDialog(
          title: "Accept assignment",
          message: "Do you want to accept this assignment?",
          action: _accept,
        ),
        onChange: () => _showActionDialog(
          title: "Request change",
          message: "Do you want to request a change to this assignment?",
          action: _change,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            _HeaderCard(
              fsName: fsName,
              fsLogoLink: fsLogoLink,
              event: event,
            ),
            const SizedBox(height: 12),

            _SectionCard(
              title: "General",
              children: [
                _InfoRow(
                  icon: Icons.badge_outlined,
                  label: "Identifier",
                  value: event.identifier,
                ),
                _InfoRow(
                  icon: Icons.schedule,
                  label: "Start",
                  value: _formatDate(event.startTime),
                ),
                _InfoRow(
                  icon: Icons.schedule_outlined,
                  label: "End",
                  value: _formatDate(event.endTime),
                ),
                _InfoRow(
                  icon: Icons.flag_outlined,
                  label: "Event status",
                  value: event.status.label,
                ),
                _InfoRow(
                  icon: Icons.account_circle_outlined,
                  label: "Your role",
                  value: event.role.label,
                ),
                if ((event.location ?? "").toString().isNotEmpty)
                  _InfoRow(
                    icon: Icons.place_outlined,
                    label: "Location",
                    value: (event.location ?? "").toString(),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            _SectionCard(
              title: "Team",
              children: event.team
                  .where((t) => t.name != null && t.name!.isNotEmpty)
                  .isEmpty
                  ? [
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    "No team members assigned.",
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              ]
                  : event.team
                  .where((t) => t.name != null && t.name!.isNotEmpty)
                  .map(
                    (t) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.name!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
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
              title: "Notes",
              children: [
                if (event.notes.isEmpty)
                  const Text(
                    "No notes.",
                    style: TextStyle(color: Colors.black54),
                  )
                else
                  Text(event.notes),
              ],
            ),

            const SizedBox(height: 80), // Platz für Bottom Bar
          ],
        ),
      ),
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
                    fsName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _Pill(
                        icon: Icons.assignment_ind_outlined,
                        text: event.assignmentStatus.name,
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
      color: cs.surface,
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
              value.isEmpty ? "—" : value,
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
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: BorderSide(color: cs.outlineVariant).toBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  final EventUserStatusEnum status;
  final VoidCallback onRequest;
  final VoidCallback onAccept;
  final VoidCallback onChange;

  const _BottomActionBar({
    required this.status,
    required this.onRequest,
    required this.onAccept,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget content;

    if (status == EventUserStatusEnum.open) {
      content = FilledButton.icon(
        onPressed: onRequest,
        icon: const Icon(Icons.send_outlined),
        label: const Text("Request assignment"),
      );
    } else if (status == EventUserStatusEnum.pending_user) {
      content = FilledButton.icon(
        onPressed: onAccept,
        icon: const Icon(Icons.check_circle_outline),
        label: const Text("Accept"),
      );
    } else if (status == EventUserStatusEnum.pending_flight_school) {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: BorderSide(color: cs.outlineVariant).toBorder(),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Waiting for flight school to accept",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (status == EventUserStatusEnum.accepted_user ||
        status == EventUserStatusEnum.aceppted_flight_school) {
      content = OutlinedButton.icon(
        onPressed: onChange,
        icon: const Icon(Icons.swap_horiz),
        label: const Text("Request change"),
      );
    } else {
      content = const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: content,
      ),
    );
  }
}

class _ActionDialog extends StatefulWidget {
  final String title;
  final String message;
  final Future<bool> Function() action;

  const _ActionDialog({
    required this.title,
    required this.message,
    required this.action,
  });

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  bool _isLoading = false;
  bool? _success;

  Future<void> _execute() async {
    setState(() => _isLoading = true);

    try {
      final result = await widget.action();

      setState(() {
        _isLoading = false;
        _success = result;
      });

      if (result) {
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {
      setState(() {
        _isLoading = false;
        _success = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        height: 110,
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator()
              : _success == true
              ? const Icon(Icons.check_circle, color: Colors.green, size: 52)
              : _success == false
              ? Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.cancel, color: Colors.red, size: 52),
              SizedBox(height: 8),
              Text("Sorry, something went wrong."),
              Text("Please try again later :)"),
            ],
          )
              : Text(widget.message),
        ),
      ),
      actions: _isLoading || _success == true
          ? []
          : _success == false
          ? [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("OK"),
        )
      ]
          : [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Abort"),
        ),
        FilledButton(
          onPressed: _execute,
          child: const Text("Approve"),
        ),
      ],
    );
  }
}

extension on BorderSide {
  Border toBorder() => Border.fromBorderSide(this);
}
