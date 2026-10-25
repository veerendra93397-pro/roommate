import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Registers this phone for push notifications.
///
/// The phone's FCM token is saved in users/{uid}.fcmTokens. A Cloud Function
/// (functions/index.js) reads those tokens and sends the actual push messages
/// whenever something happens in a room.
class PushService {
  StreamSubscription<String>? _refreshSub;

  FirebaseMessaging get _fm => FirebaseMessaging.instance;
  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.doc('users/$uid');

  /// Call after login. Safe to call many times.
  Future<void> start(String uid) async {
    if (kIsWeb) return; // web push needs extra setup; mobile only for now
    try {
      final settings = await _fm.requestPermission(); // asks on Android 13+
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

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
