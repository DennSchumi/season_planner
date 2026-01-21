import 'package:flutter/material.dart';
import 'package:season_planer/data/enums/event_status_enum.dart';
import 'package:season_planer/data/enums/event_user_status_enum.dart';

import '../../../../data/models/event_model.dart';
import '../../../../data/models/user_models/flight_school_model_user_view.dart';

class EventCardTile extends StatelessWidget {
  final Event event;
  final FlightSchoolUserView? flightSchool;
  final String dateText;
  final EventStatusEnum status;
  final VoidCallback onTap;

  const EventCardTile({
    super.key,
    required this.event,
    required this.flightSchool,
    required this.dateText,
    required this.status,
    required this.onTap,
  });

  String _getStatusText(EventStatusEnum status) {
    switch (status) {
      case EventStatusEnum.scheduled:
        return EventStatusEnum.scheduled.label;
      case EventStatusEnum.provisional:
        return EventStatusEnum.provisional.label;
      case EventStatusEnum.canceled:
        return EventStatusEnum.canceled.label;
      default:
        return "none";
    }
  }

  Widget? _buildAssignmentIndicator(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    switch (event.assignmentStatus) {
      case EventUserStatusEnum.user_requests_change:
        return Tooltip(
          message: 'Change requested',
          child: Icon(Icons.change_circle, color: Colors.orange, size: 20),
        );
      case EventUserStatusEnum.accepted_user:
        return Tooltip(
          message: 'Confirmed',
          child: Icon(Icons.check_circle, color: Colors.green, size: 20),
        );
      case EventUserStatusEnum.accepted_flight_school:
        return Tooltip(
          message: 'Confirmed',
          child: Icon(Icons.check_circle, color: Colors.green, size: 20),
        );
      case EventUserStatusEnum.denied_user:
        return Tooltip(
          message: 'Denied',
          child: Icon(Icons.cancel, color: Colors.red, size: 20),
        );
      case EventUserStatusEnum.pending_user:
      case EventUserStatusEnum.pending_flight_school:
        return Tooltip(
          message: 'Pending confirmation',
          child: Icon(Icons.hourglass_top, color: Colors.blueGrey, size: 20),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fs = flightSchool;
    final logo = (fs?.logoLink ?? '').toString();
    final fsName = fs?.displayShortName ?? fs?.displayName ?? 'Flight School';

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: cs.surfaceContainerHighest,
                child: logo.isEmpty
                    ? Icon(Icons.flight, color: cs.onSurfaceVariant)
                    : ClipOval(
                  child: Image.network(
                    logo,
                    width: 40,
                    height: 40,
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (_buildAssignmentIndicator(context) != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: _buildAssignmentIndicator(context),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _InfoChip(
                          icon: Icons.calendar_today_outlined,
                          text: dateText,
                        ),
                        if ((event.location ?? '').toString().isNotEmpty)
                          _InfoChip(
                            icon: Icons.place_outlined,
                            text: event.location!,
                          ),
                        _InfoChip(
                          icon: Icons.question_answer_outlined,
                          text: _getStatusText(status),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}