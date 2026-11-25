enum MembershipStatusEnum {
  active,
  invited,
  requested,
  inactive,
}

extension MembershipStatusEnumX on MembershipStatusEnum {
  String get label {
    switch (this) {
      case MembershipStatusEnum.active:
        return 'Aktiv';
      case MembershipStatusEnum.invited:
        return 'Eingeladen';
      case MembershipStatusEnum.requested:
        return 'Angefragt';
      case MembershipStatusEnum.inactive:
        return 'Inaktiv';
    }
  }

  static MembershipStatusEnum parse(dynamic raw) {
    final s = (raw ?? 'active').toString();
    return MembershipStatusEnum.values.firstWhere(
      (e) => e.name == s,
      orElse: () => MembershipStatusEnum.active,
    );
  }
}
