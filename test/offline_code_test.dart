import 'package:ctu_kiosk_mobile/services/offline_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches the kiosk test vector (leading zero kept)', () {
    expect(
      offlineApprovalCode(
        secret: 'ctu-kiosk-test-secret',
        requestCode: 'C-4821',
        amount: 150,
      ),
      '011621',
    );
  });

  test('150 and 150.00 give the same code', () {
    String code(num amount) => offlineApprovalCode(
      secret: 'ctu-kiosk-test-secret',
      requestCode: 'C-4821',
      amount: amount,
    );
    expect(code(150.0), code(150));
  });
}
