import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'qr_scan_screen.dart';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  Future<void> _confirmRemove(BuildContext context, Member m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.name}?'),
        content: Text(
          '${m.name} will lose access to this room. Their past expenses stay in the '
          'history. They can ask to join again with the room code.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      guard(context, appState.removeMember(m));
    }
  }

  Future<void> _confirmTransfer(BuildContext context, Member m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Make room owner?'),
        content: Text(
          '${m.name} will become the room owner and will be able to accept new '
          'members. You will become a normal member.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Make owner'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      guard(context, appState.transferOwnership(m));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text('Members (${appState.members.length})')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Invite with room code',
                              style: TextStyle(color: AppColors.muted, fontSize: 12)),
                          Text(appState.roomCode,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: 2)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Show QR code',
                      onPressed: () => showRoomQr(context),
                      icon: const Icon(Icons.qr_code_2_rounded, color: AppColors.primary),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: appState.roomCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Room code copied')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ),
              if (appState.isOwner && appState.joinRequests.isNotEmpty) ...[
                const SectionHeader(title: 'Join requests'),
                for (final r in appState.joinRequests)
                  AppCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                    child: Row(
                      children: [
                        Avatar(name: r.name, color: AppColors.orange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              const Text('wants to join your room',
                                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Decline',
                          icon: const Icon(Icons.close_rounded, color: AppColors.red),
                          onPressed: () => guard(context, appState.rejectRequest(r)),
                        ),
                        IconButton(
                          tooltip: 'Accept',
                          icon: const Icon(Icons.check_circle_rounded, color: AppColors.green),
                          onPressed: () => guard(context, appState.approveRequest(r)),
                        ),
                      ],
                    ),
                  ),
                const SectionHeader(title: 'Members'),
              ] else
                const SizedBox(height: 14),
              for (final m in appState.members)
                Builder(builder: (context) {
                  final b = appState.balanceOf(m.name);
                  return AppCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Avatar(name: m.name, color: m.color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.name == appState.userName ? '${m.name} (You)' : m.name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (m.uid == appState.ownerId)
                                const Text('Room owner',
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Text(
                          b.abs() < 0.005 ? 'Settled' : '${b > 0 ? '+' : '-'} ${rupee(b.abs())}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: b.abs() < 0.005
                                ? AppColors.muted
                                : (b > 0 ? AppColors.green : AppColors.red),
                          ),
                        ),
                        if (appState.isOwner && m.uid != appState.uid)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, color: AppColors.muted),
                            onSelected: (v) => v == 'owner'
                                ? _confirmTransfer(context, m)
                                : _confirmRemove(context, m),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'owner', child: Text('Make room owner')),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove from room',
                                    style: TextStyle(color: AppColors.red)),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
