import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Registers this phone for push notifications.
///
/// The phone's FCM token is saved in users/{uid}.fcmTokens. A Cloud Function
/// (functions/index.js) reads those tokens and sends the actual push messages
/// whenever something happens in a room.
class PushService {
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  final _local = FlutterLocalNotificationsPlugin();
  bool _localReady = false;

  static const _channel = AndroidNotificationChannel(
    'roommate_alerts',
    'RoomMate alerts',
    description: 'Expenses, chat, join requests and announcements',
    importance: Importance.high,
  );

  /// Android does not show a push while the app is open, so we draw the same
  /// kind of normal notification ourselves.
  Future<void> _setupForeground() async {
    if (!_localReady) {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      _localReady = true;
    }
    await _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      _local.show(
        id: n.hashCode,
        title: n.title,
        body: n.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    });
  }

  FirebaseMessaging get _fm => FirebaseMessaging.instance;
  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.doc('users/$uid');

  /// Call after login. Safe to call many times.
  Future<void> start(String uid) async {
    if (kIsWeb) return; // web push needs extra setup; mobile only for now
    try {
      final settings = await _fm.requestPermission(); // asks on Android 13+
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      await _setupForeground();

      final token = await _fm.getToken();
      if (token != null) await _save(uid, token);

      await _refreshSub?.cancel();
      _refreshSub = _fm.onTokenRefresh.listen((t) => _save(uid, t));
    } catch (e) {
      debugPrint('Push setup failed: $e');
    }
  }

  Future<void> _save(String uid, String token) {
    return _userDoc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /// Call before logout so this phone stops receiving the old user's alerts.
  Future<void> stop(String uid) async {
    if (kIsWeb) return;
    try {
      await _refreshSub?.cancel();
      _refreshSub = null;
      await _foregroundSub?.cancel();
      _foregroundSub = null;
      final token = await _fm.getToken();
      if (token != null) {
        await _userDoc(uid).set({
          'fcmTokens': FieldValue.arrayRemove([token]),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Push cleanup failed: $e');
    }
  }
}

final PushService pushService = PushService();