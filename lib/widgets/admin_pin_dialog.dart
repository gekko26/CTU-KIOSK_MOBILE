import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_rpc.dart';

/// Asks for the 6-digit admin PIN and runs [action] with it.
///
/// - Wrong PIN (`PIN_WRONG`): the dialog stays open, shows the server's
///   message and the field is cleared for another try.
/// - Success: returns [action]'s result.
/// - Cancel: throws [PinCancelledException].
/// - Anything else (locked, cooldown, validation, network…): the dialog
///   closes and the error is rethrown for the caller to show.
///
/// The PIN only lives in the text field and the [action] call; the field is
/// cleared after every attempt and it is never stored or logged.
Future<T> runWithAdminPin<T>(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  required Future<T> Function(String pin) action,
}) async {
  final outcome = await showDialog<_PinOutcome<T>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AdminPinDialog<T>(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      action: action,
    ),
  );
  if (outcome == null) throw const PinCancelledException();
  if (outcome.error != null) {
    Error.throwWithStackTrace(outcome.error!, outcome.stackTrace!);
  }
  return outcome.value as T;
}

class _PinOutcome<T> {
  final T? value;
  final Object? error;
  final StackTrace? stackTrace;

  const _PinOutcome.success(this.value) : error = null, stackTrace = null;
  const _PinOutcome.failure(this.error, this.stackTrace) : value = null;
}

class _AdminPinDialog<T> extends StatefulWidget {
  final String title;
  final String? message;
  final String confirmLabel;
  final Future<T> Function(String pin) action;

  const _AdminPinDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.action,
  });

  @override
  State<_AdminPinDialog<T>> createState() => _AdminPinDialogState<T>();
}

class _AdminPinDialogState<T> extends State<_AdminPinDialog<T>> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _busy = false;
  String? _error;

  bool get _complete => _controller.text.length == 6;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_complete) return;
    final pin = _controller.text;
    // Clear right away: the PIN is only kept for this one call.
    _controller.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await widget.action(pin);
      if (mounted) Navigator.of(context).pop(_PinOutcome<T>.success(value));
    } on AdminRpcException catch (error, stack) {
      if (!mounted) return;
      if (error.isRetryablePin) {
        setState(() {
          _busy = false;
          _error = error.userMessage;
        });
        _focusNode.requestFocus();
      } else {
        Navigator.of(context).pop(_PinOutcome<T>.failure(error, stack));
      }
    } catch (error, stack) {
      if (mounted) {
        Navigator.of(context).pop(_PinOutcome<T>.failure(error, stack));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.message != null) ...[
                  Text(widget.message!),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  enabled: !_busy,
                  obscureText: true,
                  obscuringCharacter: '●',
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(fontSize: 22, letterSpacing: 8),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Admin PIN',
                    counterText: '',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy || !_complete ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
