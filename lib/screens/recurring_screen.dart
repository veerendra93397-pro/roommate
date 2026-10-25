import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Monthly expenses (rent, wifi...) that are added automatically each month.
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final title = TextEditingController();
    final amount = TextEditingController();
    final day = TextEditingController(text: '1');
    Category cat = Category.rent;
    String paidBy = appState.userName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('New monthly expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(hintText: 'Title (e.g. House rent)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: 'Amount', prefixText: '₹'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: day,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Day of month (1-28)',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<Category>(
                  value: cat,
                  items: [
                    for (final c in Category.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (v) => setS(() => cat = v ?? cat),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: paidBy,
                  decoration: const InputDecoration(labelText: 'Paid by'),
                  items: [
                    for (final n in appState.names) DropdownMenuItem(value: n, child: Text(n)),
                  ],
                  onChanged: (v) => setS(() => paidBy = v ?? paidBy),
                ),
                const SizedBox(height: 8),
                const Text('Split equally between everyone in the room.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final t = title.text.trim();
    final a = double.tryParse(amount.text.trim());
    final d = int.tryParse(day.text.trim());
    if (ok != true || !context.mounted) return;
    if (t.isEmpty || a == null || a <= 0 || d == null || d < 1 || d > 28) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a title, an amount and a day between 1 and 28')),
      );
      return;
    }
    guard(
      context,
      extras.addRecurring(title: t, category: cat, amount: a, paidBy: paidBy, day: d),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appState, extras]),
      builder: (context, _) {
        final list = extras.recurring;
        return Scaffold(
          appBar: AppBar(title: const Text('Monthly Expenses')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
          body: list.isEmpty
              ? const EmptyState(
                  icon: Icons.event_repeat_rounded,
                  message: 'No monthly expenses yet.\nAdd rent, wifi, etc. once and\nit is added every month.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Added automatically on the chosen day, the first time anyone opens the app on or after that day.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ),
                    for (final r in list)
                      AppCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: r.category.color.withOpacity(0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(r.category.icon, color: r.category.color, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.title,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(
                                    '${rupee(r.amount)} • day ${r.day} • paid by ${r.paidBy}',
                                    style: const TextStyle(
                                        color: AppColors.muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: r.active,
                              onChanged: (v) => guard(context, extras.setRecurringActive(r, v)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: AppColors.muted),
                              onPressed: () => guard(context, extras.deleteRecurring(r)),
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

/// Owner sets the monthly budget (0 turns it off).
Future<void> editBudget(BuildContext context) async {
  final ctrl = TextEditingController(
    text: extras.monthlyBudget > 0 ? extras.monthlyBudget.toStringAsFixed(0) : '',
  );
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Monthly budget'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: 'Amount', prefixText: '₹'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Everyone is alerted when spending reaches 80% and 100%. Leave empty or 0 to turn off.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  final v = double.tryParse(ctrl.text.trim()) ?? 0;
  if (ok == true && context.mounted) {
    guard(context, extras.setBudget(v < 0 ? 0 : v));
  }
}
