import 'dart:async';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

/// Admin-only RPCs that need the 6-digit admin PIN (kiosk repo
/// docs/admin-pin.md §4). They don't throw for an expected refusal: they
/// return `{ok: false, code, message, ...}`, which [callAdminRpc] turns into
/// an [AdminRpcException]. Network/auth errors still throw as usual.
class AdminRpcCode {
  static const ok = 'OK';
  static const notAdmin = 'NOT_ADMIN';
  static const pinNotSet = 'PIN_NOT_SET';
  static const pinFormat = 'PIN_FORMAT';
  static const pinWrong = 'PIN_WRONG';
  static const pinLocked = 'PIN_LOCKED';
  static const qrCooldown = 'QR_COOLDOWN';
  static const invalidInput = 'INVALID_INPUT';
  static const notFound = 'NOT_FOUND';
  static const conflict = 'CONFLICT';
  static const dbError = 'DB_ERROR';
}

class AdminRpcException implements Exception {
  final String code;
  final String? serverMessage;
  final int? attemptsLeft;
  final int? minutesLeft;
  final DateTime? lockedUntil;
  final DateTime? nextAllowedAt;
  final String? nextAllowedAtManila;
  final String? sqlstate;

  const AdminRpcException({
    required this.code,
    this.serverMessage,
    this.attemptsLeft,
    this.minutesLeft,
    this.lockedUntil,
    this.nextAllowedAt,
    this.nextAllowedAtManila,
    this.sqlstate,
  });

  factory AdminRpcException.fromResult(Map<String, dynamic> res) {
    return AdminRpcException(
      code: res['code']?.toString() ?? AdminRpcCode.dbError,
      serverMessage: _nonEmpty(res['message']),
      attemptsLeft: _asInt(res['attempts_left']),
      minutesLeft: _asInt(res['minutes_left']),
      lockedUntil: _asTime(res['locked_until']),
      nextAllowedAt: _asTime(res['next_allowed_at']),
      nextAllowedAtManila: _nonEmpty(res['next_allowed_at_manila']),
      sqlstate: _nonEmpty(res['sqlstate']),
    );
  }

  /// The PIN was wrong but more tries are left: keep the PIN dialog open.
  bool get isRetryablePin => code == AdminRpcCode.pinWrong;

  /// Text for the user. The server's `message` is written for users, so it
  /// is preferred; the fallbacks cover an empty message.
  String get userMessage {
    final server = serverMessage;
    switch (code) {
      case AdminRpcCode.notAdmin:
        return 'Only the admin account can do this.';
      case AdminRpcCode.pinNotSet:
        return server ??
            'No admin PIN has been set up yet. Ask the system administrator '
                'to set one.';
      case AdminRpcCode.pinFormat:
        return 'The PIN must be exactly 6 digits.';
      case AdminRpcCode.pinWrong:
        if (server != null) return server;
        return attemptsLeft == null
            ? 'Wrong PIN.'
            : 'Wrong PIN ($attemptsLeft '
                  '${attemptsLeft == 1 ? 'attempt' : 'attempts'} left).';
      case AdminRpcCode.pinLocked:
        if (server != null) return server;
        return minutesLeft == null
            ? 'PIN locked. Try again later.'
            : 'PIN locked — try again in $minutesLeft '
                  '${minutesLeft == 1 ? 'minute' : 'minutes'}.';
      case AdminRpcCode.qrCooldown:
        final next = nextAllowedAt != null
            ? formatManilaDateTime(nextAllowedAt!)
            : nextAllowedAtManila;
        return next == null
            ? 'The payment QR can only be changed once every 7 days.'
            : 'The payment QR can only be changed once every 7 days.\n'
                  'Next change allowed on $next (Manila time).';
      case AdminRpcCode.invalidInput:
        return server ?? 'Some values were not accepted. Check and try again.';
      case AdminRpcCode.notFound:
        return server ?? 'Not found. It may have been deleted. Refresh.';
      case AdminRpcCode.conflict:
        return server ?? 'That code is already used.';
      default:
        final detail = sqlstate == null ? '' : ' (error $sqlstate)';
        return server ?? 'The server could not save this$detail. Try again.';
    }
  }

  @override
  String toString() => userMessage;
}

/// Thrown when the admin cancels the PIN dialog (nothing was sent).
class PinCancelledException implements Exception {
  const PinCancelledException();

  @override
  String toString() => 'Cancelled.';
}

/// Calls a PIN-protected RPC and returns its `data` on success, or throws
/// [AdminRpcException] when `ok` is false.
Future<Map<String, dynamic>> callAdminRpc(
  String name,
  Map<String, dynamic> params, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final raw = await Supabase.instance.client
      .rpc(name, params: params)
      .timeout(timeout);
  if (raw is! Map) {
    throw const AdminRpcException(
      code: AdminRpcCode.dbError,
      serverMessage: 'Unexpected reply from the server.',
    );
  }
  final res = Map<String, dynamic>.from(raw);
  if (res['ok'] != true) throw AdminRpcException.fromResult(res);
  final data = res['data'];
  return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
}

final tz.Location _manila = tz.getLocation('Asia/Manila');

/// "Nov 28, 2026, 3:15 PM" in Asia/Manila.
String formatManilaDateTime(DateTime time) {
  final local = tz.TZDateTime.from(time.toUtc(), _manila);
  return DateFormat('MMM d, yyyy, h:mm a').format(local);
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

int? _asInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}');
}

DateTime? _asTime(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toUtc();
}
