import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

bool get isWebNotificationSupported {
  try {
    return web.window.hasProperty('Notification'.toJS).toDart;
  } catch (_) {
    return false;
  }
}

String get webNotificationPermission {
  if (!isWebNotificationSupported) return 'unsupported';
  try {
    return web.Notification.permission;
  } catch (_) {
    return 'unsupported';
  }
}

Future<String> requestWebNotificationPermission() async {
  if (!isWebNotificationSupported) return 'unsupported';
  try {
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart;
  } catch (_) {
    return 'denied';
  }
}

bool showWebNotification({
  required String title,
  required String body,
  String? tag,
}) {
  if (!isWebNotificationSupported) return false;
  if (webNotificationPermission != 'granted') return false;
  try {
    final options = tag != null && tag.isNotEmpty
        ? web.NotificationOptions(
            body: body,
            icon: 'icons/Icon-192.png',
            tag: tag,
          )
        : web.NotificationOptions(
            body: body,
            icon: 'icons/Icon-192.png',
          );
    web.Notification(title, options);
    return true;
  } catch (_) {
    return false;
  }
}
