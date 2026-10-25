import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'payment_history_screen.dart';

class WhoOwesWhomScreen extends StatefulWidget {
  const WhoOwesWhomScreen({super.key});

  @override
  State<WhoOwesWhomScreen> createState() => _WhoOwesWhomScreenState();
}

class _WhoOwesWhomScreenState extends State<WhoOwesWhomScreen> {
  int _tab = 0; // 0 simplified, 1 detailed

  /// Opens GPay/PhonePe/etc., then asks whether the payment went through.
  Future<void> _payUpi(BuildContext context, Debt d) async {
    final upi = appState.member(d.to).upi;
    final opened =
        await extras.payViaUpi(upiId: upi, payeeName: d.to, amount: d.amount);
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No UPI app found. Pay ${d.to} at $upi and tap Mark paid.')),
      );
      return;
    }
    final paid = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Did the payment go through?'),
        content: Text('Mark ${rupee(d.amount)} to ${d.to} as paid?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, paid')),
        ],
      ),
    );
    if (paid == true && context.mounted) {
      guard(context, appState.recordPayment(d.from, d.to, d.amount));
    }
  }

  void _settleUp() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final debts = appState.simplifiedDebts();
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Settle Up',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                const Text('Mark a payment as done once the money has been paid.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 14),
                if (debts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('🎉 Everyone is settled up!')),
                  )
                else
                  for (final d in debts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Avatar(name: d.from, color: appState.member(d.from).color),
                      title: Text('${d.from} → ${d.to}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      isThreeLine: d.from == appState.userName &&
                          appState.member(d.to).upi.isNotEmpty,
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rupee(d.amount)),
                          if (d.from == appState.userName &&
                              appState.member(d.to).upi.isNotEmpty)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _payUpi(context, d),
                              icon: const Icon(Icons.account_balance_wallet_rounded, size: 16),
                              label: const Text('Pay via UPI'),
                            ),
                        ],
                      ),
                      trailing: ElevatedButton(
                        onPressed: () =>
                            guard(context, appState.recordPayment(d.from, d.to, d.amount)),
                        child: const Text('Mark paid'),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final bal = appState.balanceOf(appState.userName);
        final color = bal >= 0 ? AppColors.green : AppColors.red;
        final debts = appState.simplifiedDebts();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Who Owes Whom'),
            actions: [
              IconButton(
                tooltip: 'Payment history',
                icon: const Icon(Icons.history_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Text('Total Balance',
                        style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(rupee(bal.abs()),
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: color)),
                    Text(
                      bal.abs() < 0.005
                          ? '(All settled)'
                          : bal > 0
                              ? '(You are owed)'
                              : '(You owe)',
                      style: TextStyle(color: color, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SegmentToggle(
                options: const ['Simplified', 'Detailed'],
                selected: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 14),
              if (_tab == 0)
                for (final m in appState.members) _memberRow(m)
              else if (debts.isEmpty)
                const EmptyState(icon: Icons.check_circle_outline_rounded, message: 'Nothing to settle')
              else
                for (final d in debts) _debtRow(d),
              const SizedBox(height: 14),
              PrimaryButton(label: 'Settle Up', onPressed: _settleUp),
            ],
          ),
        );
      },
    );
  }

  Widget _memberRow(Member m) {
    final b = appState.balanceOf(m.name);
    final color = b >= 0 ? AppColors.green : AppColors.red;
    final settled = b.abs() < 0.005;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Avatar(name: m.name, color: m.color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              m.name == appState.userName ? '${m.name} (You)' : m.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                settled ? '₹0' : '${b > 0 ? '+' : '-'} ${rupee(b.abs())}',
                style: TextStyle(fontWeight: FontWeight.w800, color: settled ? AppColors.muted : color),
              ),
              Text(
                settled ? 'Settled' : (b > 0 ? '(To receive)' : '(To pay)'),
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _debtRow(Debt d) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Avatar(name: d.from, color: appState.member(d.from).color, size: 36),
          const SizedBox(width: 10),
          const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Avatar(name: d.to, color: appState.member(d.to).color, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${d.from} owes ${d.to}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Text(rupee(d.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
