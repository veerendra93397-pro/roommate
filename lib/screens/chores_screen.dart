import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Two tabs: Chores (who does what) and the shared Shopping list.
class ChoresScreen extends StatelessWidget {
  const ChoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chores & Shopping'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Chores'), Tab(text: 'Shopping list')],
          ),
        ),
        body: const TabBarView(children: [_ChoresTab(), _ShoppingTab()]),
      ),
    );
  }
}

// ───────────────────────── Chores ─────────────────────────

class _ChoresTab extends StatelessWidget {
  const _ChoresTab();

  Future<void> _add(BuildContext context) async {
    final title = TextEditingController();
    String who = appState.userName;
    bool rotate = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('New chore'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'e.g. Clean kitchen'),
                ),
                const SizedBox(height: 14),
                const Text('Assigned to', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: who,
                  items: [
                    for (final n in appState.names) DropdownMenuItem(value: n, child: Text(n)),
                  ],
                  onChanged: (v) => setS(() => who = v ?? who),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rotate'),
                  subtitle: const Text('After it is done, pass it to the next person'),
                  value: rotate,
                  onChanged: (v) => setS(() => rotate = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    final text = title.text.trim();
    if (ok == true && text.isNotEmpty && context.mounted) {
      guard(context, extras.addChore(text, who, rotate));
    }
  }

  Future<void> _reassign(BuildContext context, Chore c) async {
    final name = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Assign to', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            for (final m in appState.members)
              ListTile(
                leading: Avatar(name: m.name, color: m.color, size: 34),
                title: Text(m.name),
                onTap: () => Navigator.pop(ctx, m.name),
              ),
          ],
        ),
      ),
    );
    if (name != null && context.mounted) guard(context, extras.assignChore(c, name));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appState, extras]),
      builder: (context, _) {
        final list = extras.chores;
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
            label: const Text('Add chore'),
          ),
          body: list.isEmpty
              ? const EmptyState(icon: Icons.cleaning_services_rounded, message: 'No chores yet')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  children: [
                    for (final c in list)
                      AppCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                        child: Row(
                          children: [
                            Checkbox(
                              value: c.done,
                              onChanged: (_) => guard(context, extras.toggleChore(c)),
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () => _reassign(context, c),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          decoration: c.done ? TextDecoration.lineThrough : null,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Assigned to ${c.assignedTo}'
                                        '${c.rotate ? ' • rotates' : ''}'
                                        '${c.lastDoneBy.isNotEmpty ? ' • last done by ${c.lastDoneBy}' : ''}',
                                        style: const TextStyle(
                                            color: AppColors.muted, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: AppColors.muted),
                              onPressed: () => guard(context, extras.deleteChore(c)),
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

// ───────────────────────── Shopping ─────────────────────────

class _ShoppingTab extends StatefulWidget {
  const _ShoppingTab();

  @override
  State<_ShoppingTab> createState() => _ShoppingTabState();
}

class _ShoppingTabState extends State<_ShoppingTab> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    guard(context, extras.addItem(t));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appState, extras]),
      builder: (context, _) {
        final items = extras.shopping;
        final bought = items.where((i) => i.bought).length;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _add(),
                      decoration: const InputDecoration(hintText: 'Add item (milk, rice...)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
                ],
              ),
            ),
            if (bought > 0)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => guard(context, extras.clearBought()),
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: Text('Clear $bought bought'),
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(
                      icon: Icons.shopping_cart_outlined, message: 'Shopping list is empty')
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        for (final i in items)
                          AppCard(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: ListTile(
                              dense: true,
                              leading: Checkbox(
                                value: i.bought,
                                onChanged: (_) => guard(context, extras.toggleItem(i)),
                              ),
                              title: Text(
                                i.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  decoration: i.bought ? TextDecoration.lineThrough : null,
                                  color: i.bought ? AppColors.muted : AppColors.of(context).text,
                                ),
                              ),
                              subtitle: Text(
                                i.bought ? 'Bought by ${i.boughtBy}' : 'Added by ${i.addedBy}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () => guard(context, extras.deleteItem(i)),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
