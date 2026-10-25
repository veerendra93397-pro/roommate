import 'dart:typed_data';

import 'package:flutter/material.dart';

// AppState (the live Firestore-backed state) lives in app_state.dart.
// It is re-exported here so screens only need to import models.dart.
export 'app_state.dart';
export 'extras.dart';

// ───────────────────────── Helpers ─────────────────────────

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _fullMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// ₹12,345 or ₹12,345.50
String rupee(num v) {
  final value = v.abs().toDouble();
  final whole = (value - value.truncate()).abs() < 0.005;
  final s = value.toStringAsFixed(whole ? 0 : 2);
  final parts = s.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '₹$intPart${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String fmtDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';
/// "Oct 24, 2026 • 3:45 PM"
String fmtFull(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${fmtDate(d)}, ${d.year} • $h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String monthYear(DateTime d) => '${_fullMonths[d.month - 1]} ${d.year}';

String timeAgo(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} m ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'Yesterday';
  return fmtDate(t);
}

/// Splits [total] equally between [names] (cent-accurate, remainder to the first people).
Map<String, double> equalShares(double total, List<String> names) {
  if (names.isEmpty) return {};
  final cents = (total * 100).round();
  final base = cents ~/ names.length;
  var rem = cents % names.length;
  final out = <String, double>{};
  for (final n in names) {
    final c = base + (rem > 0 ? 1 : 0);
    if (rem > 0) rem--;
    out[n] = c / 100;
  }
  return out;
}

/// Notification icon keys are stored in Firestore; this maps them to an icon + colour.
(IconData, Color) notifStyle(String key) {
  switch (key) {
    case 'receipt':
      return (Icons.receipt_long_rounded, const Color(0xFFF59E0B));
    case 'wallet':
      return (Icons.account_balance_wallet_rounded, const Color(0xFF2563EB));
    case 'campaign':
      return (Icons.campaign_rounded, const Color(0xFFE11D48));
    case 'check':
      return (Icons.check_circle_rounded, const Color(0xFF16A34A));
    case 'person':
      return (Icons.person_add_alt_1_rounded, const Color(0xFF2563EB));
    default:
      return (Icons.notifications_rounded, const Color(0xFF64748B));
  }
}

// ───────────────────────── Models ─────────────────────────

enum Category {
  rent('Rent', 'Rent', Icons.home_rounded, Color(0xFF2563EB)),
  food('Food & Groceries', 'Food', Icons.restaurant_rounded, Color(0xFFF59E0B)),
  electricity('Electricity', 'Electricity', Icons.bolt_rounded, Color(0xFF7C3AED)),
  water('Water', 'Water', Icons.water_drop_rounded, Color(0xFF0EA5E9)),
  other('Other', 'Other', Icons.more_horiz_rounded, Color(0xFF94A3B8));

  const Category(this.label, this.shortLabel, this.icon, this.color);
  final String label;
  final String shortLabel;
  final IconData icon;
  final Color color;
}

class Member {
  final String name; // unique inside a room
  final Color color;
  final String uid;
  final Uint8List? photo; // small JPEG, stored in Firestore as base64
  final String upi; // UPI id for receiving payments (optional)
  const Member(this.name, this.color, [this.uid = '', this.photo, this.upi = '']);
}

class Expense {
  final String id;
  final String title;
  final Category category;
  final double amount;
  final String paidBy; // member name
  final DateTime date;
  final Map<String, double> shares; // member name -> amount owed
  final bool isCustomSplit;
  final bool hasBill; // a bill photo is stored in rooms/{id}/bills/{expenseId}

  const Expense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.paidBy,
    required this.date,
    required this.shares,
    this.isCustomSplit = false,
    this.hasBill = false,
  });

  Expense copyWith({Map<String, double>? shares, bool? isCustomSplit}) => Expense(
        id: id,
        title: title,
        category: category,
        amount: amount,
        paidBy: paidBy,
        date: date,
        shares: shares ?? this.shares,
        isCustomSplit: isCustomSplit ?? this.isCustomSplit,
        hasBill: hasBill,
      );
}

/// Someone who entered the room code and is waiting for the owner to approve them.
class JoinRequest {
  final String uid;
  final String name;
  final DateTime createdAt;
  final String status; // pending | approved | rejected
  const JoinRequest({
    required this.uid,
    required this.name,
    required this.createdAt,
    this.status = 'pending',
  });
}

class Settlement {
  final String from; // the person who paid back
  final String to; // the person who received
  final double amount;
  final DateTime date;
  final String id;
  const Settlement(this.from, this.to, this.amount, this.date, [this.id = '']);
}

class Debt {
  final String from;
  final String to;
  final double amount;
  const Debt(this.from, this.to, this.amount);
}

class Announcement {
  final String title;
  final String body;
  final String author;
  final DateTime createdAt;
  final IconData icon;
  final Color color;
  final String id;
  final String authorId;
  final bool edited;
  const Announcement({
    required this.title,
    required this.body,
    required this.author,
    required this.createdAt,
    required this.icon,
    required this.color,
    this.id = '',
    this.authorId = '',
    this.edited = false,
  });
}

enum NotifType { expense, announcement, other }

class AppNotification {
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final IconData icon;
  final Color color;
  final NotifType type;
  final String byUid; // who caused it (so you are not alerted about your own actions)
  const AppNotification({
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.icon,
    required this.color,
    required this.type,
    this.byUid = '',
  });
}
