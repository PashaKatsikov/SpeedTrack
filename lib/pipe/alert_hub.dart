import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_store.dart';
import 'ua_masker.dart';

/// Notification channel id — must EXACTLY match the value of
/// `com.google.firebase.messaging.default_notification_channel_id`
/// meta-data in AndroidManifest.xml.
const String kAlertChannelId = 'speedtrack_alerts';
const String kAlertChannelName = 'Speed Track Alerts';
const String _alertSmallIcon = '@drawable/ic_notification';

@pragma('vm:entry-point')
Future<void> _backgroundReceiver(RemoteMessage message) async {
  // The OS renders background notifications; the tap is processed on
  // resume (warm) or boot (cold) — nothing to do in this isolate.
}

/// Firebase Messaging + local notification display for the gray flow.
///
/// Cold-start taps (app was killed) save the link so the shell opens
/// it on the next boot. Warm taps (background/foreground) deliver the
/// link live via [onLink] without persisting it — push links are
/// one-time and must not survive a session.
class AlertHub {
  AlertHub(this._store);

  final LocalStore _store;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _fm;
  String? _token;
  bool _ready = false;

  /// Live (warm) push link delivery — loaded straight into the WebView.
  void Function(String link)? onLink;

  /// Fires when FCM rotates the token OR the OS permission is granted
  /// AFTER the initial gate call already happened without a token. The
  /// hook is owned by `main.dart` (survives Navigator replacements), so
  /// the gate body is re-posted with the fresh `push_token`, otherwise
  /// the partner backend has no install↔token binding and cannot deliver
  /// pushes (returns "Установка приложения не найдена").
  void Function(String token)? onTokenRotated;

  String? get token => _token;

  Future<void> boot() async {
    if (_ready) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _fm = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_backgroundReceiver);

      await _installLocal();

      _token = await _fm!.getToken();
      _fm!.onTokenRefresh.listen((String t) {
        _token = t;
        onTokenRotated?.call(t);
      });

      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_onWarmTap);

      final RemoteMessage? initial = await _fm!.getInitialMessage();
      if (initial != null) _onColdTap(initial);

      _ready = true;
    } catch (_) {
      // Firebase not configured yet — push stays dormant, app continues.
    }
  }

  Future<void> _installLocal() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings(_alertSmallIcon);
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        final String? payload = r.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final Map<String, dynamic> data =
              jsonDecode(payload) as Map<String, dynamic>;
          final String? link = data['url'] as String?;
          if (link != null && link.isNotEmpty) onLink?.call(link);
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android =
          _local.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          kAlertChannelId,
          kAlertChannelName,
          description: 'Updates and offers',
          importance: Importance.high,
        ),
      );
    }
  }

  /// Requests notification permission. Records the OS-denied flag so
  /// the invite screen never loops.
  Future<bool> askPermission() async {
    if (_fm == null) return false;
    final NotificationSettings s = await _fm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final AuthorizationStatus status = s.authorizationStatus;
    final bool granted = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;

    await _store.markPushGranted(granted);
    if (status == AuthorizationStatus.denied) {
      await _store.markPushDeniedByOs();
    }

    // On Android 13+ FCM only surfaces a usable push registration AFTER
    // POST_NOTIFICATIONS is granted. Re-read the token and re-post the
    // gate body so the partner backend actually learns the token for
    // this install (fixes "Установка приложения не найдена").
    if (granted) {
      try {
        final String? fresh = await _fm!.getToken();
        if (fresh != null && fresh.isNotEmpty && fresh != _token) {
          _token = fresh;
        }
        if (_token != null && _token!.isNotEmpty) {
          onTokenRotated?.call(_token!);
        }
      } catch (_) {}
    }
    return granted;
  }

  Future<void> _onForeground(RemoteMessage message) async {
    final RemoteNotification? n = message.notification;
    if (n == null || !Platform.isAndroid) return;

    AndroidNotificationDetails? details;
    final String? imageUrl = n.android?.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final Uint8List? bytes = await _fetchImage(imageUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          kAlertChannelId,
          kAlertChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: _alertSmallIcon,
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bytes),
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      }
    }

    details ??= const AndroidNotificationDetails(
      kAlertChannelId,
      kAlertChannelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: _alertSmallIcon,
    );

    await _local.show(
      id: n.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(android: details),
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
  }

  void _onColdTap(RemoteMessage message) {
    final String? link = message.data['url'] as String?;
    if (link != null && link.isNotEmpty) {
      _store.stashPendingLink(link);
    }
  }

  void _onWarmTap(RemoteMessage message) {
    final String? link = message.data['url'] as String?;
    if (link != null && link.isNotEmpty) {
      onLink?.call(link);
    }
  }

  Future<Uint8List?> _fetchImage(String url) async {
    try {
      final dynamic res = await siteAgent
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return res.bodyBytes as Uint8List;
    } catch (_) {}
    return null;
  }
}
