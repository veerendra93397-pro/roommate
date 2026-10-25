import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Every payment that was marked as paid in "Settle Up", newest first.
class PaymentHistoryScreen extends StatelessWidget {
  const PaymentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final list = appState.settlements.reversed.toList();
        final total = list.fold<double>(0, (s, p) => s + p.amount);
        return Scaffold(
          appBar: AppBar(title: const Text('Payment History')),
          body: list.isEmpty
              ? const EmptyState(
                  icon: Icons.payments_outlined,
                  message: 'No payments recorded yet',
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: AppColors.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${list.length} ${list.length == 1 ? 'payment' : 'payments'} settled',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(rupee(total),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final p in list)
                      AppCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            Avatar(name: p.from, color: appState.member(p.from).color, size: 36),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(Icons.arrow_forward_rounded,
                                  size: 16, color: AppColors.muted),
                            ),
                            Avatar(name: p.to, color: appState.member(p.to).color, size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${p.from} paid ${p.to}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600, fontSize: 13)),
                                  Text('${fmtDate(p.date)}, ${p.date.year}',
                                      style: const TextStyle(
                                          color: AppColors.muted, fontSize: 11)),
                                ],
                              ),
                            ),
                            Text(rupee(p.amount),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, color: AppColors.green)),
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
