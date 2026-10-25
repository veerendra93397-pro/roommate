import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_expense_screen.dart';
import 'announcements_screen.dart';
import 'chores_screen.dart';
import 'expense_details_screen.dart';
import 'members_screen.dart';
import 'notifications_screen.dart';
import 'recurring_screen.dart';

class HomeDashboard extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  const HomeDashboard({super.key, required this.onNavigate});

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final bal = appState.balanceOf(appState.userName);
        final balColor = bal >= 0 ? AppColors.green : AppColors.red;
        final balLabel = bal.abs() < 0.005
            ? '(All settled)'
            : bal > 0
                ? '(You are owed)'
                : '(You owe)';

        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.home_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(appState.roomName,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          Text('${appState.members.length} Members',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: appState.roomCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Room code ${appState.roomCode} copied')),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.of(context).tint,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(appState.roomCode,
                                style: const TextStyle(
                                    color: AppColors.primary, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 4),
                            const Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _push(context, const NotificationsScreen()),
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.notifications_none_rounded, size: 26),
                          if (appState.unreadCount > 0)
                            Positioned(
                              right: -6,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.red,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  appState.unreadCount > 9 ? '9+' : '${appState.unreadCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (appState.isOwner && appState.joinRequests.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  AppCard(
                    onTap: () => _push(context, const MembersScreen()),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.person_add_alt_1_rounded, color: AppColors.orange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            appState.joinRequests.length == 1
                                ? '${appState.joinRequests.first.name} wants to join your room'
                                : '${appState.joinRequests.length} people want to join your room',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Text('Review',
                            style: TextStyle(
                                color: AppColors.primary, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),

                // Members
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final m in appState.members)
                      Column(
                        children: [
                          Avatar(name: m.name, color: m.color, size: 48),
                          const SizedBox(height: 6),
                          Text(m.name,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          if (m.name == appState.userName)
                            const Text('(You)',
                                style: TextStyle(fontSize: 10, color: AppColors.muted)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 18),

                // Balance card
                AppCard(
                  padding: const EdgeInsets.all(18),
                  onTap: () => onNavigate(2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Balance',
                                style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(rupee(bal.abs()),
                                style: TextStyle(
                                    fontSize: 30, fontWeight: FontWeight.w800, color: balColor)),
                          ],
                        ),
                      ),
                      Text(balLabel,
                          style: TextStyle(color: balColor, fontWeight: FontWeight.w600)),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _budgetCard(context),

                // Quick actions
                Row(
                  children: [
                    _action(context, Icons.add_card_rounded, 'Add Expense', AppColors.green,
                        () => _push(context, const AddExpenseScreen())),
                    const SizedBox(width: 10),
                    _action(context, Icons.campaign_rounded, 'Announcements', AppColors.primary,
                        () => _push(context, const AnnouncementsScreen())),
                    const SizedBox(width: 10),
                    _action(context, Icons.groups_rounded, 'Members', AppColors.purple,
                        () => _push(context, const MembersScreen())),
                    const SizedBox(width: 10),
                    _action(context, Icons.checklist_rounded, 'Chores & List', AppColors.orange,
                        () => _push(context, const ChoresScreen())),
                  ],
                ),

                SectionHeader(
                  title: 'Recent Expenses',
                  action: 'View All',
                  onAction: () => onNavigate(1),
                ),
                if (appState.expenses.isEmpty)
                  const EmptyState(icon: Icons.receipt_long_rounded, message: 'No expenses yet')
                else
                  for (final e in appState.expenses.take(4))
                    ExpenseTile(expense: e, onTap: () => openExpense(context, e)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _budgetCard(BuildContext context) {
    final budget = appState.monthlyBudget;
    if (budget <= 0) {
      if (!appState.isOwner) return const SizedBox(height: 14);
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AppCard(
          onTap: () => editBudget(context),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: const Row(
            children: [
              Icon(Icons.savings_outlined, color: AppColors.primary),
              SizedBox(width: 12),
              Expanded(child: Text('Set a monthly budget for the room')),
              Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      );
    }
    final spent = extras.monthTotal();
    final ratio = spent / budget;
    final color = ratio >= 1
        ? AppColors.red
        : ratio >= 0.8
            ? AppColors.orange
            : AppColors.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        onTap: appState.isOwner ? () => editBudget(context) : null,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('This month\'s budget',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text('${rupee(spent)} / ${rupee(budget)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 8,
                color: color,
                backgroundColor: AppColors.of(context).border,
              ),
            ),
            if (ratio >= 1)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Over budget!',
                    style: TextStyle(color: AppColors.red, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _action(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
