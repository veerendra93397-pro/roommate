import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'announcements_screen.dart';
import 'chores_screen.dart';
import 'expenses_screen.dart';
import 'members_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _filter = 0; // 0 all, 1 expenses, 2 announcements
  DateTime? _seenBefore; // what was already read when this screen was opened

  @override
  void initState() {
    super.initState();
    _seenBefore = appState.notifSeenAt;
  }

  bool _isNew(AppNotification n) =>
      _seenBefore != null && n.byUid != appState.uid && n.createdAt.isAfter(_seenBefore!);

  /// Where "Open" takes you for this kind of notification (null = nowhere to go).
  Widget? _target(AppNotification n) {
    if (n.type == NotifType.announcement) return const AnnouncementsScreen();
    if (n.type == NotifType.expense) return const ExpensesScreen();
    if (n.icon == Icons.check_circle_rounded) return const ChoresScreen();
    if (n.icon == Icons.person_add_alt_1_rounded) return const MembersScreen();
    return null;
  }

  void _details(AppNotification n) {
    final target = _target(n);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: n.color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(n.icon, color: n.color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(n.title,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SelectableText(n.subtitle, style: const TextStyle(fontSize: 15, height: 1.4)),
              const SizedBox(height: 10),
              Text(fmtFull(n.createdAt),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (target != null) ...[
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Open',
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => target));
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        // Opening this screen marks everything as read (does nothing if already read).
        WidgetsBinding.instance.addPostFrameCallback((_) => appState.markNotificationsRead());
        final items = appState.notifications.where((n) {
          if (_filter == 1) return n.type == NotifType.expense;
          if (_filter == 2) return n.type == NotifType.announcement;
          return true;
        }).toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Notifications')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    for (final (i, label) in ['All', 'Expenses', 'Announcements'].indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _filter == i,
                          onSelected: (_) => setState(() => _filter = i),
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: _filter == i ? Colors.white : AppColors.of(context).text,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          showCheckmark: false,
                          backgroundColor: AppColors.of(context).card,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(
                        icon: Icons.notifications_off_outlined,
                        message: 'Nothing here yet',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          for (final n in items)
                            AppCard(
                              onTap: () => _details(n),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: n.color.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(n.icon, color: n.color, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(n.title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700, fontSize: 14)),
                                        const SizedBox(height: 2),
                                        Text(n.subtitle,
                                            style: const TextStyle(
                                                color: AppColors.muted, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  if (_isNew(n))
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Icon(Icons.circle, size: 9, color: AppColors.primary),
                                    ),
                                  Text(timeAgo(n.createdAt),
                                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
