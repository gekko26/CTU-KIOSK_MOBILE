import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// App bar button showing who is signed in, with a Sign out action.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  Future<void> _showAccountSheet(BuildContext context) async {
    final authService = AuthService();
    final email = authService.currentEmail;

    final shouldSignOut = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: const Text('Signed in as'),
                subtitle: Text(email.isEmpty ? 'Unknown account' : email),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (shouldSignOut != true || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need your password to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    // The auth listener in main.dart sends the app back to the login screen.
    await authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _showAccountSheet(context),
      icon: const Icon(Icons.account_circle_outlined),
      tooltip: 'Account',
    );
  }
}
