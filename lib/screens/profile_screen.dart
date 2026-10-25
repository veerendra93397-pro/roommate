import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'edit_profile_screen.dart';
import 'chores_screen.dart';
import 'expenses_screen.dart';
import 'export_screen.dart';
import 'recurring_screen.dart';
import '../services/app_lock.dart';
import '../services/auth_service.dart';
import 'members_screen.dart';
import 'monthly_report_screen.dart';
import 'payment_history_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _roomSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Room Settings',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.home_rounded),
              title: const Text('Room name'),
              subtitle: Text(appState.roomName),
              trailing: appState.isOwner
                  ? IconButton(
                      tooltip: 'Rename room',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _renameRoom(context);
                      },
                    )
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.vpn_key_rounded),
              title: const Text('Room code'),
              subtitle: Text(appState.roomCode),
              trailing: IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: appState.roomCode));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Room code copied')),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              label: 'Leave Room',
              outlined: true,
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).popUntil((r) => r.isFirst);
                guard(context, appState.leaveRoom());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameRoom(BuildContext context) async {
    final ctrl = TextEditingController(text: appState.roomName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename room'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Room name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      guard(context, appState.renameRoom(name));
    }
  }

  void _appLockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: appLock,
        builder: (ctx, _) => AlertDialog(
          title: const Text('App Lock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ask for fingerprint / PIN'),
                value: appLock.enabled,
                onChanged: (v) async {
                  final msg = await appLock.setEnabled(v);
                  if (msg != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                  }
                },
              ),
              const Text(
                'When on, RoomMate asks for your phone\'s fingerprint, face or PIN when you open it '
                'or come back after a short while. Only this phone is affected.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  void _languageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: language,
        builder: (ctx, _) => AlertDialog(
          title: const Text('Language'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final l in AppLang.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(language.lang == l
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
                  title: Text(l.nativeName),
                  onTap: () {
                    language.set(l);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _appearance(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: themeController,
        builder: (ctx, _) => AlertDialog(
          title: const Text('Appearance'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (mode, label) in [
                (ThemeMode.system, 'Same as phone'),
                (ThemeMode.light, 'Light'),
                (ThemeMode.dark, 'Dark'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(themeController.mode == mode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
                  title: Text(label),
                  onTap: () {
                    themeController.set(mode);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to login again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Back to the root route; AuthGate then shows Login once signed out.
              Navigator.of(context).popUntil((r) => r.isFirst);
              await authService.logout();
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: appState,
        builder: (context, _) => _content(context),
      );

  Widget _content(BuildContext context) {
    final me = appState.member(appState.userName);
    final items = <_MenuItem>[
      _MenuItem(Icons.settings_outlined, 'Room Settings', () => _roomSettings(context)),
      _MenuItem(Icons.groups_outlined, 'Members', () => _push(context, const MembersScreen())),
      _MenuItem(Icons.history_rounded, 'Expense History',
          () => _push(context, const ExpensesScreen())),
      _MenuItem(Icons.bar_chart_rounded, 'Monthly Reports',
          () => _push(context, const MonthlyReportScreen())),
      _MenuItem(Icons.checklist_rounded, 'Chores & Shopping List',
          () => _push(context, const ChoresScreen())),
      _MenuItem(Icons.event_repeat_rounded, 'Monthly Expenses',
          () => _push(context, const RecurringScreen())),
      if (appState.isOwner)
        _MenuItem(Icons.savings_outlined, 'Monthly Budget', () => editBudget(context)),
      _MenuItem(Icons.ios_share_rounded, 'Export Report (PDF / Excel)',
          () => _push(context, const ExportScreen())),
      _MenuItem(Icons.ios_share_rounded, 'Export Report (PDF / Excel)',
          () => _push(context, const ExportScreen())),
      _MenuItem(Icons.payments_outlined, 'Payment History',
          () => _push(context, const PaymentHistoryScreen())),
      _MenuItem(Icons.notifications_none_rounded, 'Notification Settings',
          () => _push(context, const NotificationSettingsScreen())),
      _MenuItem(Icons.dark_mode_outlined, 'Appearance', () => _appearance(context)),
      _MenuItem(Icons.language_rounded, 'Language', () => _languageDialog(context)),
      _MenuItem(Icons.lock_outline_rounded, 'App Lock', () => _appLockDialog(context)),
      _MenuItem(Icons.help_outline_rounded, 'Help & Support', () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Help & Support'),
            content: const Text('Need help? Contact support@roommate.app (placeholder).'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Avatar(name: me.name, color: AppColors.primary, size: 60),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appState.userName,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      Text(appState.userEmail,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.muted),
                  onPressed: () => _push(context, const EditProfileScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  ListTile(
                    leading: Icon(items[i].icon, color: AppColors.primary),
                    title: Text(items[i].label,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                    onTap: items[i].onTap,
                  ),
                  if (i != items.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppColors.red),
              title: const Text('Log Out',
                  style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
              onTap: () => _logout(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _MenuItem(this.icon, this.label, this.onTap);
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _expenses = true;
  bool _announcements = true;
  bool _payments = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('New expenses'),
                  value: _expenses,
                  onChanged: (v) => setState(() => _expenses = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Announcements'),
                  value: _announcements,
                  onChanged: (v) => setState(() => _announcements = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Payments & settlements'),
                  value: _payments,
                  onChanged: (v) => setState(() => _payments = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
