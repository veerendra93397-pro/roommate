import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Group chat for everyone in the room.
class ChatScreen extends StatefulWidget {
  /// true while the Chat tab is the one on screen (messages then count as read)
  final bool active;
  const ChatScreen({super.key, this.active = true});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    guard(context, extras.sendMessage(t));
  }

  Future<void> _delete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('It will be removed for everyone.'),
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
    if (ok == true && mounted) guard(context, extras.deleteMessage(m));
  }

  String _day(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today';
    final y = now.subtract(const Duration(days: 1));
    if (d.year == y.year && d.month == y.month && d.day == y.day) return 'Yesterday';
    return fmtDate(d);
  }

  String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appState, extras]),
      builder: (context, _) {
        final p = AppColors.of(context);
        if (widget.active && extras.chatUnread > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => extras.markChatSeen());
        }
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Text('Room Chat'),
                const SizedBox(width: 8),
                Text('${appState.members.length} members',
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: Builder(
                  builder: (context) {
                    final list = extras.messages; // newest first
                    if (list.isEmpty) {
                      return const EmptyState(
                        icon: Icons.chat_bubble_outline_rounded,
                        message: 'No messages yet.\nSay hi to your roommates!',
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final m = list[i];
                        final mine = m.authorId == appState.uid;
                        // list is newest-first, so the "previous" message in time is i + 1
                        final older = i + 1 < list.length ? list[i + 1] : null;
                        final newDay = older == null ||
                            older.createdAt.day != m.createdAt.day ||
                            older.createdAt.month != m.createdAt.month ||
                            older.createdAt.year != m.createdAt.year;
                        final sameAuthorAsOlder =
                            older != null && older.authorId == m.authorId && !newDay;
                        return Column(
                          children: [
                            if (newDay)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Text(_day(m.createdAt),
                                    style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ),
                            _bubble(context, m, mine, sameAuthorAsOlder, p),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: p.card,
                    border: Border(top: BorderSide(color: p.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Message',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide(color: p.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide(color: p.border),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        onPressed: _send,
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bubble(BuildContext context, ChatMessage m, bool mine, bool grouped, Palette p) {
    final canDelete = mine || appState.isOwner;
    final bubble = GestureDetector(
      onLongPress: canDelete ? () => _delete(m) : null,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : p.card,
          border: mine ? null : Border.all(color: p.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine && !grouped)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(m.authorName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: appState.member(m.authorName).color,
                    )),
              ),
            Text(m.text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.3,
                  color: mine ? Colors.white : p.text,
                )),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(_time(m.createdAt),
                  style: TextStyle(
                    fontSize: 10,
                    color: mine ? Colors.white70 : AppColors.muted,
                  )),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: grouped ? 2 : 8),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine)
            SizedBox(
              width: 32,
              child: grouped
                  ? null
                  : Avatar(
                      name: m.authorName,
                      color: appState.member(m.authorName).color,
                      size: 28,
                    ),
            ),
          if (!mine) const SizedBox(width: 6),
          bubble,
        ],
      ),
    );
  }
}
