import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../services/cashless_service.dart';
import '../services/facility_service.dart';
import '../services/offline_code.dart';
import 'payments_screen.dart';

/// Works with no internet: computes the 6-digit approval code the kiosk
/// accepts, from the secret cached on this phone at sign-in.
class OfflineCodeScreen extends StatefulWidget {
  const OfflineCodeScreen({super.key});

  @override
  State<OfflineCodeScreen> createState() => _OfflineCodeScreenState();
}

class _OfflineCodeScreenState extends State<OfflineCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _digitsController = TextEditingController();
  final _amountController = TextEditingController();
  String? _secret;
  bool _loadingSecret = true;
  String? _code;
  String? _codeFor;
  num? _codeAmount;

  @override
  void initState() {
    super.initState();
    CashlessService().cachedSecret().then((secret) {
      if (!mounted) return;
      setState(() {
        _secret = secret;
        _loadingSecret = false;
      });
    });
  }

  @override
  void dispose() {
    _digitsController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _clearCode() {
    if (_code != null) setState(() => _code = null);
  }

  void _generate() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final requestCode = 'C-${_digitsController.text.trim()}';
    final amount = FacilityService.parsePrice(_amountController.text)!;
    setState(() {
      _codeFor = requestCode;
      _codeAmount = amount;
      _code = offlineApprovalCode(
        secret: _secret!,
        requestCode: requestCode,
        amount: amount,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Offline code'),
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: _loadingSecret
          ? const Center(child: CircularProgressIndicator())
          : _secret == null
          ? _buildNoSecret()
          : _buildForm(),
    );
  }

  Widget _buildNoSecret() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 32),
        Icon(Icons.key_off_outlined, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        const Text(
          'Offline codes are not set up on this phone',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign out and sign in again once while connected to the internet. '
          'After that, codes work without internet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          'Use this when the phone has no internet. Enter the request code '
          'and amount shown on the kiosk, then type the 6-digit code into the '
          'kiosk.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppTheme.softShadow,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _digitsController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  style: const TextStyle(fontSize: 20, letterSpacing: 2),
                  decoration: const InputDecoration(
                    labelText: 'Request code',
                    prefixText: 'C-',
                    hintText: '4821',
                  ),
                  onChanged: (_) => _clearCode(),
                  validator: (value) => RegExp(r'^\d{4}$').hasMatch(value ?? '')
                      ? null
                      : 'Enter the 4 digits after "C-".',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(fontSize: 20),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₱ ',
                  ),
                  onChanged: (_) => _clearCode(),
                  validator: (value) {
                    final amount = FacilityService.parsePrice(value ?? '');
                    if (amount == null) return 'Enter the amount.';
                    if (amount <= 0) return 'Amount must be more than ₱0.';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.pin_outlined),
                  label: const Text('Generate code'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_code != null) _buildCode(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'If the kiosk says codes are paused or locked, approve the '
                  'request from the Payments tab instead.',
                  style: TextStyle(color: Colors.blue.shade900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCode() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.softShadow,
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BankCheckWarning(amount: _codeAmount!, refDigits: null),
          const SizedBox(height: 16),
          Text(
            'Code for $_codeFor · ${formatPeso(_codeAmount!)}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SelectableText(
              _code!,
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
