import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Staff sign-in. There is deliberately no sign-up: accounts are created
/// by the administrator in the Supabase dashboard (Authentication → Users).
class AuthService {
  AuthService._internal();

  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// True when a saved session exists. The session is stored on the device,
  /// so staff stay signed in between app launches (and when offline).
  bool get isSignedIn => _auth.currentSession != null;

  User? get currentUser => _auth.currentUser;

  String get currentEmail => _auth.currentUser?.email ?? '';

  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  /// Returns null on success, or a message to show the user.
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || password.isEmpty) {
      return 'Enter your email and password.';
    }

    try {
      await _auth
          .signInWithPassword(email: trimmedEmail, password: password)
          .timeout(const Duration(seconds: 20));
      return null;
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials') ||
          message.contains('invalid credentials')) {
        return 'Wrong email or password.';
      }
      if (message.contains('email not confirmed')) {
        return 'This account is not confirmed yet. Ask the administrator.';
      }
      if (message.contains('banned')) {
        return 'This account has been disabled.';
      }
      return 'Sign-in failed: ${error.message}';
    } on SocketException {
      return 'No internet connection. Connect and try again.';
    } on TimeoutException {
      return 'The server took too long to respond. Try again.';
    } catch (error) {
      final text = error.toString().toLowerCase();
      if (text.contains('socket') ||
          text.contains('failed host lookup') ||
          text.contains('network')) {
        return 'No internet connection. Connect and try again.';
      }
      return 'Sign-in failed. Please try again.';
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Offline: still clear the local session so the device is signed out.
      await _auth.signOut(scope: SignOutScope.local);
    }
  }
}
