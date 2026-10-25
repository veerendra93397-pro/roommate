import 'dart:math';

import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'export_screen.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final list = appState.expenses
            .where((e) => e.date.year == _month.year && e.date.month == _month.month)
            .toList();
        final total = list.fold<double>(0, (s, e) => s + e.amount);

        final byCategory = <Category, double>{};
        for (final e in list) {
          byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
        }
        final cats = Category.values.where((c) => (byCategory[c] ?? 0) > 0).toList();

        final byPerson = <String, double>{
          for (final m in appState.members) m.name: 0,
        };
        for (final e in list) {
          byPerson[e.paidBy] = (byPerson[e.paidBy] ?? 0) + e.amount;
        }
        final maxPaid = byPerson.values.fold<double>(0, max);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Monthly Report'),
            actions: [
              IconButton(
                tooltip: 'Export PDF / Excel',
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExportScreen()),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(monthYear(_month),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  IconButton(
                    onPressed: () => _shift(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: EmptyState(
                    icon: Icons.insert_chart_outlined_rounded,
                    message: 'No expenses in this month',
                  ),
                )
              else ...[
                AppCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 180,
                        height: 180,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(180, 180),
                              painter: _DonutPainter(
                                values: [for (final c in cats) byCategory[c]!],
                                colors: [for (final c in cats) c.color],
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Total Expenses',
                                    style: TextStyle(color: AppColors.muted, fontSize: 11)),
                                Text(rupee(total),
                                    style: const TextStyle(
                                        fontSize: 22, fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      for (final c in cats)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(c.label,
                                    style: const TextStyle(fontWeight: FontWeight.w500)),
                              ),
                              Text('${(byCategory[c]! / total * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                              SizedBox(
                                width: 80,
                                child: Text(rupee(byCategory[c]!),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SectionHeader(title: 'Friend-wise spending (paid)'),
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (final m in appState.members)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            children: [
                              Avatar(name: m.name, color: m.color, size: 30),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 70,
                                child: Text(m.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: maxPaid == 0 ? 0 : byPerson[m.name]! / maxPaid,
                                    minHeight: 10,
                                    color: m.color,
                                    backgroundColor: AppColors.of(context).border,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 72,
                                child: Text(rupee(byPerson[m.name]!),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  _DonutPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return;
    const stroke = 26.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    var start = -pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * pi;
      paint.color = colors[i];
      canvas.drawArc(rect, start, max(0, sweep - 0.03), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.values != values || old.colors != colors;
}
