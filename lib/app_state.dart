import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;

import 'extras.dart';
import 'models.dart';
import 'services/push_service.dart';
import 'widgets.dart';

/// Where the app is in its life: decides which screen AuthGate shows.
enum SessionStatus { loading, signedOut, noRoom, pending, ready, error }

class AppException implements Exception {
  final String message;
  AppException(this.message);
  @override
  String toString() => message;
}

String friendlyError(Object e) {
  if (e is AppException) return e.message;
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permission denied. Make sure the Firestore rules are published.';
      case 'unavailable':
        return 'Cannot reach the server. Check your internet connection.';
      case 'not-found':
        return 'Not found. Is the Firestore database created in Firebase Console?';
      default:
        return '${e.message ?? 'Firebase error'} [${e.code}]';
    }
  }
  return e.toString();
}

const _palette = [
  0xFF0F9D8A, 0xFF7C3AED, 0xFF16A34A, 0xFFF59E0B,
  0xFFE11D48, 0xFF0EA5E9, 0xFFEC4899, 0xFF64748B,
];

/// Single source of truth for the UI. Reads live from Cloud Firestore.
///
/// Firestore layout
///   users/{uid}                      name, email, roomId
///   roomCodes/{CODE}                 roomId
///   rooms/{roomId}                   name, code, ownerId, memberIds[]
///   rooms/{roomId}/members/{uid}     uid, name, colorValue, joinedAt
///   rooms/{roomId}/expenses/{id}     title, category, amount, paidBy, date, shares[], isCustomSplit
///   rooms/{roomId}/settlements/{id}  from, to, amount, date
///   rooms/{roomId}/announcements/{id} title, body, authorName, createdAt
///   rooms/{roomId}/notifications/{id} title, subtitle, type, icon, createdAt
class AppState extends ChangeNotifier {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  SessionStatus status = SessionStatus.loading;
  String? errorMessage;

  String? uid;
  String userName = '';
  String userEmail = '';
  String? roomId;
  String roomName = '';
  String roomCode = '';
  String ownerId = '';
  double monthlyBudget = 0; // 0 = no budget set
  bool get isOwner => uid != null && ownerId == uid;

  // Join-request flow
  String? pendingRoomId; // room I asked to join and am waiting for
  String pendingRoomName = '';
  String? joinMessage; // one-time message shown on the Create/Join screen
  bool _completing = false;
  String? _myPhoto; // my profile photo (base64), copied into each room I join
  DateTime? _notifSeenAt; // notifications newer than this are "unread"
  bool _notifPrimed = false; // first notification snapshot is the initial load, not news
  bool _checkingRemoved = false;
  final List<JoinRequest> joinRequests = []; // pending requests for MY room (owner view)

  final List<Member> members = [];
  final List<Expense> expenses = [];
  final List<Settlement> settlements = [];
  final List<Announcement> announcements = [];
  final List<AppNotification> notifications = [];

  StreamSubscription<dynamic>? _userSub;
  StreamSubscription<dynamic>? _roomSub;
  StreamSubscription<dynamic>? _memSub;
  StreamSubscription<dynamic>? _expSub;
  StreamSubscription<dynamic>? _setSub;
  StreamSubscription<dynamic>? _annSub;
  StreamSubscription<dynamic>? _notSub;
  StreamSubscription<dynamic>? _reqSub;
  StreamSubscription<dynamic>? _myReqSub;
  bool _roomLoaded = false;
  bool _membersLoaded = false;

  List<String> get names => members.map((m) => m.name).toList();

  Member member(String name) => members.firstWhere(
        (m) => m.name == name,
        orElse: () => Member(name, const Color(0xFF94A3B8)),
      );

  // ───────────── Session ─────────────

