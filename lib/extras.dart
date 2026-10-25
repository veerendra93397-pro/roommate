import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';

// ───────────────────────── Models ─────────────────────────

class Chore {
  final String id;
  final String title;
  final String assignedTo; // member name
  final bool done;
  final bool rotate; // when done, pass it to the next member and reset
  final String lastDoneBy;
  final DateTime? lastDoneAt;
  final DateTime createdAt;
  const Chore({
    required this.id,
    required this.title,
    required this.assignedTo,
    required this.done,
    required this.rotate,
    required this.lastDoneBy,
    required this.lastDoneAt,
    required this.createdAt,
  });
}

class ShoppingItem {
  final String id;
  final String name;
  final String addedBy;
  final bool bought;
  final String boughtBy;
  final DateTime createdAt;
  const ShoppingItem({
    required this.id,
    required this.name,
    required this.addedBy,
    required this.bought,
    required this.boughtBy,
    required this.createdAt,
  });
}

class Comment {
  final String id;
  final String text;
  final String authorName;
  final String authorId;
  final DateTime createdAt;
  const Comment({
    required this.id,
    required this.text,
    required this.authorName,
    required this.authorId,
    required this.createdAt,
  });
}

class ChatMessage {
  final String id;
  final String text;
  final String authorName;
  final String authorId;
  final DateTime createdAt;
  const ChatMessage({
    required this.id,
    required this.text,
    required this.authorName,
    required this.authorId,
    required this.createdAt,
  });
}

class Recurring {
  final String id;
  final String title;
  final Category category;
  final double amount;
  final String paidBy;
  final int day; // day of month, 1..28
  final bool active;
  final String lastRun; // "2026-10" = already added for that month
  final List<String> shareNames; // empty = everyone
  const Recurring({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.paidBy,
    required this.day,
    required this.active,
    required this.lastRun,
    required this.shareNames,
  });
}

DateTime _t(dynamic v) => v is Timestamp ? v.toDate() : DateTime.now();

String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

// ───────────────────────── Service ─────────────────────────

/// Extra room features: chores, shopping list, recurring expenses, comments, budget, UPI.
/// Started/stopped by AppState together with the room subscriptions.
class Extras extends ChangeNotifier {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  final List<Chore> chores = [];
  final List<ShoppingItem> shopping = [];
  final List<Recurring> recurring = [];
  final List<ChatMessage> messages = []; // newest first
  DateTime? _chatSeenAt;

  String? _roomId;
  StreamSubscription<dynamic>? _choreSub;
  StreamSubscription<dynamic>? _shopSub;
  StreamSubscription<dynamic>? _recSub;
  StreamSubscription<dynamic>? _chatSub;
  final Set<String> _running = {}; // recurring ids being added right now

  DocumentReference<Map<String, dynamic>> get _room => _db.doc('rooms/${_roomId!}');

