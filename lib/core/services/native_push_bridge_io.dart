import 'dart:async';
import 'dart:io' show Platform;
import 'package:appwrite/appwrite.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kAndroidChannelId = 'season_planner_default';
const String _kAndroidChannelName = 'Season Planner Benachrichtigungen';
const String _kAndroidChannelDesc =
    'Einsatz-Anfragen, Tauschwünsche, offene Stellen und wichtige Updates';

const String _kPrefTargetId = 'sp_native_push_target_id_v1';
const String _kPrefLastToken = 'sp_native_push_token_v1';
const String _kPrefLastUserId = 'sp_native_push_user_v1';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

bool _nativeInitialized = false;
bool _localReady = false;
bool _fcmReady = false;
String _cachedPermission = 'default';
String? _activeUserId;
StreamSubscription<RemoteMessage>? _fgSub;
StreamSubscription<String>? _tokenRefreshSub;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
}

bool get isNativePushSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

String get nativeNotificationPermission => _cachedPermission;

bool get isNativeFcmActive => _fcmReady;

Future<void> initNativePush({
  void Function(String title, String body)? onForegroundFcmMessage,
}) async {
  if (!isNativePushSupported || _nativeInitialized) return;
  _nativeInitialized = true;

  // 1) Lokale System-Benachrichtigungen (funktionieren sofort, auch ohne Firebase)
  try {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );
    await _localNotifications.initialize(settings: settings);

    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kAndroidChannelId,
          _kAndroidChannelName,
          description: _kAndroidChannelDesc,
          importance: Importance.high,
        ),
      );
      final enabled = await androidPlugin?.areNotificationsEnabled();
      if (enabled == true) {
        _cachedPermission = 'granted';
      } else if (enabled == false) {
        _cachedPermission = 'default';
      }
    }
    _localReady = true;
  } catch (e) {
    debugPrint('NativePush local init error: $e');
  }

  // 2) Firebase Cloud Messaging (aktiviert sich automatisch, sobald google-services.json / GoogleService-Info.plist vorhanden ist)
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    _applyAuthStatus(settings.authorizationStatus);

    if (Platform.isIOS) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    await _fgSub?.cancel();
    _fgSub = FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      final title =
          msg.notification?.title ?? msg.data['title']?.toString() ?? '';
      final body = msg.notification?.body ?? msg.data['body']?.toString() ?? '';
      if (title.isEmpty && body.isEmpty) return;

      unawaited(
        showNativeNotification(
          title: title.isNotEmpty ? title : 'Season Planner',
          body: body,
          tag: msg.messageId,
        ),
      );
      onForegroundFcmMessage?.call(
        title.isNotEmpty ? title : 'Season Planner',
        body,
      );
    });

    await _tokenRefreshSub?.cancel();
    // Appwrite Messaging FCM erwartet den klassischen FCM-Registration-Token.
    // ignore: deprecated_member_use
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) {
      final uid = _activeUserId;
      if (uid != null && uid.isNotEmpty && token.isNotEmpty) {
        unawaited(_registerTokenInAppwrite(userId: uid, token: token));
      }
    });

    _fcmReady = true;
  } catch (e) {
    // Erwartbar, solange google-services.json noch nicht hinterlegt wurde.
    _fcmReady = false;
    debugPrint(
      'NativePush FCM nicht konfiguriert (nur lokale Pushs aktiv): $e',
    );
  }
}

void _applyAuthStatus(AuthorizationStatus status) {
  switch (status) {
    case AuthorizationStatus.authorized:
    case AuthorizationStatus.provisional:
      _cachedPermission = 'granted';
      break;
    case AuthorizationStatus.denied:
    case AuthorizationStatus.deniedPermanently:
      _cachedPermission = 'denied';
      break;
    case AuthorizationStatus.notDetermined:
      _cachedPermission = 'default';
      break;
  }
}

Future<String> requestNativeNotificationPermission() async {
  if (!isNativePushSupported) return 'unsupported';
  if (!_nativeInitialized) {
    await initNativePush();
  }

  try {
    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidPlugin?.requestNotificationsPermission();
      if (granted == true) {
        _cachedPermission = 'granted';
      } else if (granted == false) {
        _cachedPermission = 'denied';
      }
    }

    if (_fcmReady) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _applyAuthStatus(settings.authorizationStatus);
    } else if (Platform.isIOS) {
      final iosPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      _cachedPermission = (granted == true) ? 'granted' : 'denied';
    }
  } catch (e) {
    debugPrint('NativePush requestPermission error: $e');
  }

  if (_cachedPermission == 'granted' &&
      _activeUserId != null &&
      _activeUserId!.isNotEmpty) {
    unawaited(syncNativePushTarget(userId: _activeUserId!));
  }

  return _cachedPermission;
}

