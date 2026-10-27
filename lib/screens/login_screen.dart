import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets.dart';
import '../services/auth_service.dart';

/// Public GitHub release that holds the latest APK.
const _apkUrl =
    'https://github.com/veerendra93397-pro/roommate-download/releases/latest/download/RoomMate.apk';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _pass = TextEditingController();
  bool _isLogin = true;
  bool _hide = true;

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool _loading = false;

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_isLogin) {
        await authService.login(email: _id.text.trim(), password: _pass.text);
      } else {
        await authService.register(
          name: _name.text.trim(),
          email: _id.text.trim(),
          password: _pass.text,
        );
      }
      // AuthGate (main.dart) switches to the next screen automatically.
    } catch (e) {
      if (mounted) _toast(AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    final email = _id.text.trim();
    if (!email.contains('@')) {
      _toast('Type your email above first, then tap Forgot Password.');
      return;
    }
    try {
      await authService.sendPasswordReset(email);
      if (mounted) _toast('Password reset email sent to $email');
    } catch (e) {
      if (mounted) _toast(AuthService.messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1A3A),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: h * 0.34,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1E3A8A), Color(0xFF0B1A3A)],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.home_rounded, color: Colors.white, size: 38),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'RoomMate',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Split Expenses\nStay United\nLive Better',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              constraints: BoxConstraints(minHeight: h * 0.66),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: BoxDecoration(
                color: AppColors.of(context).bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isLogin ? 'Welcome back 👋' : 'Create your account',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLogin
                          ? 'Login to manage your room expenses'
                          : 'Register to start sharing expenses',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 22),
                    if (!_isLogin) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _id,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) =>
                      (v == null || !v.trim().contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _pass,
                      obscureText: _hide,
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                      validator: (v) =>
                      (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
                    ),
                    const SizedBox(height: 22),
                    PrimaryButton(
                      label: _loading ? 'Please wait...' : (_isLogin ? 'Login' : 'Register'),
                      onPressed: _loading ? null : _submit,
                    ),
                    if (_isLogin)
                      Center(
                        child: TextButton(
                          onPressed: _forgot,
                          child: const Text('Forgot Password?'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isLogin ? "Don't have an account? " : 'Already have an account? ',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _isLogin = !_isLogin),
                          child: Text(
                            _isLogin ? 'Sign Up' : 'Login',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (kIsWeb) ...[
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: 'Download Android App',
                        icon: Icons.download_rounded,
                        outlined: true,
                        onPressed: () => launchUrl(
                          Uri.parse(_apkUrl),
                          webOnlyWindowName: '_self',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:flutter/material.dart' hide Text;
// import 'package:url_launcher/url_launcher.dart';
//
// import '../theme.dart';
// import '../widgets.dart';
// import '../services/auth_service.dart';
//
// class LoginScreen extends StatefulWidget {
//   const LoginScreen({super.key});
//
//   @override
//   State<LoginScreen> createState() => _LoginScreenState();
// }
//
// class _LoginScreenState extends State<LoginScreen> {
//   final _form = GlobalKey<FormState>();
//   final _name = TextEditingController();
//   final _id = TextEditingController();
//   final _pass = TextEditingController();
//   bool _isLogin = true;
//   bool _hide = true;
//
//   @override
//   void dispose() {
//     _name.dispose();
//     _id.dispose();
//     _pass.dispose();
//     super.dispose();
//   }
//
//   bool _loading = false;
//
//   void _toast(String m) =>
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
//
//   Future<void> _submit() async {
//     if (!_form.currentState!.validate()) return;
//     setState(() => _loading = true);
//     try {
//       if (_isLogin) {
//         await authService.login(email: _id.text.trim(), password: _pass.text);
//       } else {
//         await authService.register(
//           name: _name.text.trim(),
//           email: _id.text.trim(),
//           password: _pass.text,
//         );
//       }
//       // AuthGate (main.dart) switches to the next screen automatically.
//     } catch (e) {
//       if (mounted) _toast(AuthService.messageFor(e));
//     } finally {
//       if (mounted) setState(() => _loading = false);
//     }
//   }
//
//   Future<void> _forgot() async {
//     final email = _id.text.trim();
//     if (!email.contains('@')) {
//       _toast('Type your email above first, then tap Forgot Password.');
//       return;
//     }
//     try {
//       await authService.sendPasswordReset(email);
//       if (mounted) _toast('Password reset email sent to $email');
//     } catch (e) {
//       if (mounted) _toast(AuthService.messageFor(e));
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final h = MediaQuery.of(context).size.height;
//     return Scaffold(
//       backgroundColor: const Color(0xFF0B1A3A),
//       body: SingleChildScrollView(
//         child: Column(
//           children: [
//             Container(
//               width: double.infinity,
//               height: h * 0.34,
//               decoration: const BoxDecoration(
//                 gradient: LinearGradient(
//                   begin: Alignment.topCenter,
//                   end: Alignment.bottomCenter,
//                   colors: [Color(0xFF1E3A8A), Color(0xFF0B1A3A)],
//                 ),
//               ),
//               child: SafeArea(
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Container(
//                       width: 64,
//                       height: 64,
//                       decoration: BoxDecoration(
//                         color: AppColors.primary,
//                         borderRadius: BorderRadius.circular(18),
//                       ),
//                       child: const Icon(Icons.home_rounded, color: Colors.white, size: 38),
//                     ),
//                     const SizedBox(height: 14),
//                     const Text(
//                       'RoomMate',
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontSize: 32,
//                         fontWeight: FontWeight.w800,
//                       ),
//                     ),
//                     const SizedBox(height: 6),
//                     const Text(
//                       'Split Expenses\nStay United\nLive Better',
//                       textAlign: TextAlign.center,
//                       style: TextStyle(color: Colors.white70, height: 1.4),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//             Container(
//               width: double.infinity,
//               constraints: BoxConstraints(minHeight: h * 0.66),
//               padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
//               decoration: BoxDecoration(
//                 color: AppColors.of(context).bg,
//                 borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
//               ),
//               child: Form(
//                 key: _form,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       _isLogin ? 'Welcome back 👋' : 'Create your account',
//                       style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
//                     ),
//                     const SizedBox(height: 4),
//                     Text(
//                       _isLogin
//                           ? 'Login to manage your room expenses'
//                           : 'Register to start sharing expenses',
//                       style: const TextStyle(color: AppColors.muted),
//                     ),
//                     const SizedBox(height: 22),
//                     if (!_isLogin) ...[
//                       TextFormField(
//                         controller: _name,
//                         textCapitalization: TextCapitalization.words,
//                         decoration: const InputDecoration(
//                           hintText: 'Full name',
//                           prefixIcon: Icon(Icons.person_outline),
//                         ),
//                         validator: (v) =>
//                             (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
//                       ),
//                       const SizedBox(height: 14),
//                     ],
//                     TextFormField(
//                       controller: _id,
//                       keyboardType: TextInputType.emailAddress,
//                       decoration: const InputDecoration(
//                         hintText: 'Email',
//                         prefixIcon: Icon(Icons.mail_outline),
//                       ),
//                       validator: (v) =>
//                           (v == null || !v.trim().contains('@')) ? 'Enter a valid email' : null,
//                     ),
//                     const SizedBox(height: 14),
//                     TextFormField(
//                       controller: _pass,
//                       obscureText: _hide,
//                       decoration: InputDecoration(
//                         hintText: 'Password',
//                         prefixIcon: const Icon(Icons.lock_outline),
//                         suffixIcon: IconButton(
//                           icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
//                           onPressed: () => setState(() => _hide = !_hide),
//                         ),
//                       ),
//                       validator: (v) =>
//                           (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
//                     ),
//                     const SizedBox(height: 22),
//                     PrimaryButton(
//                       label: _loading ? 'Please wait...' : (_isLogin ? 'Login' : 'Register'),
//                       onPressed: _loading ? null : _submit,
//                     ),
//                     if (_isLogin)
//                       Center(
//                         child: TextButton(
//                           onPressed: _forgot,
//                           child: const Text('Forgot Password?'),
//                         ),
//                       ),
//                     const SizedBox(height: 8),
//                     Row(
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: [
//                         Text(
//                           _isLogin ? "Don't have an account? " : 'Already have an account? ',
//                           style: const TextStyle(color: AppColors.muted),
//                         ),
//                         GestureDetector(
//                           onTap: () => setState(() => _isLogin = !_isLogin),
//                           child: Text(
//                             _isLogin ? 'Sign Up' : 'Login',
//                             style: const TextStyle(
//                               color: AppColors.primary,
//                               fontWeight: FontWeight.w700,
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                     if (kIsWeb) ...[
//                       const SizedBox(height: 18),
//                       PrimaryButton(
//                         label: 'Download Android App',
//                         icon: Icons.download_rounded,
//                         outlined: true,
//                         onPressed: () => launchUrl(
//                           Uri.base.resolve('RoomMate.apk'),
//                           webOnlyWindowName: '_self',
//                         ),
//                       ),
//                     ],
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
