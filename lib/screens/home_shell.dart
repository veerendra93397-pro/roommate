import 'package:flutter/material.dart' hide Text;

import '../l10n.dart';
import '../models.dart';
import 'chat_screen.dart';
import 'expenses_screen.dart';
import 'home_dashboard.dart';
import 'profile_screen.dart';
import 'who_owes_whom_screen.dart';
import '../widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _chatTab = 2;
  static const _balanceTab = 3;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeDashboard(onNavigate: (i) => setState(() => _index = i == 2 ? _balanceTab : i)),
      const ExpensesScreen(),
      ChatScreen(active: _index == _chatTab),
      const WhoOwesWhomScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: ListenableBuilder(
        listenable: Listenable.merge([extras, language]),
        builder: (context, _) {
          final unread = extras.chatUnread;
          return BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            items: [
              BottomNavigationBarItem(icon: const Icon(Icons.home_rounded), label: tr('Home')),
              BottomNavigationBarItem(
                  icon: const Icon(Icons.receipt_long_rounded), label: tr('Expenses')),
              BottomNavigationBarItem(
                icon: Badge(
                  isLabelVisible: unread > 0 && _index != _chatTab,
                  label: Text(unread > 9 ? '9+' : '$unread'),
                  child: const Icon(Icons.chat_bubble_rounded),
                ),
                label: tr('Chat'),
              ),
              BottomNavigationBarItem(icon: const Icon(Icons.pie_chart_rounded), label: tr('Balance')),
              BottomNavigationBarItem(icon: const Icon(Icons.menu_rounded), label: tr('More')),
            ],
          );
        },
      ),
    );
  }
}