  Future<void> onSignedIn(User user) async {
    if (uid == user.uid && _userSub != null) return;
    _cancelAll();
    _resetData();
    uid = user.uid;
    userEmail = user.email ?? '';
    userName = user.displayName ?? (user.email ?? 'Me').split('@').first;
    _setStatus(SessionStatus.loading);
    try {
      final ref = _db.doc('users/${user.uid}');
      final snap = await ref.get();
      if (uid != user.uid) return; // signed out in the meantime
      if (!snap.exists) {
        await ref.set({
          'name': userName,
          'email': userEmail,
          'roomId': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (uid != user.uid) return;
      // includeMetadataChanges: we need the extra event Firestore sends when our
      // own write is confirmed by the server (hasPendingWrites true -> false).
      _userSub = ref
          .snapshots(includeMetadataChanges: true)
          .listen(_onUserDoc, onError: _fail);
      pushService.start(user.uid); // register this phone for push notifications
    } catch (e) {
      _fail(e);
    }
  }

  void onSignedOut() {
    _cancelAll();
    _resetData();
    uid = null;
    userName = '';
    userEmail = '';
    _setStatus(SessionStatus.signedOut);
  }

  Future<void> retry() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      onSignedOut();
      return;
    }
    uid = null; // force a fresh start
    await onSignedIn(u);
  }

  void _onUserDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
    // Wait until our own writes are confirmed by the server, otherwise the
    // room listeners could start before the rules allow us to read the room.
    if (!snap.exists || snap.metadata.hasPendingWrites) return;
    final data = snap.data() ?? {};
    _myPhoto = data['photo'] as String?;
    final seen = data['notifSeenAt'];
    _notifSeenAt = seen is Timestamp ? seen.toDate() : null;
    final newRoom = data['roomId'] as String?;

    // 1) I am in a room.
    if (newRoom != null) {
      if (newRoom == roomId && _roomSub != null) return; // already listening
      _cancelRoom();
      _clearRoomData();
      _cancelMyRequest();
      pendingRoomId = null;
      roomId = newRoom;
      _setStatus(SessionStatus.loading);
      _subscribeRoom(newRoom);
      return;
    }

    // 2) No room (any old room data is dropped).
    if (roomId != null) {
      _cancelRoom();
      _clearRoomData();
      roomId = null;
    }

    // 3) I asked to join a room and am waiting for the owner.
    final newPending = data['pendingRoomId'] as String?;
    if (newPending != null) {
      if (newPending == pendingRoomId && _myReqSub != null) return;
      _cancelMyRequest();
      pendingRoomId = newPending;
      pendingRoomName = (data['pendingRoomName'] as String?) ?? '';
      _setStatus(SessionStatus.pending);
      _watchMyRequest(newPending);
      return;
    }

    // 4) Nothing yet: show Create / Join.
    _cancelMyRequest();
    pendingRoomId = null;
    if (status != SessionStatus.noRoom && status != SessionStatus.error) {
      _setStatus(SessionStatus.noRoom);
    }
  }

  void _subscribeRoom(String id) {
    extras.start(id);
    _roomLoaded = false;
    _membersLoaded = false;
    _notifPrimed = false;
    final room = _db.doc('rooms/$id');

    _roomSub = room.snapshots().listen((s) {
      if (!s.exists) {
        _roomFail(AppException('This room no longer exists.'));
        return;
      }
      final d = s.data()!;
      roomName = (d['name'] as String?) ?? '';
      roomCode = (d['code'] as String?) ?? '';
      ownerId = (d['ownerId'] as String?) ?? '';
      monthlyBudget = ((d['monthlyBudget'] as num?) ?? 0).toDouble();
      _roomLoaded = true;
      _maybeReady();
    }, onError: _roomFail);

    _memSub = room.collection('members').orderBy('joinedAt').snapshots().listen((q) {
      members
        ..clear()
        ..addAll(q.docs.map(_memberFrom));
      for (final m in members) {
        if (m.uid == uid) userName = m.name;
      }
      _membersLoaded = true;
      _maybeReady();
    }, onError: _roomFail);

    _expSub = room
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots()
        .listen((q) {
      expenses
        ..clear()
        ..addAll(q.docs.map(_expenseFrom));
      notifyListeners();
    }, onError: _roomFail);

    _setSub = room.collection('settlements').orderBy('date').snapshots().listen((q) {
      settlements
        ..clear()
        ..addAll(q.docs.map((d) {
          final m = d.data();
          return Settlement(
            (m['from'] as String?) ?? '',
            (m['to'] as String?) ?? '',
            ((m['amount'] as num?) ?? 0).toDouble(),
            _ts(m['date']),
            d.id,
          );
        }));
      notifyListeners();
    }, onError: _roomFail);

    _annSub = room
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((q) {
      announcements
        ..clear()
        ..addAll(q.docs.map((d) {
          final m = d.data();
          return Announcement(
            title: (m['title'] as String?) ?? '',
            body: (m['body'] as String?) ?? '',
            author: (m['authorName'] as String?) ?? '',
            createdAt: _ts(m['createdAt']),
            icon: Icons.campaign_rounded,
            color: const Color(0xFF2563EB),
            id: d.id,
            authorId: (m['authorId'] as String?) ?? '',
            edited: m['edited'] == true,
          );
        }));
      notifyListeners();
    }, onError: _roomFail);

    _notSub = room
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((q) {
      notifications
        ..clear()
        ..addAll(q.docs.map((d) {
          final m = d.data();
          final style = notifStyle((m['icon'] as String?) ?? '');
          return AppNotification(
            title: (m['title'] as String?) ?? '',
            subtitle: (m['subtitle'] as String?) ?? '',
            createdAt: _ts(m['createdAt']),
            byUid: (m['by'] as String?) ?? '',
            icon: style.$1,
            color: style.$2,
            type: NotifType.values.firstWhere(
              (t) => t.name == m['type'],
              orElse: () => NotifType.other,
            ),
          );
        }));
      // Alert about notifications that arrive while the app is open
      // (the first snapshot is just the existing list).
      if (_notifPrimed) {
        for (final c in q.docChanges) {
          if (c.type != DocumentChangeType.added) continue;
          if (c.doc.metadata.hasPendingWrites) continue; // my own action
          final m = c.doc.data();
          if (m == null || m['by'] == uid) continue;
          _announce((m['title'] as String?) ?? '', (m['subtitle'] as String?) ?? '');
        }
      }
      _notifPrimed = true;
      notifyListeners();
    }, onError: _roomFail);

    _reqSub = room
        .collection('joinRequests')
        .orderBy('createdAt')
        .snapshots()
        .listen((q) {
      joinRequests
        ..clear()
        ..addAll(q.docs
            .map((d) {
              final m = d.data();
              return JoinRequest(
                uid: (m['uid'] as String?) ?? d.id,
                name: (m['name'] as String?) ?? 'Someone',
                createdAt: _ts(m['createdAt']),
                status: (m['status'] as String?) ?? 'pending',
              );
            })
            .where((r) => r.status == 'pending'));
      notifyListeners();
    }, onError: _roomFail);
  }

