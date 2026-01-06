import 'package:flutter/material.dart';

import '../../../../data/models/event_model.dart';
import '../../../../data/models/user_models/flight_school_model_user_view.dart';

class EventCardTile extends StatelessWidget {
  final Event event;
  final FlightSchoolUserView? flightSchool;
  final String dateText;
  final Color statusColor;
  final VoidCallback onTap;

  const EventCardTile({
    super.key,
    required this.event,
    required this.flightSchool,
    required this.dateText,
    required this.statusColor,
    required this.onTap,
  });

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
            crossAxisAlignment: CrossAxisAlignment.center,
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
                    Text(
                      event.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),

                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _InfoChip(
                          icon: Icons.paragliding,
                        text: fsName,
                        ),

                        _InfoChip(
                          icon: Icons.calendar_today_outlined,
                          text: dateText,
                        ),
                        if ((event.location ?? '').toString().isNotEmpty)
                          _InfoChip(
                            icon: Icons.place_outlined,
                            text: event.location!,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              Container(
                margin: const EdgeInsets.only(left: 8, top: 4),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
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
