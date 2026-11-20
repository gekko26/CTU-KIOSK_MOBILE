/// A kiosk facility (row of the `facilities` table).
class Facility {
  /// The only facility types the kiosk understands.
  static const List<String> types = [
    'age_based',
    'membership_based',
    'special_category_based',
    'quantity_based',
  ];

  static String typeLabel(String type) {
    switch (type) {
      case 'age_based':
        return 'Age based';
      case 'membership_based':
        return 'Membership based';
      case 'special_category_based':
        return 'Special category based';
      case 'quantity_based':
        return 'Quantity based';
      default:
        return type;
    }
  }

  final String code;
  final String name;
  final String type;
  final bool isActive;
  final int sortOrder;
  final DateTime? updatedAt;

  const Facility({
    required this.code,
    required this.name,
    required this.type,
    required this.isActive,
    required this.sortOrder,
    this.updatedAt,
  });

  factory Facility.fromMap(Map<String, dynamic> map) {
    return Facility(
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      isActive: map['is_active'] != false,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
    );
  }
}

/// A price category inside a facility (row of `facility_categories`).
class FacilityCategory {
  final String facilityCode;
  final String code;
  final String label;
  final num price;
  final bool isActive;
  final int sortOrder;
  final DateTime? updatedAt;

  const FacilityCategory({
    required this.facilityCode,
    required this.code,
    required this.label,
    required this.price,
    required this.isActive,
    required this.sortOrder,
    this.updatedAt,
  });

  factory FacilityCategory.fromMap(Map<String, dynamic> map) {
    final rawPrice = map['price'];
    return FacilityCategory(
      facilityCode: map['facility_code']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      price: rawPrice is num ? rawPrice : num.tryParse('$rawPrice') ?? 0,
      isActive: map['is_active'] != false,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
    );
  }
}
