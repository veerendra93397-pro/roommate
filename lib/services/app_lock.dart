import 'package:flutter/material.dart' hide Text;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets.dart';

/// Locks the app behind the phone's own fingerprint / face / PIN / pattern.
/// The setting is saved on this phone only.
class AppLock extends ChangeNotifier {
  final LocalAuthentication _auth = LocalAuthentication();

  bool enabled = false;
  bool locked = false; // true = show the lock screen
  bool _prompting = false;
  DateTime? _leftAt;

  /// How long the app can stay in the background before it asks again.
  static const grace = Duration(seconds: 45);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled = p.getBool('appLock') ?? false;
    } catch (_) {}
    locked = enabled; // ask at app start
  }

  Future<bool> _authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  /// Shows the phone's lock prompt. Called by the lock screen.
  Future<void> unlock() async {
    if (_prompting || !locked) return;
    _prompting = true;
    final ok = await _authenticate('Unlock RoomMate');
    _prompting = false;
    if (ok) {
      locked = false;
      notifyListeners();
    }
  }

  /// Turns the lock on/off from settings. Returns an error message, or null if it worked.
  Future<String?> setEnabled(bool on) async {
    if (on) {
      bool supported = false;
      try {
        supported = await _auth.isDeviceSupported();
      } catch (_) {}
      if (!supported) {
        return 'Set a screen lock (PIN, pattern or fingerprint) in your phone settings first.';
      }
    }
    // always confirm with the phone's lock before changing the setting
    final ok = await _authenticate(on ? 'Turn on RoomMate lock' : 'Turn off RoomMate lock');
    if (!ok) return 'Could not confirm. The lock was not changed.';
    enabled = on;
    locked = false;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('appLock', on);
    } catch (_) {}
    notifyListeners();
    return null;
  }

  // app lifecycle (called by LockGate)
  void onBackground() {
    if (!_prompting) _leftAt = DateTime.now();
  }

  void onForeground() {
    if (!enabled || locked || _prompting) return;
    final left = _leftAt;
    _leftAt = null;
    if (left != null && DateTime.now().difference(left) > grace) {
      locked = true;
      notifyListeners();
    }
  }
}

final AppLock appLock = AppLock();

/// Wrap the whole app with this (MaterialApp.builder) to show the lock screen on top.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      appLock.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      appLock.onForeground();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appLock,
      builder: (context, _) {
        if (appLock.locked) {
          WidgetsBinding.instance.addPostFrameCallback((_) => appLock.unlock());
        }
        return Stack(
          children: [
            widget.child,
            if (appLock.locked)
              Positioned.fill(
                child: Material(
                  color: AppLockColors.bg,
                  child: SafeArea(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_rounded, size: 64, color: Colors.white),
                          const SizedBox(height: 16),
                          const Text('RoomMate is locked',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: appLock.unlock,
                            icon: const Icon(Icons.fingerprint_rounded),
                            label: const Text('Unlock'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class AppLockColors {
  static const bg = Color(0xFF0B1A3A);
}
