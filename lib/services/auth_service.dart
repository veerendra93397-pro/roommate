import 'package:firebase_auth/firebase_auth.dart';

import '../models.dart';
import 'push_service.dart';

/// All Firebase Authentication calls live here, so screens never touch Firebase directly.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// True while register() is running, so the app does not start loading data
  /// before the display name has been saved.
  bool registering = false;

  Stream<User?> get authChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    registering = true;
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      await cred.user?.reload();
    } finally {
      registering = false;
      final u = _auth.currentUser;
      if (u != null) appState.onSignedIn(u);
    }
  }

  Future<void> login({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  Future<void> logout() async {
    final u = _auth.currentUser;
    if (u != null) await pushService.stop(u.uid); // stop alerts for this phone
    await _auth.signOut();
  }

  /// Turns a Firebase error into a message a user can understand.
  static String messageFor(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'That email address is not valid.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Wrong email or password.';
        case 'email-already-in-use':
          return 'An account already exists with this email.';
        case 'weak-password':
          return 'Password is too weak (use at least 6 characters).';
        case 'network-request-failed':
          return 'No internet connection.';
        case 'too-many-requests':
          return 'Too many attempts. Try again later.';
        case 'operation-not-allowed':
          return 'Email/Password sign-in is not enabled in Firebase Console.';
        default:
          return e.message ?? 'Authentication failed (${e.code}).';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}

final AuthService authService = AuthService();
