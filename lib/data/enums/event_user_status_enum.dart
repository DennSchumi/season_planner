enum EventUserStatusEnum {
    open,
    aceppted_flight_school,
    accepted_user,
    pending_flight_school,
    pending_user,
    denied_user,
    denied_flight_school,
}

extension EventUserStatusLabel on EventUserStatusEnum {
    String get label {
        switch (this) {
            case EventUserStatusEnum.open:
                return 'Open Opportunity';
            case EventUserStatusEnum.aceppted_flight_school:
                return 'Accepted by Flight School';
            case EventUserStatusEnum.accepted_user:
                return 'Accepted by You';
            case EventUserStatusEnum.pending_flight_school:
                return 'Waiting for Flight School';
            case EventUserStatusEnum.pending_user:
                return 'Waiting for Your Response';
            case EventUserStatusEnum.denied_user:
                return 'Declined by You';
            case EventUserStatusEnum.denied_flight_school:
                return 'Declined by Flight School';
        }
    }
}
