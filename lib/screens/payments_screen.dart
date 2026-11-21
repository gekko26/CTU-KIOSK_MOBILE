import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../config/app_theme.dart';
import '../models/cashless_request.dart';
import '../services/cashless_controller.dart';
import '../services/cashless_service.dart';
import '../services/facility_service.dart';
import '../widgets/kiosk_widgets.dart';
import 'offline_code_screen.dart';

/// ₱1,500 or ₱1,500.50
String formatPeso(num amount) {
  final whole = amount == amount.roundToDouble();
  return NumberFormat(whole ? '₱#,##0' : '₱#,##0.00').format(amount);
}

String formatManilaTime(DateTime time) {
  final local = tz.TZDateTime.from(time.toUtc(), CashlessService.manila);
  final now = tz.TZDateTime.now(CashlessService.manila);
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return DateFormat(sameDay ? 'h:mm a' : 'MMM d, h:mm a').format(local);
}

String timeAgo(DateTime time) {
  final diff = DateTime.now().toUtc().difference(time.toUtc());
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

/// Asks for (and remembers) the staff member's name or initials. Returns
/// null if cancelled.
Future<String?> askForInitials(BuildContext context, {String? current}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _InitialsDialog(current: current),
  );
}

class _InitialsDialog extends StatefulWidget {
  final String? current;
  const _InitialsDialog({this.current});

  @override
  State<_InitialsDialog> createState() => _InitialsDialogState();
}

class _InitialsDialogState extends State<_InitialsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.current ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final value = _controller.text.trim();
    await CashlessService().saveInitials(value);
    if (mounted) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your name or initials'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Saved with every approval and rejection, so we know who '
              'checked the payment. It is remembered on this phone.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controller,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name or initials',
                hintText: 'e.g. J. Cruz',
              ),
              validator: CashlessService.validateInitials,
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class PaymentsScreen extends StatefulWidget {
  final CashlessController controller;

  const PaymentsScreen({required this.controller, super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final CashlessService _service = CashlessService();
  Map<String, String> _facilityNames = const {};
  final Set<String> _busyIds = {};

  CashlessController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadFacilityNames();
  }

  Future<void> _loadFacilityNames() async {
    try {
      final facilities = await FacilityService().getFacilities();
      if (!mounted) return;
      setState(() {
        _facilityNames = {for (final f in facilities) f.code: f.name};
      });
    } catch (_) {
      // Codes are shown instead.
    }
  }

  String _facilityLabel(String code) {
    final name = _facilityNames[code];
    return name == null ? code : '$name ($code)';
  }

  Future<void> _editInitials() async {
    final current = await _service.savedInitials();
    if (!mounted) return;
    final saved = await askForInitials(context, current: current);
    if (saved != null && mounted) {
      showKioskSnack(context, 'Saved. Approvals will be signed "$saved".');
    }
  }

  void _openOfflineCode() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OfflineCodeScreen()),
    );
  }

  Future<void> _review(CashlessRequest request, {required bool approve}) async {
    var name = await _service.savedInitials();
    if (!mounted) return;
    name ??= await askForInitials(context);
    if (name == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ReviewConfirmDialog(
        request: request,
        approve: approve,
        initialName: name!,
      ),
    );
    if (confirmed != true || !mounted) return;
    // The dialog may have changed the name.
    name = await _service.savedInitials() ?? name;
    if (!mounted) return;

    final wasExpired = request.isExpired;
    setState(() => _busyIds.add(request.id));
    try {
      await _service.review(id: request.id, approve: approve, name: name);
      if (!mounted) return;
      if (approve && wasExpired) {
        await showKioskMessage(
          context,
          title: 'Approved — ticket not printed',
          message:
              'Approved — the ticket wasn\'t printed. Reprint it from the '
              'kiosk Admin page.',
        );
      } else {
        showKioskSnack(
          context,
          approve
              ? '${request.requestCode} approved. The kiosk will print the ticket.'
              : '${request.requestCode} rejected.',
        );
      }
    } on AlreadyHandledException {
      if (mounted) {
        showKioskSnack(
          context,
          '${request.requestCode} was already handled by someone else or on '
          'the kiosk.',
          error: true,
        );
      }
    } catch (error) {
      if (mounted) {
        showKioskSnack(
          context,
          CashlessService.errorMessage(error),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(request.id));
      await _c.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Payments'),
        elevation: 0,
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _openOfflineCode,
            icon: const Icon(Icons.pin_outlined),
            tooltip: 'Generate offline code',
          ),
          IconButton(
            onPressed: _c.reload,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'initials') _editInitials();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'initials',
                child: ListTile(
                  leading: Icon(Icons.badge_outlined),
                  title: Text('Your name / initials'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) =>
            RefreshIndicator(onRefresh: _c.reload, child: _buildList()),
      ),
    );
  }

  Widget _buildList() {
    if (_c.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final children = <Widget>[
      if (_c.error != null) _buildErrorBanner(_c.error!),
      if (_c.error == null && !_c.realtimeConnected) _buildReconnectingNote(),
      _buildTodayCard(),
      const SizedBox(height: 16),
      _sectionTitle('Waiting for approval', _c.pending.length),
      if (_c.pending.isEmpty)
        _buildEmptyPending()
      else
        ..._c.pending.map(_buildPendingCard),
      const SizedBox(height: 16),
      _sectionTitle('History (last 7 days)', null),
      if (_c.history.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'No QR payments yet.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        )
      else
        ..._c.history.map(_buildHistoryCard),
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: children,
    );
  }

  Widget _sectionTitle(String title, int? count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        count == null ? title : '$title ($count)',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Text(
        'Could not refresh: $message\n\nNo internet? Use "Generate offline '
        'code" (top right).',
        style: TextStyle(color: Colors.red.shade800),
      ),
    );
  }

  Widget _buildReconnectingNote() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(Icons.sync_problem, size: 16, color: Colors.orange.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Live updates reconnecting — the list still refreshes every 30 s.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.green.shade50,
            foregroundColor: Colors.green.shade700,
            child: const Icon(Icons.qr_code_2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today (since 12:00 AM)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Completed QR payments — compare with your bank app.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatPeso(_c.todayTotal),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
              Text(
                '${_c.todayCount} payment${_c.todayCount == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPending() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 40,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 8),
          Text(
            'No payments waiting',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'New QR payments from the kiosk appear here right away.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCard(CashlessRequest r) {
    final busy = _busyIds.contains(r.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.softShadow,
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  r.requestCode,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                formatPeso(r.amount),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _infoRow(Icons.tag, 'Ref digits', _refText(r)),
          _infoRow(
            Icons.storefront_outlined,
            'Facility',
            _facilityLabel(r.facilityCode),
          ),
          _infoRow(
            Icons.schedule,
            'Requested',
            '${timeAgo(r.createdAt)} · ${formatManilaTime(r.createdAt)}',
          ),
          const SizedBox(height: 12),
          _reviewButtons(r, busy),
        ],
      ),
    );
  }

  String _refText(CashlessRequest r) =>
      r.refDigits == null ? 'not entered' : '…${r.refDigits}';

  Widget _reviewButtons(CashlessRequest r, bool busy) {
    if (busy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _review(r, approve: false),
            icon: const Icon(Icons.close),
            label: const Text('Reject'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _review(r, approve: true),
            icon: const Icon(Icons.check),
            label: const Text('Approve'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(color: Colors.grey.shade600)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(CashlessRequest r) {
    final busy = _busyIds.contains(r.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                r.requestCode,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              CashlessStatusChip(status: r.status),
              const Spacer(),
              Text(
                formatPeso(r.amount),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Ref ${_refText(r)} · ${_facilityLabel(r.facilityCode)} · '
            '${formatManilaTime(r.createdAt)}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 2),
          Text(
            _verifiedText(r),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          if (r.isExpired) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'The kiosk timed out. If the money did arrive, you can still '
                'approve it: the sale is recorded but the ticket is NOT '
                'printed — reprint it from the kiosk Admin page.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
              ),
            ),
            const SizedBox(height: 10),
            _reviewButtons(r, busy),
          ],
        ],
      ),
    );
  }

  String _verifiedText(CashlessRequest r) {
    if (r.isExpired) return 'Not reviewed before the kiosk timed out.';
    final who =
        r.verifiedByName ??
        (r.approvalSource == 'offline_code' ? 'offline code' : null);
    final source = r.approvalSource == 'offline_code'
        ? ' (offline code on kiosk)'
        : r.approvalSource == 'app'
        ? ' (app)'
        : '';
    final when = r.verifiedAt == null
        ? ''
        : ' at ${formatManilaTime(r.verifiedAt!)}';
    final verb = r.status == 'rejected' ? 'Rejected' : 'Approved';
    if (who == null && r.verifiedAt == null) return 'No reviewer recorded.';
    return '$verb by ${who ?? 'unknown'}$source$when';
  }
}

class CashlessStatusChip extends StatelessWidget {
  final String status;

  const CashlessStatusChip({required this.status, super.key});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'pending' => ('Pending', Colors.blue),
      'approved' => ('Approved', Colors.indigo),
      'completed' => ('Completed', Colors.green),
      'rejected' => ('Rejected', Colors.red),
      'expired' => ('Expired', Colors.orange),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color.shade800,
        ),
      ),
    );
  }
}

