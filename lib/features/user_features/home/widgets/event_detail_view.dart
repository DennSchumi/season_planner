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
    Future.microtask(() {
      user = Provider.of<UserProvider>(context, listen: false).user!;
    });
  }



  Future<bool> _request() async {
    bool success = await DatabaseService().changeEventAssignmentStatus(
      user: user,
      event: widget.event,
      newStatus: EventUserStatusEnum.pending_flight_school,
    );
    if (success) {
      final updatedEvents = await DatabaseService().loadUserEvents(user);
      if (!mounted) return false;
      Provider.of<UserProvider>(context, listen: false).updateEvents(updatedEvents);
    }
    return success;
  }

  Future<bool> _accept() async {
    bool success = await DatabaseService().changeEventAssignmentStatus(
      user: user,
      event: widget.event,
      newStatus: EventUserStatusEnum.accepted_user,
    );
    if (success) {
      final updatedEvents = await DatabaseService().loadUserEvents(user);
      if (!mounted) return false;
      Provider.of<UserProvider>(context, listen: false).updateEvents(updatedEvents);
    }
    return success;
  }

  Future<bool> _change() async {
    bool success = await DatabaseService().changeEventAssignmentStatus(
      user: user,
      event: widget.event,
      newStatus: EventUserStatusEnum.open,
    );
    if (success) {
      final updatedEvents = await DatabaseService().loadUserEvents(user);
      if (!mounted) return false;
      Provider.of<UserProvider>(context, listen: false).updateEvents(updatedEvents);//TODO: überlegen ob man da einen extra schritt macht bevor es für alle sichtbar ist
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
    final user = Provider.of<UserProvider>(context).user;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final event = user.events.firstWhere(
          (e) => e.id == widget.event.id,
      orElse: () => widget.event, // fallback
    );

    return Scaffold(
      appBar: AppBar(title: Text(event.displayName)),
      body: SafeArea(
        minimum: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle("Allgemeine Informationen"),
                    _infoRow(Icons.badge, "Interne Kennung", event.identifier),
                    _infoRow(Icons.calendar_today, "Start", _formatDate(event.startTime)),
                    _infoRow(Icons.calendar_today_outlined, "Ende", _formatDate(event.endTime)),
                    _infoRow(Icons.flag, "Status", event.status.label),
                    _infoRow(Icons.account_circle_outlined, "Deine Rolle", event.role.label),
                    const SizedBox(height: 20),
                    _sectionTitle("Team"),
                    if (event.team.isEmpty)
                      const Text("Keine Teammitglieder eingetragen."),
                    ...event.team.map((t) => Text("• $t")),
                    const SizedBox(height: 20),
                    _sectionTitle("Notizen"),
                    if (event.notes.isEmpty)
                      const Text("Keine Notizen vorhanden."),
                      Text(event.notes),
                  ],
                ),
              ),
            ),
            Divider(),
            if (event.assignmentStatus == EventUserStatusEnum.open)
              OutlinedButton(
                onPressed: () => _showActionDialog(
                  title: "Request Assignment",
                  message: "Are you sure you want to request this assignment?",
                  action: _request,
                ),
                child: const Text("Request Assignment"),
              )
            else if (event.assignmentStatus == EventUserStatusEnum.pending_user)
              OutlinedButton(
                onPressed: () => _showActionDialog(
                  title: "Accept Assignment",
                  message: "Are you sure you want to accept this assignment?",
                  action: _accept,
                ),
                child: const Text("Accept"),
              )
            else if (event.assignmentStatus == EventUserStatusEnum.pending_flight_school)
                const Text("Waiting for Flight School to Accept")
              else if (event.assignmentStatus == EventUserStatusEnum.accepted_user ||
                    event.assignmentStatus == EventUserStatusEnum.aceppted_flight_school)
                  OutlinedButton(
                    onPressed: () => _showActionDialog(
                      title: "Request Change",
                      message: "Are you sure you want to request a change to this assignment?",
                      action: _change,
                    ),
                    child: const Text("Request Change"),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blueGrey),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(": $value")),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.of(context).pop();
      }

    } catch (e) {
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
        height: 100,
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator()
              : _success == true
              ? const Icon(Icons.check_circle, color: Colors.green, size: 48)
              : _success == false
              ? Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.cancel, color: Colors.red, size: 48),
              SizedBox(height: 8),
              Text("Sorry, something went wrong."),
              Text("Please try again later :)")
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
        TextButton(
          onPressed: _execute,
          child: const Text("Approve"),
        ),
      ],
    );
  }
}