  void _maybeReady() {
    if (_roomLoaded && _membersLoaded && status == SessionStatus.loading) {
      status = SessionStatus.ready;
      if (_notifSeenAt == null && uid != null) {
        // First time in the app: everything older than now counts as already seen.
        _notifSeenAt = DateTime.now();
        _db
            .doc('users/${uid!}')
            .update({'notifSeenAt': FieldValue.serverTimestamp()}).catchError((_) {});
      }
    }
    notifyListeners();
  }

  // ───────────── Parsing ─────────────

  DateTime _ts(dynamic v) => v is Timestamp ? v.toDate() : DateTime.now();

  Member _memberFrom(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    Uint8List? photo;
    final p = m['photo'];
    if (p is String && p.isNotEmpty) {
      try {
        photo = base64Decode(p);
      } catch (_) {
        photo = null;
      }
    }
    return Member(
      (m['name'] as String?) ?? 'Member',
      Color((m['colorValue'] as num?)?.toInt() ?? 0xFF94A3B8),
      (m['uid'] as String?) ?? d.id,
      photo,
      (m['upi'] as String?) ?? '',
    );
  }

  Expense _expenseFrom(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final shares = <String, double>{};
    for (final s in (m['shares'] as List<dynamic>? ?? const [])) {
      shares[(s['name'] as String?) ?? ''] = ((s['amount'] as num?) ?? 0).toDouble();
    }
    return Expense(
      id: d.id,
      title: (m['title'] as String?) ?? '',
      category: Category.values.firstWhere(
        (c) => c.name == m['category'],
        orElse: () => Category.other,
      ),
      amount: ((m['amount'] as num?) ?? 0).toDouble(),
      paidBy: (m['paidBy'] as String?) ?? '',
      date: _ts(m['date']),
      shares: shares,
      isCustomSplit: m['isCustomSplit'] == true,
      hasBill: m['hasBill'] == true,
    );
  }

  Map<String, dynamic> _expenseMap(Expense e) => {
        'title': e.title,
        'category': e.category.name,
        'amount': e.amount,
        'paidBy': e.paidBy,
        'date': Timestamp.fromDate(e.date),
        'shares': [
          for (final s in e.shares.entries) {'name': s.key, 'amount': s.value},
        ],
        'isCustomSplit': e.isCustomSplit,
        'hasBill': e.hasBill,
        'createdBy': uid,
      };

