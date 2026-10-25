import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets.dart';

/// Shown to signed-in users who are not in a room yet.
/// When create/join succeeds, AuthGate switches to the Home screen by itself.
class CreateJoinRoomScreen extends StatefulWidget {
  const CreateJoinRoomScreen({super.key});

  @override
  State<CreateJoinRoomScreen> createState() => _CreateJoinRoomScreenState();
}

class _CreateJoinRoomScreenState extends State<CreateJoinRoomScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // e.g. "The room owner declined your request."
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final msg = appState.joinMessage;
      if (msg != null && mounted) {
        appState.joinMessage = null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController(text: 'My Room');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create a new room'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Room name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _run(() => appState.createRoom(name));
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid room code')),
      );
      return;
    }
    await _run(() => appState.joinRoom(code));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create / Join Room'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _busy ? null : authService.logout,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _iconBox(Icons.add_home_rounded, AppColors.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Create a New Room',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          SizedBox(height: 2),
                          Text('Start a new room and invite your friends',
                              style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: _busy ? 'Please wait...' : 'Create Room',
                  icon: Icons.add,
                  onPressed: _busy ? null : _create,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _iconBox(Icons.meeting_room_rounded, AppColors.green),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Join a Room',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          SizedBox(height: 2),
                          Text('Enter the room code. The room owner must accept you.',
                              style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'Room Code'),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: _busy ? 'Please wait...' : 'Request to Join',
                  icon: Icons.login_rounded,
                  onPressed: _busy ? null : _join,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text('or', style: TextStyle(color: AppColors.muted)),
                  ),
                ),
                PrimaryButton(
                  label: 'Scan QR Code',
                  icon: Icons.qr_code_scanner_rounded,
                  outlined: true,
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('QR scanning needs a camera plugin (e.g. mobile_scanner) – add later.'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBox(IconData icon, Color color) => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      );
}
