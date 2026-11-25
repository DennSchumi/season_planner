enum SubscriptionStatusEnum {
  pending,
  active,
  disabled,
}

extension SubscriptionStatusEnumX on SubscriptionStatusEnum {
  String get label {
    switch (this) {
      case SubscriptionStatusEnum.pending:
        return 'Abo wird aktiviert';
      case SubscriptionStatusEnum.active:
        return 'Aktiv';
      case SubscriptionStatusEnum.disabled:
        return 'Deaktiviert';
    }
  }

  bool get isActive => this == SubscriptionStatusEnum.active;

  static SubscriptionStatusEnum parse(dynamic raw) {
    final s = (raw ?? 'active').toString();
    return SubscriptionStatusEnum.values.firstWhere(
      (e) => e.name == s,
      orElse: () => SubscriptionStatusEnum.active,
    );
  }
}
