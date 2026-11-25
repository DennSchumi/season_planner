bool get isWebNotificationSupported => false;

String get webNotificationPermission => 'unsupported';

Future<String> requestWebNotificationPermission() async => 'unsupported';

bool showWebNotification({
  required String title,
  required String body,
  String? tag,
}) =>
    false;
