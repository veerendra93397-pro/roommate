import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_expense_screen.dart';
import 'expense_details_screen.dart';
import 'monthly_report_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _search = TextEditingController();
  String _query = '';
  Category? _category; // null = all

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final list = appState.expenses.where((e) {
          if (_category != null && e.category != _category) return false;
          if (_query.isEmpty) return true;
          return e.title.toLowerCase().contains(_query) ||
              e.paidBy.toLowerCase().contains(_query) ||
              e.category.label.toLowerCase().contains(_query);
        }).toList();
        final filtering = _query.isNotEmpty || _category != null;
        final total = list.fold<double>(0, (s, e) => s + e.amount);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Expenses'),
            actions: [
              IconButton(
                tooltip: 'Monthly report',
                icon: const Icon(Icons.bar_chart_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MonthlyReportScreen()),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add Expense'),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search by name, person or category',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _chip('All', _category == null, () => setState(() => _category = null)),
                    for (final c in Category.values)
                      _chip(c.shortLabel, _category == c, () => setState(() => _category = c)),
                  ],
                ),
              ),
              if (filtering)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        '${list.length} ${list.length == 1 ? 'expense' : 'expenses'}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                      const Spacer(),
                      Text('Total ${rupee(total)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_long_rounded,
                        message: filtering ? 'No expenses match your search' : 'No expenses yet',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                        children: [
                          for (final e in list)
                            ExpenseTile(expense: e, onTap: () => openExpense(context, e)),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.of(context).card,
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.of(context).text,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
