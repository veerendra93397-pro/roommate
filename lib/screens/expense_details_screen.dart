import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_expense_screen.dart';

/// Opens an existing expense and saves edits to the split.
Future<void> openExpense(BuildContext context, Expense e) async {
  final result = await Navigator.push<Expense>(
    context,
    MaterialPageRoute(builder: (_) => ExpenseDetailsScreen(expense: e)),
  );
  if (result != null && context.mounted) {
    guard(context, appState.updateExpense(result));
  }
}

/// Expense details + "who shares?" split editor.
/// [draft] = true when called from Add Expense (custom split); the screen pops the Expense.
class ExpenseDetailsScreen extends StatefulWidget {
  final Expense expense;
  final bool draft;
  const ExpenseDetailsScreen({super.key, required this.expense, this.draft = false});

  @override
  State<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends State<ExpenseDetailsScreen> {
  late final double _total = widget.expense.amount;
  late final Future<Uint8List?> _billFuture = (widget.expense.hasBill && !widget.draft)
      ? appState.loadBill(widget.expense.id)
      : Future<Uint8List?>.value(null);
  late Set<String> _selected;
  late bool _custom;
  final Map<String, TextEditingController> _ctrl = {};

  @override
  void initState() {
    super.initState();
    _custom = widget.expense.isCustomSplit;
    _selected = widget.expense.shares.entries
        .where((e) => e.value > 0)
        .map((e) => e.key)
        .toSet();
    if (_selected.isEmpty) _selected = appState.names.toSet();
    for (final m in appState.members) {
      final v = widget.expense.shares[m.name] ?? 0;
      _ctrl[m.name] = TextEditingController(text: _num(v));
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _num(double v) =>
      (v - v.truncate()).abs() < 0.005 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  double _val(String n) => double.tryParse(_ctrl[n]!.text.trim()) ?? 0;

  void _recalc() {
    final shares =
        equalShares(_total, appState.names.where(_selected.contains).toList());
    for (final m in appState.members) {
      _ctrl[m.name]!.text = _num(shares[m.name] ?? 0);
    }
  }

  double get _assigned =>
      appState.names.where(_selected.contains).fold(0.0, (s, n) => s + _val(n));

  void _save() {
    if (_selected.isEmpty) {
      _toast('Select at least one person');
      return;
    }
    Map<String, double> shares;
    if (_custom) {
      if ((_assigned - _total).abs() > 0.01) {
        _toast('Amounts add up to ${rupee(_assigned)} – should be ${rupee(_total)}');
        return;
      }
      shares = {for (final n in _selected) n: _val(n)};
    } else {
      shares = equalShares(_total, appState.names.where(_selected.contains).toList());
    }
    Navigator.pop(context, widget.expense.copyWith(shares: shares, isCustomSplit: _custom));
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _edit() async {
    final edited = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddExpenseScreen(editing: widget.expense)),
    );
    // The details shown here are now out of date, so go back to the list.
    if (edited == true && mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
          '"${widget.expense.title}" (${rupee(widget.expense.amount)}) will be removed for everyone in the room.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    guard(context, appState.deleteExpense(widget.expense));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    final n = _selected.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.draft ? 'Split Details' : 'Expense Details'),
        actions: widget.draft
            ? null
            : [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _edit,
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
                  onPressed: _delete,
                ),
              ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: e.category.color.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(e.category.icon, color: e.category.color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(rupee(e.amount),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
                      Text('Paid by ${e.paidBy} • ${fmtDate(e.date)}, ${e.date.year}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!widget.draft && e.hasBill) ...[
            const SizedBox(height: 14),
            FutureBuilder<Uint8List?>(
              future: _billFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final bytes = snap.data;
                if (bytes == null) {
                  return const Text('The bill photo could not be loaded.',
                      style: TextStyle(color: AppColors.muted));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bill photo', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => showBillViewer(context, bytes),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          bytes,
                          height: 190,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Tap to zoom',
                          style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          const Text('Split Type', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentToggle(
            options: const ['Equal', 'Custom Split'],
            selected: _custom ? 1 : 0,
            onChanged: (i) => setState(() {
              _custom = i == 1;
              _recalc();
            }),
          ),
          const SizedBox(height: 16),
          const Text('Who shares?', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              children: [
                for (final m in appState.members)
                  Row(
                    children: [
                      Checkbox(
                        value: _selected.contains(m.name),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(m.name);
                          } else {
                            _selected.remove(m.name);
                          }
                          _recalc();
                        }),
                      ),
                      Avatar(name: m.name, color: m.color, size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          m.name == appState.userName ? '${m.name} (You)' : m.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(
                        width: 96,
                        child: _custom && _selected.contains(m.name)
                            ? TextField(
                                controller: _ctrl[m.name],
                                textAlign: TextAlign.right,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  prefixText: '₹',
                                  isDense: true,
                                  contentPadding:
                                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                onChanged: (_) => setState(() {}),
                              )
                            : Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Text(
                                  _selected.contains(m.name)
                                      ? rupee(_val(m.name))
                                      : '₹0',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _selected.contains(m.name)
                                        ? AppColors.of(context).text
                                        : AppColors.muted,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.of(context).tint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: _custom
                ? Row(
                    children: [
                      const Expanded(
                        child: Text('Assigned so far',
                            style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        '${rupee(_assigned)} / ${rupee(_total)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: (_assigned - _total).abs() < 0.01
                              ? AppColors.green
                              : AppColors.red,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const Expanded(
                        child: Text("Each person's share",
                            style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        n == 0 ? '₹0' : rupee(_total / n),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.primary),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: widget.draft ? 'Done' : 'Save', onPressed: _save),
          if (!widget.draft) ...[
            const SizedBox(height: 22),
            _CommentsSection(expense: widget.expense),
          ],
        ],
      ),
    );
  }
}


/// Roommates can discuss an expense ("who bought this?", "wrong amount") here.
class _CommentsSection extends StatefulWidget {
  final Expense expense;
  const _CommentsSection({required this.expense});

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final _ctrl = TextEditingController();
  late final Stream<List<Comment>> _stream = extras.commentsOf(widget.expense.id);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    guard(context, extras.addComment(widget.expense, t));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Comments', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        StreamBuilder<List<Comment>>(
          stream: _stream,
          builder: (context, snap) {
            final list = snap.data ?? const <Comment>[];
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No comments yet.', style: TextStyle(color: AppColors.muted)),
              );
            }
            return Column(
              children: [
                for (final c in list)
                  AppCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Avatar(
                            name: c.authorName,
                            color: appState.member(c.authorName).color,
                            size: 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${c.authorName} • ${timeAgo(c.createdAt)}',
                                  style: const TextStyle(
                                      color: AppColors.muted, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(c.text),
                            ],
                          ),
                        ),
                        if (c.authorId == appState.uid || appState.isOwner)
                          IconButton(
                            iconSize: 18,
                            icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                            onPressed: () =>
                                guard(context, extras.deleteComment(widget.expense, c)),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(hintText: 'Write a comment...'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _send, icon: const Icon(Icons.send_rounded)),
          ],
        ),
      ],
    );
  }
}
