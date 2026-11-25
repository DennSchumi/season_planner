enum EventUserStatusEnum {
  open,
  accepted_flight_school,
  accepted_user,
  pending_flight_school,
  pending_user,
  denied_user,
  denied_flight_school,
  user_requests_change,
}

enum EventUserStatusLabelContext {
  defaultView,
  userView,
  shortLabel,
  tooltip,
}

extension EventUserStatusLabelX on EventUserStatusEnum {
  static EventUserStatusEnum parse(dynamic raw) {
    final s = (raw ?? 'open').toString();
    return EventUserStatusEnum.values.firstWhere(
      (e) => e.name == s,
      orElse: () => EventUserStatusEnum.open,
    );
  }

  String label({EventUserStatusLabelContext context = EventUserStatusLabelContext.defaultView}) {
    switch (context) {
      case EventUserStatusLabelContext.userView:
        return _userViewLabel();
      case EventUserStatusLabelContext.shortLabel:
        return _shortLabel();
      case EventUserStatusLabelContext.tooltip:
        return _tooltipLabel();
      case EventUserStatusLabelContext.defaultView:
        return _defaultLabel();
    }
  }

  String _defaultLabel() {
    switch (this) {
      case EventUserStatusEnum.open:
        return 'Offene Stelle';
      case EventUserStatusEnum.accepted_flight_school:
        return 'Von Flugschule bestätigt';
      case EventUserStatusEnum.accepted_user:
        return 'Vom Mitglied bestätigt';
      case EventUserStatusEnum.pending_flight_school:
        return 'Warte auf Flugschule';
      case EventUserStatusEnum.pending_user:
        return 'Warte auf Rückmeldung';
      case EventUserStatusEnum.denied_user:
        return 'Vom Mitglied abgelehnt';
      case EventUserStatusEnum.denied_flight_school:
        return 'Von Flugschule abgelehnt';
      case EventUserStatusEnum.user_requests_change:
        return 'Änderung angefragt';
    }
  }

  String _userViewLabel() {
    switch (this) {
      case EventUserStatusEnum.user_requests_change:
        return 'Du hast eine Änderung angefragt';
      case EventUserStatusEnum.accepted_user:
      case EventUserStatusEnum.accepted_flight_school:
        return 'Bestätigt';
      default:
        return _defaultLabel();
    }
  }

  String _shortLabel() {
    switch (this) {
      case EventUserStatusEnum.open:
        return 'Offen';
      case EventUserStatusEnum.accepted_user:
      case EventUserStatusEnum.accepted_flight_school:
        return 'Bestätigt';
      case EventUserStatusEnum.user_requests_change:
        return 'Änderung';
      case EventUserStatusEnum.pending_flight_school:
      case EventUserStatusEnum.pending_user:
        return 'Ausstehend';
      case EventUserStatusEnum.denied_user:
      case EventUserStatusEnum.denied_flight_school:
        return 'Abgelehnt';
    }
  }

  String _tooltipLabel() {
    switch (this) {
      case EventUserStatusEnum.pending_flight_school:
        return 'Warte auf Bestätigung durch die Flugschule.';
      case EventUserStatusEnum.denied_user:
        return 'Du hast diese Anfrage abgelehnt.';
      default:
        return _defaultLabel();
    }
  }
}
