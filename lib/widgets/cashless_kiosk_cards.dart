import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';
import '../screens/payments_screen.dart' show formatManilaTime;
import '../services/admin_rpc.dart';
import '../services/cashless_service.dart';
import 'admin_pin_dialog.dart';
import 'kiosk_widgets.dart';

/// Shadow + rounded corners; the white fill comes from a Material inside
/// so ListTile ink splashes stay visible.
BoxDecoration _cardDecoration() => BoxDecoration(
  borderRadius: BorderRadius.circular(14),
  boxShadow: AppTheme.softShadow,
);

/// Subscribes to one table and calls [onChange] on any insert/update/delete.
RealtimeChannel _watchTable(String table, VoidCallback onChange) {
  return Supabase.instance.client
      .channel('kiosk-tab-$table')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => onChange(),
      )
      .subscribe();
}

// -----------------------------------------------------------------------------
// QR payments on/off (staff and admin)
// -----------------------------------------------------------------------------

class QrPaymentsSwitchCard extends StatefulWidget {
  const QrPaymentsSwitchCard({super.key});

  @override
  State<QrPaymentsSwitchCard> createState() => _QrPaymentsSwitchCardState();
}

class _QrPaymentsSwitchCardState extends State<QrPaymentsSwitchCard> {
  final CashlessService _service = CashlessService();
  RealtimeChannel? _channel;
  KioskSettings? _settings;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _channel = _watchTable(CashlessService.settingsTable, _load);
    _load();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _service.settings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = CashlessService.errorMessage(error));
    }
  }

  Future<void> _toggle(bool enabled) async {
    setState(() => _saving = true);
    try {
      await _service.setQrEnabled(enabled);
      if (mounted) {
        showKioskSnack(
          context,
          enabled
              ? 'QR payments turned ON. The kiosk shows "Pay with QR".'
              : 'QR payments turned OFF. The kiosk takes cash only.',
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
      if (mounted) setState(() => _saving = false);
      await _load();
    }
  }

  String _lastChanged(KioskSettings s) {
    if (s.updatedAt == null) return '';
    final String who;
    if (s.updatedBy == null) {
      who = '';
    } else if (s.updatedBy == _service.currentUserId) {
      who = ' by you';
    } else {
      // Only two accounts exist: whoever it wasn't, is the other one.
      who = _service.isAdmin ? ' by staff' : ' by admin';
    }
    return 'Last changed$who at ${formatManilaTime(s.updatedAt!)}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration(),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          secondary: CircleAvatar(
            backgroundColor: Colors.green.shade50,
            foregroundColor: Colors.green.shade700,
            child: const Icon(Icons.qr_code_2),
          ),
          title: const Text(
            'QR payments',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            _error != null
                ? 'Could not load: $_error'
                : settings == null
                ? 'Loading…'
                : [
                    settings.qrEnabled
                        ? 'On — customers can pay with QR.'
                        : 'Off — cash only.',
                    _lastChanged(settings),
                  ].where((s) => s.isNotEmpty).join('\n'),
            style: _error != null
                ? TextStyle(color: Colors.red.shade700)
                : null,
          ),
          value: settings?.qrEnabled ?? false,
          onChanged: settings == null || _saving ? null : _toggle,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Payment QR (admin only)
// -----------------------------------------------------------------------------

class PaymentQrCard extends StatefulWidget {
  const PaymentQrCard({super.key});

  @override
  State<PaymentQrCard> createState() => _PaymentQrCardState();
}

class _PaymentQrCardState extends State<PaymentQrCard> {
  final CashlessService _service = CashlessService();
  RealtimeChannel? _channel;
  List<KioskQr> _history = const [];
  QrChangeStatus? _status;
  String? _statusError;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// Null while unknown; "Change QR" stays disabled until it is known.
  bool get _changeAllowed => _status?.allowed == true;

  KioskQr? get _active {
    for (final qr in _history) {
      if (qr.isActive) return qr;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _channel = _watchTable(CashlessService.qrTable, _load);
    _load();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([_loadHistory(), _loadStatus()]);
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _service.qrHistory();
      if (!mounted) return;
      setState(() {
        _history = history;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = CashlessService.errorMessage(error);
      });
    }
  }

  Future<void> _loadStatus() async {
    try {
      final status = await _service.qrChangeStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _statusError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _statusError = CashlessService.errorMessage(error);
      });
    }
  }

  String _nextAllowedText(DateTime? next) => next == null
      ? 'The payment QR can only be changed once every 7 days.'
      : 'Next change allowed on ${formatManilaDateTime(next)} (Manila time).';

  Future<void> _changeQr() async {
    // Re-check the 7-day cooldown before picking/uploading anything.
    await _loadStatus();
    if (!mounted) return;
    if (!_changeAllowed) {
      if (_status != null) {
        await showKioskMessage(
          context,
          title: 'QR can’t be changed yet',
          message: _nextAllowedText(_status!.nextAllowedAt),
        );
      } else {
        showKioskSnack(
          context,
          _statusError ?? 'Could not check when the QR can be changed.',
          error: true,
        );
      }
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text(
                'Best: the QR image saved from the bank app',
              ),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 92,
      );
    } catch (error) {
      if (mounted) {
        showKioskSnack(
          context,
          'Could not open the image: $error',
          error: true,
        );
      }
      return;
    }
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    final contentType = CashlessService.detectImageType(bytes);
    if (!mounted) return;
    if (contentType == null) {
      showKioskSnack(context, 'Use a PNG or JPEG image.', error: true);
      return;
    }
    if (bytes.length > CashlessService.maxQrBytes) {
      showKioskSnack(
        context,
        'The image is ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB. '
        'The limit is 2 MB.',
        error: true,
      );
      return;
    }

    final accountName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewQrDialog(bytes: bytes),
    );
    if (accountName == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change the payment QR?'),
        content: Text(
          'All QR payments will go to this account:\n\n$accountName\n\n'
          'The kiosk shows the new QR right away. Check that the account '
          'name matches the bank app.\n\n'
          'You won’t be able to change the QR again for 7 days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Use this QR'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Uploading QR…')),
            ],
          ),
        ),
      ),
    );

    // 1. Upload (no PIN needed; the file does nothing until activated).
    final String path;
    try {
      path = await _service.uploadQrImage(
        bytes: bytes,
        contentType: contentType,
      );
    } catch (error) {
      if (mounted) {
        Navigator.of(context).pop();
        setState(() => _busy = false);
        await showKioskMessage(
          context,
          title: 'QR not changed',
          message: CashlessService.errorMessage(error),
        );
      }
      return;
    }
    if (!mounted) {
      await _service.removeQrUpload(path);
      return;
    }
    Navigator.of(context).pop();

    // 2. PIN, then set_active_qr. Any failure removes the upload.
    try {
      await runWithAdminPin<KioskQr>(
        context,
        title: 'Enter admin PIN',
        message: 'Confirm the new payment QR for $accountName.',
        confirmLabel: 'Change QR',
        action: (pin) => _service.activateQr(
          imagePath: path,
          accountName: accountName,
          pin: pin,
        ),
      );
      if (mounted) {
        showKioskSnack(context, 'Payment QR changed to $accountName.');
      }
    } on PinCancelledException {
      await _service.removeQrUpload(path);
      if (mounted) showKioskSnack(context, 'QR not changed.');
    } catch (error) {
      await _service.removeQrUpload(path);
      if (mounted) {
        await showKioskMessage(
          context,
          title:
              error is AdminRpcException &&
                  error.code == AdminRpcCode.qrCooldown
              ? 'QR can’t be changed yet'
              : 'QR not changed',
          message: CashlessService.errorMessage(error),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final previous = _history.where((q) => !q.isActive).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration(),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.purple.shade50,
                    foregroundColor: Colors.purple.shade700,
                    child: const Icon(Icons.account_balance_wallet_outlined),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Payment QR',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Admin only',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Text(
                  'Could not load: $_error',
                  style: TextStyle(color: Colors.red.shade700),
                )
              else if (active == null)
                Text(
                  'No payment QR yet. The kiosk can\'t take QR payments until '
                  'you add one.',
                  style: TextStyle(color: Colors.grey.shade700),
                )
              else ...[
                Center(child: _QrImage(path: active.imagePath, size: 200)),
                const SizedBox(height: 8),
                Text(
                  active.accountName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Since ${formatManilaTime(active.createdAt)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading || _busy || !_changeAllowed
                    ? null
                    : _changeQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Change QR'),
              ),
              if (!_loading && _status != null && !_status!.allowed)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _nextAllowedText(_status!.nextAllowedAt),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
                )
              else if (!_loading && _statusError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextButton.icon(
                    onPressed: _loadStatus,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(
                      'Could not check when the QR can be changed. Retry',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ),
              if (previous.isNotEmpty)
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Previous QRs (${previous.length})'),
                    children: [
                      for (final qr in previous)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: _QrImage(path: qr.imagePath, size: 48),
                          title: Text(qr.accountName),
                          subtitle: Text(formatManilaTime(qr.createdAt)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Private bucket: shows the image through a short-lived signed URL.
class _QrImage extends StatefulWidget {
  final String path;
  final double size;

  const _QrImage({required this.path, required this.size});

  @override
  State<_QrImage> createState() => _QrImageState();
}

class _QrImageState extends State<_QrImage> {
  late Future<String> _url = CashlessService().signedQrUrl(widget.path);

  @override
  void didUpdateWidget(covariant _QrImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _url = CashlessService().signedQrUrl(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: widget.size,
      height: widget.size,
      color: Colors.grey.shade100,
      child: Icon(Icons.qr_code_2, color: Colors.grey.shade400),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: FutureBuilder<String>(
        future: _url,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return placeholder;
          return Image.network(
            snapshot.data!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => placeholder,
          );
        },
      ),
    );
  }
}

class _NewQrDialog extends StatefulWidget {
  final Uint8List bytes;

  const _NewQrDialog({required this.bytes});

  @override
  State<_NewQrDialog> createState() => _NewQrDialogState();
}

class _NewQrDialogState extends State<_NewQrDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New payment QR'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  widget.bytes,
                  height: 220,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scan it with another phone to check it opens the right '
                'account.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                autofocus: true,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  hintText: 'As shown in GoTyme / GCash',
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'Enter the account name.';
                  if (text.length > 80) return 'Use 80 characters or fewer.';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_nameController.text.trim());
            }
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
