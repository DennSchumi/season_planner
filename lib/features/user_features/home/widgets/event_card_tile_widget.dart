import 'package:flutter/cupertino.dart';
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
    final fs = flightSchool;
    final logo = (fs?.logoLink ?? '').toString();

    return Card(
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: logo.isEmpty
              ? const Icon(Icons.flight, size: 18)
              : ClipOval(
            child: Image.network(
              logo,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
              const Icon(Icons.flight, size: 18),
            ),
          ),
        ),
        title: Text(
          event.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(dateText),
        trailing: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: statusColor,
            shape: BoxShape.circle,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}