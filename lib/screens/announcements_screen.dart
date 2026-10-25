import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  /// Bottom sheet used both to post a new announcement and to edit one.
  void _compose(BuildContext context, {Announcement? editing}) {
    final title = TextEditingController(text: editing?.title ?? '');
    final body = TextEditingController(text: editing?.body ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(editing == null ? 'New Announcement' : 'Edit Announcement',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 14),
            TextField(controller: title, decoration: const InputDecoration(hintText: 'Title')),
            const SizedBox(height: 10),
            TextField(
              controller: body,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Message to your roommates'),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: editing == null ? 'Post' : 'Save',
              icon: editing == null ? Icons.send_rounded : Icons.check_rounded,
              onPressed: () {
                if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Add a title and a message')),
                  );
                  return;
                }
                final t = title.text.trim();
                final b = body.text.trim();
                guard(
                  ctx,
                  editing == null
                      ? appState.addAnnouncement(t, b)
                      : appState.editAnnouncement(editing.id, t, b),
                );
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Announcement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: Text('"${a.title}" will be removed for everyone in the room.'),
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
    if (ok == true && context.mounted) {
      guard(context, appState.deleteAnnouncement(a.id));
    }
  }

  /// Full announcement (all the text, who posted it and when).
  void _details(BuildContext context, Announcement a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: a.color.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(a.icon, color: a.color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(a.title,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Posted by ${a.author} • ${fmtFull(a.createdAt)}${a.edited ? ' • edited' : ''}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(a.body, style: const TextStyle(fontSize: 15, height: 1.45)),
                  ),
                ),
                if (appState.canManage(a)) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _compose(context, editing: a);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.red,
                            side: const BorderSide(color: AppColors.red),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _confirmDelete(context, a);
                          },
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Announcements'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton.filled(
                  onPressed: () => _compose(context),
                  icon: const Icon(Icons.add),
                  tooltip: 'New announcement',
                ),
              ),
            ],
          ),
          body: appState.announcements.isEmpty
              ? const EmptyState(icon: Icons.campaign_rounded, message: 'No announcements yet')
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final a in appState.announcements)
                      AppCard(
                        onTap: () => _details(context, a),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: a.color.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(a.icon, color: a.color, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text(a.body,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, height: 1.35)),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${a.author} • ${timeAgo(a.createdAt)}${a.edited ? ' • edited' : ''}',
                                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (appState.canManage(a))
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded, color: AppColors.muted),
                                onSelected: (v) {
                                  if (v == 'edit') _compose(context, editing: a);
                                  if (v == 'delete') _confirmDelete(context, a);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              )
                            else
                              const SizedBox(width: 10),
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
