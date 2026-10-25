import 'package:flutter/material.dart' hide Text;

import '../models.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets.dart';

/// Shown to someone who entered a room code and is waiting for the owner to accept.
/// When the owner approves, AuthGate moves them into the room automatically.
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final room = appState.pendingRoomName.isEmpty ? 'this room' : '"${appState.pendingRoomName}"';
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.of(context).tint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.hourglass_top_rounded,
                        size: 46, color: AppColors.primary),
                  ),
                  const SizedBox(height: 22),
                  const Text('Waiting for approval',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(
                    'Your request to join $room has been sent.\n'
                    'The room owner needs to accept it. You will enter the room '
                    'automatically as soon as they do.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                  const SizedBox(height: 30),
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 34),
                  PrimaryButton(
                    label: 'Cancel Request',
                    outlined: true,
                    onPressed: () => guard(context, appState.cancelJoinRequest()),
                  ),
                  TextButton(
                    onPressed: authService.logout,
                    child: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
