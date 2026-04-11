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
  String label({EventUserStatusLabelContext context = EventUserStatusLabelContext.defaultView}) {
    switch (context) {
      case EventUserStatusLabelContext.userView:
        return _userViewLabel();
      case EventUserStatusLabelContext.shortLabel:
        return _shortLabel();
      case EventUserStatusLabelContext.tooltip:
        return _tooltipLabel();
      case EventUserStatusLabelContext.defaultView:
      default:
        return _defaultLabel();
    }
  }

  String _defaultLabel() {
    switch (this) {
      case EventUserStatusEnum.open:
        return 'Open Opportunity';
      case EventUserStatusEnum.accepted_flight_school:
        return 'Accepted by Flight School';
      case EventUserStatusEnum.accepted_user:
        return 'Accepted by User';
      case EventUserStatusEnum.pending_flight_school:
        return 'Waiting for Flight School';
      case EventUserStatusEnum.pending_user:
        return 'Waiting for User Response';
      case EventUserStatusEnum.denied_user:
        return 'Declined by User';
      case EventUserStatusEnum.denied_flight_school:
        return 'Declined by Flight School';
      case EventUserStatusEnum.user_requests_change:
        return 'User requests to Change';
    }
  }

  String _userViewLabel() {
    switch (this) {
      case EventUserStatusEnum.user_requests_change:
        return 'You requested a Change';
      default:
        return _defaultLabel();
    }
  }

  String _shortLabel() {
    switch (this) {
      case EventUserStatusEnum.open:
        return 'Open';
      case EventUserStatusEnum.accepted_user:
        return 'Accepted';
      case EventUserStatusEnum.user_requests_change:
        return 'Change';
      default:
        return _defaultLabel();
    }
  }

  String _tooltipLabel() {
    switch (this) {
      case EventUserStatusEnum.pending_flight_school:
        return 'Waiting for confirmation from the flight school.';
      case EventUserStatusEnum.denied_user:
        return 'You have declined this request.';
      default:
        return _defaultLabel();
    }
  }
}



