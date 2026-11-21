import 'package:ctu_kiosk_mobile/services/admin_rpc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  AdminRpcException parse(Map<String, dynamic> res) =>
      AdminRpcException.fromResult({'ok': false, ...res});

  test('PIN_WRONG shows the server message and is retryable', () {
    final e = parse({
      'code': 'PIN_WRONG',
      'message': 'Wrong PIN, 3 attempts left',
      'attempts_left': 3,
    });
    expect(e.isRetryablePin, isTrue);
    expect(e.attemptsLeft, 3);
    expect(e.userMessage, 'Wrong PIN, 3 attempts left');
  });

  test('PIN_WRONG without a message falls back to attempts left', () {
    final e = parse({'code': 'PIN_WRONG', 'attempts_left': 1});
    expect(e.userMessage, 'Wrong PIN (1 attempt left).');
  });

  test('PIN_LOCKED is not retryable and falls back to minutes left', () {
    final e = parse({
      'code': 'PIN_LOCKED',
      'minutes_left': 15,
      'attempts_left': 0,
      'locked_until': '2026-11-21T08:15:00+00:00',
    });
    expect(e.isRetryablePin, isFalse);
    expect(e.lockedUntil, DateTime.utc(2026, 11, 21, 8, 15));
    expect(e.userMessage, 'PIN locked — try again in 15 minutes.');
  });

  test('QR_COOLDOWN shows the next allowed time in Manila', () {
    final e = parse({
      'code': 'QR_COOLDOWN',
      'message': 'ignored',
      'next_allowed_at': '2026-11-28T07:15:00+00:00',
      'next_allowed_at_manila': '2026-11-28 15:15',
    });
    expect(e.isRetryablePin, isFalse);
    expect(e.userMessage, contains('Nov 28, 2026, 3:15 PM'));
  });

  test('NOT_ADMIN and PIN_FORMAT use fixed messages', () {
    expect(
      parse({'code': 'NOT_ADMIN', 'message': 'x'}).userMessage,
      'Only the admin account can do this.',
    );
    expect(
      parse({'code': 'PIN_FORMAT'}).userMessage,
      'The PIN must be exactly 6 digits.',
    );
  });

  test('validation errors show the server message', () {
    expect(
      parse({
        'code': 'INVALID_INPUT',
        'message': 'Price must be a multiple of 5',
      }).userMessage,
      'Price must be a multiple of 5',
    );
    expect(
      parse({'code': 'DB_ERROR', 'sqlstate': '23502'}).userMessage,
      contains('23502'),
    );
  });
}
