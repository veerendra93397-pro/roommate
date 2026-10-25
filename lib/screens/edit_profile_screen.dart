import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name = TextEditingController(text: appState.userName);
  late final TextEditingController _upi =
      TextEditingController(text: appState.member(appState.userName).upi);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _upi.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    final text = _name.text.trim();
    if (text.isEmpty) {
      _toast('Name cannot be empty');
      return;
    }
    setState(() => _busy = true);
    try {
      await appState.updateProfileName(text);
      await extras.saveUpi(_upi.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated')));
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  final _picker = ImagePicker();

  Future<void> _photoSheet() async {
    final hasPhoto = appState.member(appState.userName).photo != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
                title: const Text('Remove photo',
                    style: TextStyle(color: AppColors.red)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;

    setState(() => _busy = true);
    try {
      if (choice == 'remove') {
        await appState.removeProfilePhoto();
      } else {
        final file = await _picker.pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 400,
          maxHeight: 400,
          imageQuality: 70,
        );
        if (file != null) {
          await appState.setProfilePhoto(await file.readAsBytes());
        }
      }
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    try {
      await authService.sendPasswordReset(appState.userEmail);
      if (mounted) _toast('Password reset email sent to ${appState.userEmail}');
    } catch (e) {
      if (mounted) _toast(AuthService.messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _busy ? null : _photoSheet,
              child: Stack(
                children: [
                  ListenableBuilder(
                    listenable: appState,
                    builder: (context, _) => Avatar(
                      name: appState.userName,
                      color: AppColors.primary,
                      size: 96,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('Tap to change photo',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
          const SizedBox(height: 24),
          const Text('Name', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Your name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your name is also updated on your past expenses and payments in this room.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          const Text('Email', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: TextEditingController(text: appState.userEmail),
            enabled: false,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 16),
          const Text('UPI ID (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _upi,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'name@bank',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Roommates who owe you can pay straight to this UPI ID from the Settle Up screen.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: _busy ? 'Saving...' : 'Save Changes',
            onPressed: _busy ? null : _save,
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Send Password Reset Email',
            icon: Icons.lock_reset_rounded,
            outlined: true,
            onPressed: _busy ? null : _resetPassword,
          ),
        ],
      ),
    );
  }
}
