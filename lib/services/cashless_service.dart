import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/cashless_request.dart';

/// Thrown by [CashlessService.review] when the request was already approved,
/// rejected or completed by someone else (or by an offline code on the kiosk).
class AlreadyHandledException implements Exception {
  const AlreadyHandledException();
}

class KioskSettings {
  final bool qrEnabled;
  final String? updatedBy;
  final DateTime? updatedAt;

  const KioskSettings({
    required this.qrEnabled,
    required this.updatedBy,
    required this.updatedAt,
  });

  factory KioskSettings.fromJson(Map<String, dynamic> json) => KioskSettings(
    qrEnabled: json['qr_enabled'] as bool? ?? false,
    updatedBy: json['updated_by'] as String?,
    updatedAt: DateTime.tryParse('${json['updated_at']}')?.toUtc(),
  );
}

class KioskQr {
  final String id;
  final String imagePath;
  final String accountName;
  final bool isActive;
  final DateTime createdAt;

  const KioskQr({
    required this.id,
    required this.imagePath,
    required this.accountName,
    required this.isActive,
    required this.createdAt,
  });

  factory KioskQr.fromJson(Map<String, dynamic> json) => KioskQr(
    id: json['id'] as String,
    imagePath: json['image_path'] as String,
    accountName: json['account_name'] as String,
    isActive: json['is_active'] as bool? ?? false,
    createdAt:
        DateTime.tryParse('${json['created_at']}')?.toUtc() ?? DateTime.now(),
  );
}

/// Cashless (QR) payments: the offline-code secret, staff initials,
/// approving/rejecting requests, the kiosk's QR switch and payment QR.
/// Table and RPC names follow supabase/003_cashless.sql in the kiosk repo.
class CashlessService {
  CashlessService._internal();

  static final CashlessService _instance = CashlessService._internal();

  factory CashlessService() => _instance;

  static const Duration _timeout = Duration(seconds: 20);
  static const String requestsTable = 'cashless_requests';
  static const String settingsTable = 'kiosk_settings';
  static const String qrTable = 'kiosk_qr';
  static const String assetsBucket = 'kiosk-assets';
  static const int maxQrBytes = 2 * 1024 * 1024;

  static const String _secretKey = 'cashless_secret';
  static const String _initialsKey = 'staff_initials';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  SupabaseClient get _client => Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Roles
  // ---------------------------------------------------------------------------

  /// Admin = `app_metadata.role == 'admin'` (only settable server-side).
  bool get isAdmin => _client.auth.currentUser?.appMetadata['role'] == 'admin';

  String? get currentUserId => _client.auth.currentUser?.id;

  // ---------------------------------------------------------------------------
  // Offline-code secret (kept in the device's secure storage)
  // ---------------------------------------------------------------------------

  /// Downloads the secret after sign-in and replaces the cached copy.
  /// Never throws: the app still works online without it.
  Future<bool> refreshSecret() async {
    try {
      final row = await _client
          .from('kiosk_secrets')
          .select('cashless_secret')
          .eq('id', 1)
          .maybeSingle()
          .timeout(_timeout);
      final secret = row?['cashless_secret'] as String?;
      if (secret == null || secret.isEmpty) return false;
      await _storage.write(key: _secretKey, value: secret);
      return true;
    } catch (error) {
      debugPrint('Could not refresh cashless secret: $error');
      return false;
    }
  }

  Future<String?> cachedSecret() => _storage.read(key: _secretKey);

