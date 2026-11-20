import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// "Changes reach the kiosk within 5 minutes." banner.
class KioskSyncNote extends StatelessWidget {
  const KioskSyncNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 18, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Changes reach the kiosk within 5 minutes.',
              style: TextStyle(color: Colors.blue.shade800, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small "Active" / "Hidden" pill.
class ActiveBadge extends StatelessWidget {
  final bool isActive;

  const ActiveBadge({required this.isActive, super.key});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppTheme.successGreen : AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.visibility : Icons.visibility_off,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isActive ? 'Active' : 'Hidden',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-area error with the Supabase message and a retry button.
/// Scrollable so pull-to-refresh still works around it.
class KioskErrorView extends StatelessWidget {
  final String title;
  final String message;
  final Future<void> Function() onRetry;

  const KioskErrorView({
    required this.title,
    required this.message,
    required this.onRetry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        Icon(Icons.cloud_off, size: 64, color: Colors.red.shade300),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.red.shade700, height: 1.35),
        ),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}

/// Simple scrollable empty state (keeps pull-to-refresh working).
class KioskEmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const KioskEmptyView({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        Icon(icon, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

void showKioskSnack(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        duration: Duration(seconds: error ? 6 : 3),
      ),
    );
}

/// Plain message dialog with an OK button.
Future<void> showKioskMessage(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SelectableText(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