  void start(String roomId) {
    stop();
    _roomId = roomId;
    final room = _db.doc('rooms/$roomId');

    _choreSub = room.collection('chores').snapshots().listen((q) {
      chores
        ..clear()
        ..addAll(q.docs.map((d) {
          final m = d.data();
          return Chore(
            id: d.id,
            title: (m['title'] as String?) ?? '',
            assignedTo: (m['assignedTo'] as String?) ?? '',
            done: m['done'] == true,
            rotate: m['rotate'] == true,
            lastDoneBy: (m['lastDoneBy'] as String?) ?? '',
            lastDoneAt: m['lastDoneAt'] is Timestamp ? _t(m['lastDoneAt']) : null,
            createdAt: _t(m['createdAt']),
          );
        }))
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      notifyListeners();
    }, onError: (_) {});

    _shopSub = room.collection('shopping').snapshots().listen((q) {
      shopping
        ..clear()
        ..addAll(q.docs.map((d) {
          final m = d.data();
          return ShoppingItem(
            id: d.id,
            name: (m['name'] as String?) ?? '',
            addedBy: (m['addedBy'] as String?) ?? '',
            bought: m['bought'] == true,
            boughtBy: (m['boughtBy'] as String?) ?? '',
            createdAt: _t(m['createdAt']),
          );
        }))
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }, onError: (_) {});

    _loadChatSeen(roomId);
    _chatSub = room
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .listen((q) {
      messages
        ..clear()
        ..addAll(q.docs.map((d) {
          final m = d.data();
          return ChatMessage(
            id: d.id,
            text: (m['text'] as String?) ?? '',
            authorName: (m['authorName'] as String?) ?? '',
            authorId: (m['authorId'] as String?) ?? '',
            createdAt: _t(m['createdAt']),
          );
        }))
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }, onError: (_) {});

    _recSub = room.collection('recurring').snapshots().listen((q) {
      recurring
        ..clear()
        ..addAll(q.docs.map((d) {
          final m = d.data();
          return Recurring(
            id: d.id,
            title: (m['title'] as String?) ?? '',
            category: Category.values.firstWhere(
              (c) => c.name == m['category'],
              orElse: () => Category.other,
            ),
            amount: ((m['amount'] as num?) ?? 0).toDouble(),
            paidBy: (m['paidBy'] as String?) ?? '',
            day: ((m['day'] as num?) ?? 1).toInt().clamp(1, 28).toInt(),
            active: m['active'] != false,
            lastRun: (m['lastRun'] as String?) ?? '',
            shareNames: [for (final n in (m['shareNames'] as List<dynamic>? ?? const [])) '$n'],
          );
        }));
      notifyListeners();
      _runDue();
    }, onError: (_) {});
  }

  void stop() {
    _choreSub?.cancel();
    _shopSub?.cancel();
    _recSub?.cancel();
    _chatSub?.cancel();
    _choreSub = _shopSub = _recSub = _chatSub = null;
    messages.clear();
    _chatSeenAt = null;
    _roomId = null;
    chores.clear();
    shopping.clear();
    recurring.clear();
    _running.clear();
  }

  Map<String, dynamic> _notif(String title, String subtitle, String icon) => {
        'title': title,
        'subtitle': subtitle,
        'type': NotifType.other.name,
        'icon': icon,
        'by': appState.uid,
        'createdAt': FieldValue.serverTimestamp(),
      };

  // ───────────── Group chat ─────────────

  Future<void> _loadChatSeen(String roomId) async {
    DateTime seen = DateTime.now(); // first time on this phone: old messages count as read
    try {
      final p = await SharedPreferences.getInstance();
      final ms = p.getInt('chatSeen_$roomId');
      if (ms != null) {
        seen = DateTime.fromMillisecondsSinceEpoch(ms);
      } else {
        await p.setInt('chatSeen_$roomId', seen.millisecondsSinceEpoch);
      }
    } catch (_) {}
    if (_roomId != roomId) return;
    _chatSeenAt = seen;
    notifyListeners();
  }

  int get chatUnread {
    final seen = _chatSeenAt;
    if (seen == null) return 0;
    return messages.where((m) => m.authorId != appState.uid && m.createdAt.isAfter(seen)).length;
  }