/// "Only approve after you see ₱X with reference …Y in YOUR bank app."
class BankCheckWarning extends StatelessWidget {
  final num amount;
  final String? refDigits;
  final bool approve;

  const BankCheckWarning({
    required this.amount,
    required this.refDigits,
    this.approve = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ref = refDigits == null ? '' : ' with reference …$refDigits';
    final text = approve
        ? 'Only approve after you see ${formatPeso(amount)}$ref in YOUR bank '
              'app. Never accept screenshots.'
        : 'Only reject after checking YOUR bank app: no ${formatPeso(amount)} '
              'payment$ref arrived. Never trust screenshots.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewConfirmDialog extends StatefulWidget {
  final CashlessRequest request;
  final bool approve;
  final String initialName;

  const _ReviewConfirmDialog({
    required this.request,
    required this.approve,
    required this.initialName,
  });

  @override
  State<_ReviewConfirmDialog> createState() => _ReviewConfirmDialogState();
}

class _ReviewConfirmDialogState extends State<_ReviewConfirmDialog> {
  late String _name = widget.initialName;

  Future<void> _changeName() async {
    final saved = await askForInitials(context, current: _name);
    if (saved != null && mounted) setState(() => _name = saved);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final approve = widget.approve;
    return AlertDialog(
      title: Text(
        '${approve ? 'Approve' : 'Reject'} ${r.requestCode} · '
        '${formatPeso(r.amount)}?',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BankCheckWarning(
              amount: r.amount,
              refDigits: r.refDigits,
              approve: approve,
            ),
            if (approve && r.isExpired) ...[
              const SizedBox(height: 12),
              const Text(
                'This request timed out on the kiosk. Approving records the '
                'sale but the ticket will NOT print — reprint it from the '
                'kiosk Admin page.',
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('Signed as: $_name')),
                TextButton(onPressed: _changeName, child: const Text('Change')),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: approve
                ? Colors.green.shade700
                : AppTheme.errorRed,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(approve ? 'Approve' : 'Reject'),
        ),
      ],
    );
  }
}
