import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Offline approval code for a cashless (QR) request. Must match the kiosk:
///
///   message = "{requestCode}|{amount in centavos}"   (UTF-8)
///   mac     = HMAC-SHA256(secret, message)
///   code    = (first 4 bytes of mac, big-endian uint32) % 1000000
///
/// Returned as 6 digits with leading zeros kept (e.g. "011621").
String offlineApprovalCode({
  required String secret,
  required String requestCode,
  required num amount,
}) {
  final centavos = (amount * 100).round();
  final message = '$requestCode|$centavos';
  final mac = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(message));
  final b = mac.bytes;
  final value = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  return (value % 1000000).toString().padLeft(6, '0');
}