  Future<void> clearSecret() async {
    try {
      await _storage.delete(key: _secretKey);
    } catch (error) {
      debugPrint('Could not clear cashless secret: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Staff initials (remembered on this device; the staff account is shared)
  // ---------------------------------------------------------------------------

  Future<String?> savedInitials() async {
    final value = (await _storage.read(key: _initialsKey))?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> saveInitials(String value) =>
      _storage.write(key: _initialsKey, value: value.trim());

  static String? validateInitials(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter your name or initials.';
    if (text.length > 40) return 'Use 40 characters or fewer.';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Requests
  // ---------------------------------------------------------------------------

  Future<List<CashlessRequest>> pendingRequests() async {
    final rows = await _client
        .from(requestsTable)
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: true)
        .timeout(_timeout);
    return _toRequests(rows);
  }

  /// Everything that isn't pending from the last 7 days, newest first.
  Future<List<CashlessRequest>> recentHistory() async {
    final since = DateTime.now().toUtc().subtract(const Duration(days: 7));
    final rows = await _client
        .from(requestsTable)
        .select()
        .neq('status', 'pending')
        .gte('created_at', since.toIso8601String())
        .order('created_at', ascending: false)
        .limit(100)
        .timeout(_timeout);
    return _toRequests(rows);
  }

  static final tz.Location manila = tz.getLocation('Asia/Manila');

  /// Completed QR payments today, midnight to midnight Asia/Manila, so it
  /// lines up with the calendar days in the bank app. (Reports keep 9 AM.)
  Future<({int count, double total})> todaysCompletedTotal() async {
    final now = tz.TZDateTime.now(manila);
    final start = tz.TZDateTime(manila, now.year, now.month, now.day);
    final rows = await _client
        .from(requestsTable)
        .select('amount')
        .eq('status', 'completed')
        .gte('created_at', start.toUtc().toIso8601String())
        .timeout(_timeout);
    var total = 0.0;
    for (final row in rows) {
      total += double.parse('${row['amount']}');
    }
    return (count: rows.length, total: total);
  }

  List<CashlessRequest> _toRequests(List<Map<String, dynamic>> rows) =>
      rows.map(CashlessRequest.fromJson).toList();

  /// Approves or rejects a pending/expired request. Throws
  /// [AlreadyHandledException] if it was handled elsewhere first.
  Future<CashlessRequest> review({
    required String id,
    required bool approve,
    required String name,
  }) async {
    try {
      final row = await _client
          .rpc(
            'review_cashless_request',
            params: {'p_id': id, 'p_approve': approve, 'p_name': name.trim()},
          )
          .timeout(_timeout);
      return CashlessRequest.fromJson(Map<String, dynamic>.from(row as Map));
    } on PostgrestException catch (error) {
      if (error.code == 'P0002') throw const AlreadyHandledException();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // kiosk_settings.qr_enabled
  // ---------------------------------------------------------------------------

  Future<KioskSettings> settings() async {
    final row = await _client
        .from(settingsTable)
        .select()
        .eq('id', 1)
        .single()
        .timeout(_timeout);
    return KioskSettings.fromJson(row);
  }

  /// Only qr_enabled may be sent; a trigger stamps updated_by/updated_at.
  Future<void> setQrEnabled(bool enabled) async {
    await _client
        .from(settingsTable)
        .update({'qr_enabled': enabled})
        .eq('id', 1)
        .timeout(_timeout);
  }

  // ---------------------------------------------------------------------------
  // Payment QR (admin only)
  // ---------------------------------------------------------------------------

  Future<List<KioskQr>> qrHistory() async {
    final rows = await _client
        .from(qrTable)
        .select()
        .order('created_at', ascending: false)
        .timeout(_timeout);
    return rows.map(KioskQr.fromJson).toList();
  }

  Future<String> signedQrUrl(String path) => _client.storage
      .from(assetsBucket)
      .createSignedUrl(path, 60 * 60)
      .timeout(_timeout);

  /// "image/png" or "image/jpeg" from the file's first bytes, else null.
  static String? detectImageType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    return null;
  }

  /// Uploads the image to `kiosk-assets/qr/<timestamp>-<random>.<ext>`, then
  /// makes it the kiosk's active QR. Removes the upload if activation fails.
  Future<KioskQr> changeQr({
    required Uint8List bytes,
    required String contentType,
    required String accountName,
  }) async {
    final ext = contentType == 'image/png' ? 'png' : 'jpg';
    final path =
        'qr/${DateTime.now().millisecondsSinceEpoch}-${_randomHex(8)}.$ext';
    final bucket = _client.storage.from(assetsBucket);

    await bucket
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        )
        .timeout(const Duration(seconds: 60));

    try {
      final row = await _client
          .rpc(
            'set_active_qr',
            params: {
              'p_image_path': path,
              'p_account_name': accountName.trim(),
            },
          )
          .timeout(_timeout);
      return KioskQr.fromJson(Map<String, dynamic>.from(row as Map));
    } catch (_) {
      try {
        await bucket.remove([path]);
      } catch (_) {}
      rethrow;
    }
  }

  static String _randomHex(int byteCount) {
    final random = Random.secure();
    return List.generate(
      byteCount,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  // ---------------------------------------------------------------------------
  // Errors
  // ---------------------------------------------------------------------------

  static String errorMessage(Object error) {
    if (error is AlreadyHandledException) {
      return 'Already handled by someone else or on the kiosk.';
    }
    if (error is PostgrestException) {
      switch (error.code) {
        case '42501':
          return error.message.toLowerCase().contains('not signed in')
              ? 'You are signed out. Sign in again.'
              : 'Your account is not allowed to do this.\n${error.message}';
        case '22023':
          return error.message;
        case 'P0002':
          return error.message;
      }
      return error.message;
    }
    if (error is StorageException) {
      final status = '${error.statusCode}';
      if (status == '413' || error.message.toLowerCase().contains('size')) {
        return 'The image is too large (max 2 MB).';
      }
      if (status == '403' || status == '401') {
        return 'Only the admin account can upload a payment QR.';
      }
      return 'Upload failed: ${error.message}';
    }
    if (error is SocketException || error is TimeoutException) {
      return 'No internet connection. Connect and try again.';
    }
    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('failed host lookup') ||
        text.contains('network')) {
      return 'No internet connection. Connect and try again.';
    }
    return error.toString();
  }
}
