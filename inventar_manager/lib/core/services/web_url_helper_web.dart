import 'package:web/web.dart' as web;

void clearBrowserUrlToRootImpl() {
  try {
    web.window.history.replaceState(null, '', '/');
  } catch (_) {}
}
