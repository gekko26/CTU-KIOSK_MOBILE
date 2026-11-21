/// One row of `cashless_requests`: a customer chose "Pay with QR" on the
/// kiosk and is waiting for staff to check the payment in the bank app.
class CashlessRequest {
  final String id;
  final String requestCode;
  final String facilityCode;
  final double amount;
  final String? refDigits;
  final String status;
  final String? approvalSource;
  final String? verifiedBy;
  final String? verifiedByName;
  final DateTime? verifiedAt;
  final int? localTransactionId;
  final DateTime createdAt;

  const CashlessRequest({
    required this.id,
    required this.requestCode,
    required this.facilityCode,
    required this.amount,
    required this.refDigits,
    required this.status,
    required this.approvalSource,
    required this.verifiedBy,
    required this.verifiedByName,
    required this.verifiedAt,
    required this.localTransactionId,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isExpired => status == 'expired';

  /// Pending and expired requests can still be approved or rejected.
  bool get canReview => isPending || isExpired;

  factory CashlessRequest.fromJson(Map<String, dynamic> json) {
    return CashlessRequest(
      id: json['id'] as String,
      requestCode: json['request_code'] as String,
      facilityCode: json['facility_code'] as String? ?? '',
      amount: double.parse('${json['amount']}'),
      refDigits: json['ref_digits'] as String?,
      status: json['status'] as String,
      approvalSource: json['approval_source'] as String?,
      verifiedBy: json['verified_by'] as String?,
      verifiedByName: json['verified_by_name'] as String?,
      verifiedAt: _parseTime(json['verified_at']),
      localTransactionId: (json['local_transaction_id'] as num?)?.toInt(),
      createdAt: _parseTime(json['created_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseTime(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse('$value')?.toUtc();
  }
}