Future<bool> showNativeNotification({
  required String title,
  required String body,
  String? tag,
}) async {
  if (!isNativePushSupported) return false;
  if (!_nativeInitialized) {
    await initNativePush();
  }
  if (!_localReady) return false;

  try {
    final id =
        (tag?.hashCode ?? DateTime.now().millisecondsSinceEpoch).abs() %
        2147483647;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _kAndroidChannelId,
        _kAndroidChannelName,
        channelDescription: _kAndroidChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
    return true;
  } catch (e) {
    debugPrint('NativePush showNativeNotification error: $e');
    return false;
  }
}

/// Registriert bzw. aktualisiert das aktuelle Gerät als Appwrite Push Target,
/// sodass serverseitige Pushs (`push_notifier`) auch bei geschlossener App ankommen.
Future<void> syncNativePushTarget({required String userId}) async {
  if (!isNativePushSupported || userId.isEmpty) return;
  _activeUserId = userId;
  if (!_nativeInitialized) {
    await initNativePush();
  }
  if (!_fcmReady) return;

  try {
    if (Platform.isIOS) {
      // Auf iOS stellt APNs das Device-Token manchmal erst kurz nach App-Start bereit;
      // kurz warten, damit FirebaseMessaging.getToken() keinen apns-token-not-set Fehler wirft.
      String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      for (int attempt = 0; attempt < 5 && apnsToken == null; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      }
      if (apnsToken == null) {
        debugPrint('NativePush iOS APNs token noch nicht verfügbar – späterer Retry.');
        return;
      }
    }

    // Appwrite Messaging FCM erwartet den klassischen FCM-Registration-Token (für Android & iOS via FCM→APNs).
    // ignore: deprecated_member_use
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.trim().isEmpty) return;
    await _registerTokenInAppwrite(userId: userId, token: token.trim());
  } catch (e) {
    debugPrint('NativePush syncNativePushTarget error: $e');
  }
}

Future<void> _registerTokenInAppwrite({
  required String userId,
  required String token,
}) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final savedTargetId = sp.getString(_kPrefTargetId);
    final savedToken = sp.getString(_kPrefLastToken);
    final savedUser = sp.getString(_kPrefLastUserId);

    if (savedUser == userId &&
        savedToken == token &&
        savedTargetId != null &&
        savedTargetId.isNotEmpty) {
      return; // Bereits aktuell registriert
    }

    final cfg = AppwriteConfig();
    // Sowohl Android als auch iOS senden über Firebase Cloud Messaging (FCM → APNs),
    // daher nutzen beide Plattformen denselben Appwrite-FCM-Provider.
    final providerId = cfg.fcmProviderId.isNotEmpty ? cfg.fcmProviderId : null;

    final account = AuthService().account;
    String targetId = savedTargetId ?? '';

    if (savedUser == userId && targetId.isNotEmpty) {
      try {
        await account.updatePushTarget(targetId: targetId, identifier: token);
      } catch (_) {
        targetId = ID.unique();
        await account.createPushTarget(
          targetId: targetId,
          identifier: token,
          providerId: providerId,
        );
      }
    } else {
      targetId = ID.unique();
      await account.createPushTarget(
        targetId: targetId,
        identifier: token,
        providerId: providerId,
      );
    }

    await sp.setString(_kPrefTargetId, targetId);
    await sp.setString(_kPrefLastToken, token);
    await sp.setString(_kPrefLastUserId, userId);
  } catch (e) {
    debugPrint('NativePush Appwrite push target registration failed: $e');
  }
}

Future<void> unregisterNativePushTarget() async {
  _activeUserId = null;
  if (!isNativePushSupported) return;
  try {
    final sp = await SharedPreferences.getInstance();
    final targetId = sp.getString(_kPrefTargetId);
    if (targetId != null && targetId.isNotEmpty) {
      try {
        await AuthService().account.deletePushTarget(targetId: targetId);
      } catch (_) {}
    }
    await sp.remove(_kPrefTargetId);
    await sp.remove(_kPrefLastToken);
    await sp.remove(_kPrefLastUserId);
  } catch (_) {}
}
