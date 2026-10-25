import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../services/export_service.dart';
import '../theme.dart';
import '../widgets.dart';

/// Pick a month and share the report as PDF or Excel.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _busy = false;

  void _shift(int d) => setState(() => _month = DateTime(_month.year, _month.month + d));

  bool get _isCurrent {
    final n = DateTime.now();
    return _month.year == n.year && _month.month == n.month;
  }

  Future<void> _run(Future<void> Function(DateTime) job) async {
    setState(() => _busy = true);
    try {
      await job(_month);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create the file: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ex = appState.expenses
        .where((e) => e.date.year == _month.year && e.date.month == _month.month)
        .toList();
    final total = ex.fold(0.0, (s, e) => s + e.amount);
    return Scaffold(
      appBar: AppBar(title: const Text('Export Report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: Text(monthYear(_month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _isCurrent ? null : () => _shift(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total spent',
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      Text(rupee(total),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
                    ],
                  ),
                ),
                Text('${ex.length} expenses',
                    style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'The report has: who paid and who owes, every expense, payments between roommates, and current balances.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: _busy ? 'Please wait...' : 'Share as PDF',
            icon: Icons.picture_as_pdf_rounded,
            onPressed: _busy ? null : () => _run(ExportService.sharePdf),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: _busy ? 'Please wait...' : 'Share as Excel',
            icon: Icons.table_chart_rounded,
            outlined: true,
            onPressed: _busy ? null : () => _run(ExportService.shareExcel),
          ),
        ],
      ),
    );
  }
}