  Map<String, dynamic> _notifMap(
    String title,
    String subtitle,
    NotifType type,
    String icon,
  ) =>
      {
        'title': title,
        'subtitle': subtitle,
        'type': type.name,
        'icon': icon,
        'by': uid,
        'createdAt': FieldValue.serverTimestamp(),
      };

  // ───────────── Balances (calculated on the device) ─────────────

  /// Positive = the person is owed money, negative = the person owes money.
  double balanceOf(String name) {
    double bal = 0;
    for (final e in expenses) {
      if (e.paidBy == name) bal += e.amount;
      bal -= e.shares[name] ?? 0;
    }
    for (final s in settlements) {
      if (s.from == name) bal += s.amount;
      if (s.to == name) bal -= s.amount;
    }
    return (bal * 100).round() / 100;
  }

  /// Minimal list of payments that settles everyone (greedy).
  List<Debt> simplifiedDebts() {
    final creditors = <List<dynamic>>[];
    final debtors = <List<dynamic>>[];
    for (final m in members) {
      final b = balanceOf(m.name);
      if (b > 0.005) creditors.add([m.name, b]);
      if (b < -0.005) debtors.add([m.name, -b]);
    }
    creditors.sort((a, b) => (b[1] as double).compareTo(a[1] as double));
    debtors.sort((a, b) => (b[1] as double).compareTo(a[1] as double));

    final result = <Debt>[];
    var i = 0, j = 0;
    while (i < debtors.length && j < creditors.length) {
      final pay = (debtors[i][1] as double) < (creditors[j][1] as double)
          ? debtors[i][1] as double
          : creditors[j][1] as double;
      result.add(Debt(debtors[i][0] as String, creditors[j][0] as String,
          (pay * 100).round() / 100));
      debtors[i][1] = (debtors[i][1] as double) - pay;
      creditors[j][1] = (creditors[j][1] as double) - pay;
      if ((debtors[i][1] as double) < 0.005) i++;
      if ((creditors[j][1] as double) < 0.005) j++;
    }
    return result;
  }

  // ───────────── Writes ─────────────

  DocumentReference<Map<String, dynamic>> get _room => _db.doc('rooms/${roomId!}');

