import 'package:flutter/foundation.dart';
import 'web_url_helper_stub.dart'
    if (dart.library.js_interop) 'web_url_helper_web.dart';

class PasswordRecoveryParams {
  final String userId;
  final String secret;

  const PasswordRecoveryParams({
    required this.userId,
    required this.secret,
  });
}

/// Liest `userId` und `secret` aus der aktuellen Web-URL (sowohl aus normalen
/// Query-Parametern `/reset-password?userId=...&secret=...` als auch aus einem
/// Hash-Fragment `/#/reset-password?userId=...&secret=...`).
PasswordRecoveryParams? extractPasswordRecoveryParams([Uri? uri]) {
  if (!kIsWeb && uri == null) return null;
  final effective = uri ?? Uri.base;

  // 1) Reguläre Query-Parameter prüfen
  var userId = (effective.queryParameters['userId'] ?? '').trim();
  var secret = (effective.queryParameters['secret'] ?? '').trim();
  if (userId.isNotEmpty && secret.isNotEmpty) {
    return PasswordRecoveryParams(userId: userId, secret: secret);
  }

  // 2) Fallback: Hash-Fragment (z. B. /#/reset-password?userId=...&secret=...)
  final frag = effective.fragment;
  if (frag.contains('?')) {
    final fragUri = Uri.tryParse(frag.startsWith('/') ? frag : '/$frag');
    if (fragUri != null) {
      userId = (fragUri.queryParameters['userId'] ?? '').trim();
      secret = (fragUri.queryParameters['secret'] ?? '').trim();
      if (userId.isNotEmpty && secret.isNotEmpty) {
        return PasswordRecoveryParams(userId: userId, secret: secret);
      }
    }
  }

  return null;
}

/// Bereinigt im Web die Adressleiste nach Abschluss des Passwort-Resets auf `/`,
/// damit ein Reload nicht erneut den bereits eingelösten Reset-Link öffnet.
void clearBrowserUrlToRoot() {
  clearBrowserUrlToRootImpl();
}
