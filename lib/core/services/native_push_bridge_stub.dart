bool get isNativePushSupported => false;

String get nativeNotificationPermission => 'unsupported';

bool get isNativeFcmActive => false;

Future<void> initNativePush({
  void Function(String title, String body)? onForegroundFcmMessage,
}) async {}

Future<String> requestNativeNotificationPermission() async => 'unsupported';

Future<bool> showNativeNotification({
  required String title,
  required String body,
  String? tag,
}) async =>
    false;

Future<void> syncNativePushTarget({required String userId}) async {}

Future<void> unregisterNativePushTarget() async {}