  Future<void> addExpense(Expense e, {Uint8List? bill}) async {
    final batch = _db.batch();
    final ref = _room.collection('expenses').doc();
    batch.set(ref, {..._expenseMap(e), 'hasBill': bill != null});
    if (bill != null) {
      batch.set(_room.collection('bills').doc(ref.id), {
        'data': base64Encode(bill),
        'by': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    batch.set(
      _room.collection('notifications').doc(),
      _notifMap('New expense added', '${e.title} – ${rupee(e.amount)} by ${e.paidBy}',
          NotifType.expense, 'receipt'),
    );
    final alert = extras.budgetAlertFor(e);
    if (alert != null) {
      batch.set(
        _room.collection('notifications').doc(),
        _notifMap('Budget alert', alert, NotifType.expense, 'wallet'),
      );
    }
    await batch.commit();
  }

  Future<void> updateExpense(Expense e) {
    return _room.collection('expenses').doc(e.id).update({
      'shares': [
        for (final s in e.shares.entries) {'name': s.key, 'amount': s.value},
      ],
      'isCustomSplit': e.isCustomSplit,
    });
  }

  /// [newBill] replaces the bill photo; [removeBill] deletes it.
  Future<void> editExpense(Expense e, {Uint8List? newBill, bool removeBill = false}) async {
    final batch = _db.batch();
    batch.update(_room.collection('expenses').doc(e.id), {
      'title': e.title,
      'category': e.category.name,
      'amount': e.amount,
      'paidBy': e.paidBy,
      'shares': [
        for (final s in e.shares.entries) {'name': s.key, 'amount': s.value},
      ],
      'isCustomSplit': e.isCustomSplit,
      if (newBill != null || removeBill) 'hasBill': newBill != null,
    });
    if (newBill != null) {
      batch.set(_room.collection('bills').doc(e.id), {
        'data': base64Encode(newBill),
        'by': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else if (removeBill) {
      batch.delete(_room.collection('bills').doc(e.id));
    }
    batch.set(
      _room.collection('notifications').doc(),
      _notifMap('Expense updated', '${e.title} – ${rupee(e.amount)}',
          NotifType.expense, 'receipt'),
    );
    await batch.commit();
  }

  Future<void> deleteExpense(Expense e) async {
    final batch = _db.batch();
    batch.delete(_room.collection('expenses').doc(e.id));
    if (e.hasBill) batch.delete(_room.collection('bills').doc(e.id));
    batch.set(
      _room.collection('notifications').doc(),
      _notifMap('Expense deleted', '${e.title} – ${rupee(e.amount)} was removed',
          NotifType.expense, 'receipt'),
    );
    await batch.commit();
  }

  /// Bill photos are loaded on demand so the expense list stays light.
  Future<Uint8List?> loadBill(String expenseId) async {
    final snap = await _room.collection('bills').doc(expenseId).get();
    final data = snap.data()?['data'];
    if (data is! String || data.isEmpty) return null;
    return base64Decode(data);
  }

  Future<void> recordPayment(String from, String to, double amount) async {
    final batch = _db.batch();
    batch.set(_room.collection('settlements').doc(), {
      'from': from,
      'to': to,
      'amount': amount,
      'date': Timestamp.now(),
    });
    batch.set(
      _room.collection('notifications').doc(),
      _notifMap('Payment received', '$from paid ${rupee(amount)} to $to',
          NotifType.expense, 'check'),
    );
    await batch.commit();
  }

  Future<void> addAnnouncement(String title, String body) async {
    final batch = _db.batch();
    batch.set(_room.collection('announcements').doc(), {
      'title': title,
      'body': body,
      'authorName': userName,
      'authorId': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      _room.collection('notifications').doc(),
      _notifMap('Announcement', title, NotifType.announcement, 'campaign'),
    );
    await batch.commit();
  }

  // ───────────── Notifications: unread count + live alerts ─────────────

  DateTime? get notifSeenAt => _notifSeenAt;

  bool isUnread(AppNotification n) =>
      _notifSeenAt != null && n.byUid != uid && n.createdAt.isAfter(_notifSeenAt!);

  int get unreadCount => notifications.where(isUnread).length;

  /// Called when the notification list is opened.
  void markNotificationsRead() {
    final u = uid;
    if (u == null) return;
    final newest = notifications.isEmpty ? DateTime.now() : notifications.first.createdAt;
    if (_notifSeenAt != null && !newest.isAfter(_notifSeenAt!)) return;
    _notifSeenAt = newest;
    notifyListeners();
    _db
        .doc('users/$u')
        .update({'notifSeenAt': Timestamp.fromDate(newest)}).catchError((_) {});
  }

  /// A small banner shown to every member while the app is open.
  void _announce(String title, String subtitle) {
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (subtitle.isNotEmpty) Text(subtitle),
          ],
        ),
      ),
    );
  }

  // ───────────── Room management (owner) ─────────────

  Future<void> renameRoom(String rawName) async {
    if (!isOwner) throw AppException('Only the room owner can rename the room.');
    final name = rawName.trim();
    if (name.isEmpty) throw AppException('Room name cannot be empty.');
    final batch = _db.batch();
    batch.update(_room, {'name': name});
    if (roomCode.isNotEmpty) {
      batch.update(_db.doc('roomCodes/$roomCode'), {'roomName': name});
    }
    batch.set(
      _room.collection('notifications').doc(),
      _notifMap('Room renamed', 'The room is now called "$name"', NotifType.other, 'campaign'),
    );
    await batch.commit();
  }

  /// Owner removes a member. Their balance must be settled first so nobody is left owed.
  Future<void> removeMember(Member m) async {
    if (!isOwner) throw AppException('Only the room owner can remove members.');
    if (m.uid == uid) throw AppException('You cannot remove yourself.');
    final bal = balanceOf(m.name);
    if (bal.abs() >= 0.01) {
      throw AppException(
          '${m.name} still has an unsettled balance of ${rupee(bal.abs())}. Settle up before removing them.');
    }
    final batch = _db.batch();
    batch.update(_room, {'memberIds': FieldValue.arrayRemove([m.uid])});
    batch.delete(_room.collection('members').doc(m.uid));
    batch.set(_room.collection('removedMembers').doc(m.uid), {
      'name': m.name,
      'at': FieldValue.serverTimestamp(),
    });
    batch.set(
      _room.collection('notifications').doc(),
      _notifMap('Member removed', '${m.name} was removed from the room',
          NotifType.other, 'person'),
    );
    await batch.commit();
  }

  /// Only the author of an announcement (or the room owner) may change it.
  bool canManage(Announcement a) => uid != null && (a.authorId == uid || isOwner);

  Future<void> editAnnouncement(String id, String title, String body) {
    return _room.collection('announcements').doc(id).update({
      'title': title,
      'body': body,
      'edited': true,
    });
  }

  Future<void> deleteAnnouncement(String id) {
    return _room.collection('announcements').doc(id).delete();
  }

  // ───────────── Profile ─────────────

  /// Renames the current user everywhere: Firebase Auth, users/{uid}, the room's
  /// member list AND every expense / payment / announcement that used the old name
  /// (names are the keys inside those documents).
  Future<void> updateProfileName(String rawName) async {
    final u = uid;
    if (u == null) throw AppException('Please login again.');
    final newName = rawName.trim();
    if (newName.isEmpty) throw AppException('Name cannot be empty.');
    final old = userName;
    if (newName == old) return;
    final clash = members.any(
      (m) => m.uid != u && m.name.toLowerCase() == newName.toLowerCase(),
    );
    if (clash) throw AppException('Someone in your room already uses that name.');

    final ops = <void Function(WriteBatch)>[];
    ops.add((b) => b.update(_db.doc('users/$u'), {'name': newName}));

    if (roomId != null) {
      ops.add((b) => b.update(_room.collection('members').doc(u), {'name': newName}));

      for (final e in expenses) {
        if (e.paidBy != old && !e.shares.containsKey(old)) continue;
        final shares = {
          for (final s in e.shares.entries) (s.key == old ? newName : s.key): s.value,
        };
        ops.add((b) => b.update(_room.collection('expenses').doc(e.id), {
              'paidBy': e.paidBy == old ? newName : e.paidBy,
              'shares': [
                for (final s in shares.entries) {'name': s.key, 'amount': s.value},
              ],
            }));
      }
      for (final s in settlements) {
        if (s.id.isEmpty || (s.from != old && s.to != old)) continue;
        ops.add((b) => b.update(_room.collection('settlements').doc(s.id), {
              'from': s.from == old ? newName : s.from,
              'to': s.to == old ? newName : s.to,
            }));
      }
      for (final a in announcements) {
        if (a.id.isEmpty || a.authorId != u) continue;
        ops.add((b) => b.update(
            _room.collection('announcements').doc(a.id), {'authorName': newName}));
      }
    }

    await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
    for (var i = 0; i < ops.length; i += 400) {
      final batch = _db.batch();
      for (final op in ops.skip(i).take(400)) {
        op(batch);
      }
      await batch.commit();
    }
  }

  /// Saves a small profile photo (the picker already shrinks it to ~400px JPEG).
  /// It is kept as base64 in Firestore, so no paid Firebase Storage is needed.
  Future<void> setProfilePhoto(Uint8List bytes) async {
    final u = uid;
    if (u == null) throw AppException('Please login again.');
    if (bytes.length > 200 * 1024) {
      throw AppException('That image is too large. Please pick a smaller one.');
    }
    final b64 = base64Encode(bytes);
    final batch = _db.batch();
    batch.update(_db.doc('users/$u'), {'photo': b64});
    if (roomId != null) {
      batch.update(_room.collection('members').doc(u), {'photo': b64});
    }
    await batch.commit();
  }

  Future<void> removeProfilePhoto() async {
    final u = uid;
    if (u == null) throw AppException('Please login again.');
    final batch = _db.batch();
    batch.update(_db.doc('users/$u'), {'photo': FieldValue.delete()});
    if (roomId != null) {
      batch.update(_room.collection('members').doc(u), {'photo': FieldValue.delete()});
    }
    await batch.commit();
  }

  /// Owner only: hand the room over to another member.
  Future<void> transferOwnership(Member m) async {
    if (!isOwner) throw AppException('Only the room owner can do this.');
    final batch = _db.batch();
    batch.update(_room, {'ownerId': m.uid});
    batch.set(
      _room.collection('notifications').doc(),
      _notifMap('New room owner', '${m.name} is now the room owner',
          NotifType.other, 'person'),
    );
    await batch.commit();
  }

  // ───────────── Rooms ─────────────

  int _colorFor(String u) => _palette[u.hashCode.abs() % _palette.length];

  Future<String> _freshCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    for (var i = 0; i < 8; i++) {
      final code = List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
      final snap = await _db.doc('roomCodes/$code').get();
      if (!snap.exists) return code;
    }
    throw AppException('Could not generate a room code. Please try again.');
  }

  Future<void> createRoom(String name) async {
    final u = uid;
    if (u == null) throw AppException('Please login again.');
    final code = await _freshCode();
    final roomRef = _db.collection('rooms').doc();
    final batch = _db.batch();
    batch.set(roomRef, {
      'name': name,
      'code': code,
      'ownerId': u,
      'memberIds': [u],
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.doc('roomCodes/$code'), {'roomId': roomRef.id, 'roomName': name});
    batch.set(roomRef.collection('members').doc(u), {
      'uid': u,
      'name': userName,
      'colorValue': _colorFor(u),
      if (_myPhoto != null) 'photo': _myPhoto,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.doc('users/$u'), {'roomId': roomRef.id});
    await batch.commit();
    // The users/{uid} listener now moves the app to the Home screen.
  }

  /// Step 1 of joining: send a request. The owner must approve it.
  Future<void> joinRoom(String rawCode) async {
    final u = uid;
    if (u == null) throw AppException('Please login again.');
    final code = rawCode.trim().toUpperCase();
    final codeSnap = await _db.doc('roomCodes/$code').get();
    if (!codeSnap.exists) throw AppException('No room found with code $code.');
    final rid = codeSnap.data()!['roomId'] as String;
    final roomLabel = (codeSnap.data()!['roomName'] as String?) ?? 'Room $code';

    final batch = _db.batch();
    batch.set(_db.doc('rooms/$rid/joinRequests/$u'), {
      'uid': u,
      'name': userName,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.doc('users/$u'), {
      'pendingRoomId': rid,
      'pendingRoomName': roomLabel,
    });
    await batch.commit();
    // users/{uid} listener now shows the "waiting for approval" screen.
  }

  /// Owner: let the person in.
  Future<void> approveRequest(JoinRequest r) async {
    final batch = _db.batch();
    batch.update(_room, {'memberIds': FieldValue.arrayUnion([r.uid])});
    batch.update(_room.collection('joinRequests').doc(r.uid), {'status': 'approved'});
    await batch.commit();
  }

  /// Owner: decline.
  Future<void> rejectRequest(JoinRequest r) {
    return _room.collection('joinRequests').doc(r.uid).update({'status': 'rejected'});
  }

  /// Requester: withdraw my own request.
  Future<void> cancelJoinRequest() => _finishPending(null);

  /// Requester side: watch my request until the owner answers.
  void _watchMyRequest(String rid) {
    _completing = false;
    final ref = _db.doc('rooms/$rid/joinRequests/${uid!}');
    _myReqSub = ref.snapshots().listen((s) {
      if (s.metadata.hasPendingWrites) return;
      if (!s.exists) {
        if (s.metadata.isFromCache) return;
        _finishPending('Your join request is no longer available.');
        return;
      }
      final st = s.data()?['status'];
      if (st == 'approved') {
        _completeJoin(rid);
      } else if (st == 'rejected') {
        _finishPending('The room owner declined your request.');
      }
    }, onError: _fail);
  }

  Future<void> _finishPending(String? message) async {
    final u = uid;
    final rid = pendingRoomId;
    if (u == null || rid == null) return;
    _cancelMyRequest();
    joinMessage = message;
    try {
      final batch = _db.batch();
      batch.delete(_db.doc('rooms/$rid/joinRequests/$u'));
      batch.update(_db.doc('users/$u'), {
        'pendingRoomId': null,
        'pendingRoomName': null,
      });
      await batch.commit();
    } catch (e) {
      _fail(e);
    }
  }

  void _cancelMyRequest() {
    _myReqSub?.cancel();
    _myReqSub = null;
  }

  /// Step 2: the owner approved me, so I create my member record and enter the room.
  Future<void> _completeJoin(String rid) async {
    if (_completing) return;
    _completing = true;
    final u = uid!;
    final roomRef = _db.doc('rooms/$rid');
    final batch = _db.batch();
    batch.set(roomRef.collection('members').doc(u), {
      'uid': u,
      'name': userName,
      'colorValue': _colorFor(u),
      if (_myPhoto != null) 'photo': _myPhoto,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.doc('users/$u'), {
      'roomId': rid,
      'pendingRoomId': null,
      'pendingRoomName': null,
    });
    batch.delete(roomRef.collection('joinRequests').doc(u));
    try {
      await batch.commit();
    } catch (e) {
      _completing = false;
      _fail(e);
      return;
    }

    try {
      final finalName = await _ensureUniqueName(rid);
      await roomRef.collection('notifications').add(
            _notifMap('New member joined', '$finalName joined the room',
                NotifType.other, 'person'),
          );
    } catch (e) {
      debugPrint('post-join step failed: $e');
    }
  }

  /// Names are used as keys inside expenses, so they must be unique in a room.
  Future<String> _ensureUniqueName(String rid) async {
    final mems = await _db.collection('rooms/$rid/members').get();
    final me = mems.docs.firstWhere((d) => d.id == uid);
    final mine = ((me.data()['name'] as String?) ?? '').trim();
    final taken = mems.docs
        .where((d) => d.id != uid)
        .map((d) => ((d.data()['name'] as String?) ?? '').trim().toLowerCase())
        .toSet();
    var name = mine;
    var i = 2;
    while (taken.contains(name.toLowerCase())) {
      name = '$mine $i';
      i++;
    }
    if (name != mine) await me.reference.update({'name': name});
    return name;
  }

  Future<void> leaveRoom() async {
    final rid = roomId;
    final u = uid;
    if (rid == null || u == null) return;
    if (isOwner) {
      throw AppException(
          'You are the room owner. Make another member the owner first (Members screen), then you can leave.');
    }
    _cancelRoom();
    _clearRoomData();
    roomId = null;
    _setStatus(SessionStatus.noRoom);
    try {
      final batch = _db.batch();
      batch.update(_db.doc('rooms/$rid'), {'memberIds': FieldValue.arrayRemove([u])});
      batch.delete(_db.doc('rooms/$rid/members/$u'));
      batch.update(_db.doc('users/$u'), {'roomId': null});
      await batch.commit();
    } catch (e) {
      await retry();
      rethrow;
    }
  }

  // ───────────── Internals ─────────────

  void _setStatus(SessionStatus s) {
    status = s;
    if (s != SessionStatus.error) errorMessage = null;
    notifyListeners();
  }

  void _fail(Object e, [StackTrace? st]) {
    debugPrint('Firestore error: $e');
    errorMessage = friendlyError(e);
    status = SessionStatus.error;
    notifyListeners();
  }

  void _roomFail(Object e, [StackTrace? st]) {
    if (roomId == null) return; // we just left the room; ignore late errors
    if (e is FirebaseException && e.code == 'permission-denied') {
      _checkRemoved(e);
      return;
    }
    _fail(e);
  }

  /// A permission error can mean the owner removed me. The owner leaves a marker
  /// document that only I can read, which tells it apart from a rules problem.
  Future<void> _checkRemoved(Object original) async {
    if (_checkingRemoved) return;
    _checkingRemoved = true;
    final rid = roomId;
    final u = uid;
    try {
      if (rid == null || u == null) return;
      final marker = await _db.doc('rooms/$rid/removedMembers/$u').get();
      if (!marker.exists) {
        _fail(original);
        return;
      }
      _cancelRoom();
      _clearRoomData();
      roomId = null;
      joinMessage = 'The room owner removed you from the room.';
      _setStatus(SessionStatus.noRoom);
      final batch = _db.batch();
      batch.delete(_db.doc('rooms/$rid/removedMembers/$u'));
      batch.update(_db.doc('users/$u'), {'roomId': null});
      await batch.commit();
    } catch (_) {
      _fail(original);
    } finally {
      _checkingRemoved = false;
    }
  }

  void _cancelRoom() {
    _roomSub?.cancel();
    _memSub?.cancel();
    _expSub?.cancel();
    _setSub?.cancel();
    _annSub?.cancel();
    _notSub?.cancel();
    _reqSub?.cancel();
    _roomSub = _memSub = _expSub = _setSub = _annSub = _notSub = _reqSub = null;
    extras.stop();
  }

  void _cancelAll() {
    _userSub?.cancel();
    _userSub = null;
    _cancelMyRequest();
    _cancelRoom();
  }

  void _clearRoomData() {
    members.clear();
    expenses.clear();
    settlements.clear();
    announcements.clear();
    notifications.clear();
    joinRequests.clear();
    roomName = '';
    roomCode = '';
    ownerId = '';
    monthlyBudget = 0;
  }

  void _resetData() {
    _clearRoomData();
    roomId = null;
    pendingRoomId = null;
    pendingRoomName = '';
    joinMessage = null;
  }
}

final AppState appState = AppState();

/// Lets AppState show a banner from anywhere (set on MaterialApp in main.dart).
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