  Future<void> markChatSeen() async {
    final id = _roomId;
    if (id == null || chatUnread == 0) return;
    _chatSeenAt = DateTime.now();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('chatSeen_$id', _chatSeenAt!.millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<void> sendMessage(String text) => _room.collection('messages').doc().set({
        'text': text,
        'authorName': appState.userName,
        'authorId': appState.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteMessage(ChatMessage m) => _room.collection('messages').doc(m.id).delete();

  // ───────────── Chores ─────────────

  Future<void> addChore(String title, String assignedTo, bool rotate) async {
    final batch = _db.batch();
    batch.set(_room.collection('chores').doc(), {
      'title': title,
      'assignedTo': assignedTo,
      'done': false,
      'rotate': rotate,
      'lastDoneBy': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_room.collection('notifications').doc(),
        _notif('New chore', '$title – assigned to $assignedTo', 'check'));
    await batch.commit();
  }

  Future<void> deleteChore(Chore c) => _room.collection('chores').doc(c.id).delete();

  Future<void> assignChore(Chore c, String name) =>
      _room.collection('chores').doc(c.id).update({'assignedTo': name});

  /// Tick a chore. Rotating chores pass to the next member and reset.
  Future<void> toggleChore(Chore c) async {
    final ref = _room.collection('chores').doc(c.id);
    if (c.done) {
      await ref.update({'done': false});
      return;
    }
    final names = appState.names;
    if (c.rotate && names.isNotEmpty) {
      final i = names.indexOf(c.assignedTo);
      final next = names[(i + 1) % names.length];
      await ref.update({
        'done': false,
        'assignedTo': next,
        'lastDoneBy': appState.userName,
        'lastDoneAt': FieldValue.serverTimestamp(),
      });
      await _room.collection('notifications').doc().set(
          _notif('Chore done', '${c.title} done by ${appState.userName}. Next: $next', 'check'));
    } else {
      await ref.update({
        'done': true,
        'lastDoneBy': appState.userName,
        'lastDoneAt': FieldValue.serverTimestamp(),
      });
      await _room.collection('notifications').doc().set(
          _notif('Chore done', '${c.title} done by ${appState.userName}', 'check'));
    }
  }

  // ───────────── Shopping list ─────────────

  Future<void> addItem(String name) => _room.collection('shopping').doc().set({
        'name': name,
        'addedBy': appState.userName,
        'bought': false,
        'boughtBy': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> toggleItem(ShoppingItem i) => _room.collection('shopping').doc(i.id).update({
        'bought': !i.bought,
        'boughtBy': i.bought ? '' : appState.userName,
      });

  Future<void> deleteItem(ShoppingItem i) => _room.collection('shopping').doc(i.id).delete();

  Future<void> clearBought() async {
    final batch = _db.batch();
    for (final i in shopping.where((i) => i.bought)) {
      batch.delete(_room.collection('shopping').doc(i.id));
    }
    await batch.commit();
  }

  // ───────────── Recurring expenses ─────────────

  Future<void> addRecurring({
    required String title,
    required Category category,
    required double amount,
    required String paidBy,
    required int day,
  }) async {
    await _room.collection('recurring').doc().set({
      'title': title,
      'category': category.name,
      'amount': amount,
      'paidBy': paidBy,
      'day': day,
      'active': true,
      'lastRun': '',
      'shareNames': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setRecurringActive(Recurring r, bool on) =>
      _room.collection('recurring').doc(r.id).update({'active': on});

  Future<void> deleteRecurring(Recurring r) => _room.collection('recurring').doc(r.id).delete();

  /// Adds this month's expense for every recurring item that is due and not yet added.
  /// Runs on whichever phone opens the app first; a transaction stops duplicates.
  Future<void> _runDue() async {
    if (_roomId == null || appState.uid == null) return;
    final now = DateTime.now();
    final key = _monthKey(now);
    for (final r in List<Recurring>.from(recurring)) {
      if (!r.active || r.lastRun == key || now.day < r.day) continue;
      if (!_running.add(r.id)) continue;
      try {
        await _addRecurringExpense(r, key, now);
      } catch (_) {
        // try again next time the app opens
      } finally {
        _running.remove(r.id);
      }
    }
  }

  Future<void> _addRecurringExpense(Recurring r, String key, DateTime now) async {
    final roomRef = _room;
    final recRef = roomRef.collection('recurring').doc(r.id);
    final expRef = roomRef.collection('expenses').doc();
    final notifRef = roomRef.collection('notifications').doc();
    final names = r.shareNames.isEmpty
        ? appState.names
        : appState.names.where(r.shareNames.contains).toList();
    if (names.isEmpty) return;
    final shares = equalShares(r.amount, names);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(recRef);
      if (!snap.exists) return;
      final d = snap.data()!;
      if (d['active'] == false || d['lastRun'] == key) return;
      tx.update(recRef, {'lastRun': key});
      tx.set(expRef, {
        'title': r.title,
        'category': r.category.name,
        'amount': r.amount,
        'paidBy': r.paidBy,
        'date': Timestamp.fromDate(DateTime(now.year, now.month, r.day)),
        'shares': [
          for (final s in shares.entries) {'name': s.key, 'amount': s.value},
        ],
        'isCustomSplit': false,
        'hasBill': false,
        'recurring': true,
        'createdBy': appState.uid,
      });
      tx.set(notifRef, {
        'title': 'Monthly expense added',
        'subtitle': '${r.title} – ${rupee(r.amount)} by ${r.paidBy}',
        'type': NotifType.expense.name,
        'icon': 'receipt',
        'by': appState.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ───────────── Comments on an expense ─────────────

  Stream<List<Comment>> commentsOf(String expenseId) {
    return _room.collection('expenses').doc(expenseId).collection('comments').snapshots().map((q) {
      final list = q.docs.map((d) {
        final m = d.data();
        return Comment(
          id: d.id,
          text: (m['text'] as String?) ?? '',
          authorName: (m['authorName'] as String?) ?? '',
          authorId: (m['authorId'] as String?) ?? '',
          createdAt: _t(m['createdAt']),
        );
      }).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    });
  }

  Future<void> addComment(Expense e, String text) async {
    final batch = _db.batch();
    batch.set(_room.collection('expenses').doc(e.id).collection('comments').doc(), {
      'text': text,
      'authorName': appState.userName,
      'authorId': appState.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      _room.collection('notifications').doc(),
      _notif('New comment on ${e.title}', '${appState.userName}: $text', 'campaign'),
    );
    await batch.commit();
  }

  Future<void> deleteComment(Expense e, Comment c) =>
      _room.collection('expenses').doc(e.id).collection('comments').doc(c.id).delete();

  // ───────────── Budget ─────────────

  double get monthlyBudget => appState.monthlyBudget;

  double monthTotal([DateTime? month]) {
    final m = month ?? DateTime.now();
    return appState.expenses
        .where((e) => e.date.year == m.year && e.date.month == m.month)
        .fold(0.0, (s, e) => s + e.amount);
  }

  Future<void> setBudget(double amount) => _room.update({'monthlyBudget': amount});

  /// Text for a notification if adding [e] pushes this month past 80% / 100% of the budget.
  String? budgetAlertFor(Expense e) {
    final b = monthlyBudget;
    final now = DateTime.now();
    if (b <= 0 || e.date.year != now.year || e.date.month != now.month) return null;
    final before = monthTotal(now);
    final after = before + e.amount;
    if (before < b && after >= b) {
      return 'This month\'s spending is ${rupee(after)} – over the ${rupee(b)} budget!';
    }
    if (before < b * 0.8 && after >= b * 0.8) {
      return 'This month\'s spending is ${rupee(after)} – 80% of the ${rupee(b)} budget.';
    }
    return null;
  }

  // ───────────── UPI ─────────────

  Future<void> saveUpi(String upi) => _room
      .collection('members')
      .doc(appState.uid!)
      .update({'upi': upi.trim()});

  /// Opens the phone's UPI apps (GPay, PhonePe, Paytm...) with the amount filled in.
  /// Returns false if no UPI app could be opened.
  Future<bool> payViaUpi({required String upiId, required String payeeName, required double amount}) async {
    final uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': upiId,
        'pn': payeeName,
        'am': amount.toStringAsFixed(2),
        'cu': 'INR',
        'tn': 'RoomMate settle up',
      },
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

final Extras extras = Extras();
