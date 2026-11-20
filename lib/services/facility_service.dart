import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/facility.dart';

/// Reads and edits the kiosk's `facilities` and `facility_categories`
/// tables. The kiosk polls these tables, so edits reach it within minutes.
class FacilityService {
  FacilityService._internal();

  static final FacilityService _instance = FacilityService._internal();

  factory FacilityService() => _instance;

  static const String _facilitiesTable = 'facilities';
  static const String _categoriesTable = 'facility_categories';
  static const Duration _timeout = Duration(seconds: 20);

  SupabaseClient get _client => Supabase.instance.client;

  static final RegExp facilityCodePattern = RegExp(r'^[A-Z]{2,3}$');

  // ---------------------------------------------------------------------------
  // Validation helpers (shared with the UI)
  // ---------------------------------------------------------------------------

  /// Returns an error message, or null when [code] is a valid new code.
  static String? validateFacilityCode(String code) {
    if (!facilityCodePattern.hasMatch(code)) {
      return 'Code must be 2–3 capital letters (e.g. SW or GYM).';
    }
    return null;
  }

  /// Parses a price typed by the user. Returns null if it isn't a number.
  static num? parsePrice(String text) {
    final cleaned = text.trim().replaceAll(',', '').replaceAll('₱', '');
    if (cleaned.isEmpty) return null;
    final value = num.tryParse(cleaned);
    if (value == null) return null;
    return value == value.roundToDouble() ? value.toInt() : value;
  }

  /// Returns an error message, or null when [price] is allowed.
  static String? validatePrice(num? price) {
    if (price == null) return 'Enter a price.';
    if (price <= 0) return 'Price must be more than ₱0.';
    if (price % 5 != 0) return 'Price must be a multiple of ₱5.';
    return null;
  }

  static String formatPrice(num price) {
    if (price == price.roundToDouble()) return '₱${price.toInt()}';
    return '₱${price.toStringAsFixed(2)}';
  }

  /// "Senior Citizen (60+)" -> "senior_citizen_60".
  static String categoryCodeFromLabel(String label) {
    return label
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Turns any error into text for the user, keeping Supabase's own message.
  static String errorMessage(Object error) {
    if (error is PostgrestException) {
      final parts = <String>[error.message];
      if (error.details != null && '${error.details}'.isNotEmpty) {
        parts.add('${error.details}');
      }
      if (error.hint != null && error.hint!.isNotEmpty) {
        parts.add('Hint: ${error.hint}');
      }
      final text = parts.join('\n');
      if (error.code == '23505') {
        return 'That code is already used.\n$text';
      }
      if (error.code == '23514') {
        return 'The database rejected a value.\n$text';
      }
      if (error.code == '23503') {
        return 'This row is still referenced elsewhere.\n$text';
      }
      if (error.code == '42501') {
        return 'Not allowed. Sign in again and retry.\n$text';
      }
      return text;
    }
    if (error is AuthException) return error.message;
    if (error is SocketException) {
      return 'No internet connection. Connect and try again.';
    }
    if (error is TimeoutException) {
      return 'The server took too long to respond. Try again.';
    }
    if (error is FacilityException) return error.message;
    return error.toString();
  }

  String get _now => DateTime.now().toUtc().toIso8601String();

  // ---------------------------------------------------------------------------
  // Facilities
  // ---------------------------------------------------------------------------

  Future<List<Facility>> getFacilities() async {
    final rows = await _client
        .from(_facilitiesTable)
        .select()
        .order('sort_order', ascending: true)
        .order('code', ascending: true)
        .timeout(_timeout);
    return rows.map(Facility.fromMap).toList();
  }

  /// Creates a facility together with its first category. If the category
  /// can't be saved, the new facility is removed again so the kiosk never
  /// sees a facility without prices.
  Future<void> addFacility({
    required String code,
    required String name,
    required String type,
    required String firstCategoryLabel,
    required num firstCategoryPrice,
  }) async {
    final codeError = validateFacilityCode(code);
    if (codeError != null) throw FacilityException(codeError);
    if (name.trim().isEmpty) throw FacilityException('Enter a name.');
    if (!Facility.types.contains(type)) {
      throw FacilityException('Choose a type.');
    }
    final categoryRow = _newCategoryRow(
      facilityCode: code,
      label: firstCategoryLabel,
      price: firstCategoryPrice,
      sortOrder: 1,
    );

    final existing = await _client
        .from(_facilitiesTable)
        .select('code, sort_order')
        .order('sort_order', ascending: false)
        .timeout(_timeout);
    if (existing.any((row) => row['code'] == code)) {
      throw FacilityException('A facility with code $code already exists.');
    }
    final maxOrder = existing.isEmpty
        ? 0
        : (existing.first['sort_order'] as num?)?.toInt() ?? 0;

    await _client
        .from(_facilitiesTable)
        .insert({
          'code': code,
          'name': name.trim(),
          'type': type,
          'is_active': true,
          'sort_order': maxOrder + 1,
          'updated_at': _now,
        })
        .timeout(_timeout);

    try {
      await _client
          .from(_categoriesTable)
          .insert(categoryRow)
          .timeout(_timeout);
    } catch (error) {
      try {
        await _client
            .from(_facilitiesTable)
            .delete()
            .eq('code', code)
            .timeout(_timeout);
      } catch (_) {
        throw FacilityException(
          'Facility $code was created but its first category could not be '
          'saved (${errorMessage(error)}). Open the facility and add a '
          'category, or delete it.',
        );
      }
      rethrow;
    }
  }

  Future<void> updateFacility({
    required String code,
    required String name,
    required String type,
  }) async {
    if (name.trim().isEmpty) throw FacilityException('Enter a name.');
    if (!Facility.types.contains(type)) {
      throw FacilityException('Choose a type.');
    }
    await _updateFacilityRow(code, {'name': name.trim(), 'type': type});
  }

  Future<void> setFacilityActive(String code, bool isActive) {
    return _updateFacilityRow(code, {'is_active': isActive});
  }

  Future<void> _updateFacilityRow(
    String code,
    Map<String, dynamic> values,
  ) async {
    final rows = await _client
        .from(_facilitiesTable)
        .update({...values, 'updated_at': _now})
        .eq('code', code)
        .select('code')
        .timeout(_timeout);
    if (rows.isEmpty) {
      throw FacilityException(
        'Facility $code was not found. It may have been deleted.',
      );
    }
  }

  /// Deletes the facility; its categories are removed by the cascade.
  Future<void> deleteFacility(String code) async {
    final rows = await _client
        .from(_facilitiesTable)
        .delete()
        .eq('code', code)
        .select('code')
        .timeout(_timeout);
    if (rows.isEmpty) {
      throw FacilityException(
        'Facility $code was not deleted. It may already be gone.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------

  Future<List<FacilityCategory>> getCategories(String facilityCode) async {
    final rows = await _client
        .from(_categoriesTable)
        .select()
        .eq('facility_code', facilityCode)
        .order('sort_order', ascending: true)
        .order('code', ascending: true)
        .timeout(_timeout);
    return rows.map(FacilityCategory.fromMap).toList();
  }

  /// Builds a validated insert row for a new category.
  Map<String, dynamic> _newCategoryRow({
    required String facilityCode,
    required String label,
    required num price,
    required int sortOrder,
  }) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) throw FacilityException('Enter a category label.');
    final code = categoryCodeFromLabel(trimmed);
    if (code.isEmpty) {
      throw FacilityException(
        'The category label needs at least one letter or digit.',
      );
    }
    final priceError = validatePrice(price);
    if (priceError != null) throw FacilityException(priceError);
    return {
      'facility_code': facilityCode,
      'code': code,
      'label': trimmed,
      'price': price,
      'is_active': true,
      'sort_order': sortOrder,
      'updated_at': _now,
    };
  }

  Future<void> addCategory({
    required String facilityCode,
    required String label,
    required num price,
  }) async {
    final row = _newCategoryRow(
      facilityCode: facilityCode,
      label: label,
      price: price,
      sortOrder: 0,
    );
    final code = row['code'] as String;

    final existing = await _client
        .from(_categoriesTable)
        .select('code, sort_order')
        .eq('facility_code', facilityCode)
        .order('sort_order', ascending: false)
        .timeout(_timeout);
    if (existing.any((r) => r['code'] == code)) {
      throw FacilityException(
        'A category with code "$code" already exists in this facility.',
      );
    }
    row['sort_order'] = existing.isEmpty
        ? 1
        : ((existing.first['sort_order'] as num?)?.toInt() ?? 0) + 1;

    await _client.from(_categoriesTable).insert(row).timeout(_timeout);
  }

  /// Message shown when the last active category of an active facility
  /// would be hidden or deleted.
  static const String lastActiveCategoryMessage =
      'This is the last active category of an active facility. The kiosk '
      'would have nothing to sell. Hide the facility instead.';

  /// Throws if removing [code] would leave an active facility with no
  /// active categories. Checked against the server, not the local list.
  Future<void> _ensureNotLastActiveCategory(
    String facilityCode,
    String code,
  ) async {
    final facility = await _client
        .from(_facilitiesTable)
        .select('is_active')
        .eq('code', facilityCode)
        .maybeSingle()
        .timeout(_timeout);
    if (facility == null || facility['is_active'] == false) return;

    final otherActive = await _client
        .from(_categoriesTable)
        .select('code')
        .eq('facility_code', facilityCode)
        .eq('is_active', true)
        .neq('code', code)
        .limit(1)
        .timeout(_timeout);
    if (otherActive.isEmpty) {
      throw FacilityException(lastActiveCategoryMessage);
    }
  }

  Future<void> updateCategory({
    required String facilityCode,
    required String code,
    required String label,
    required num price,
  }) async {
    if (label.trim().isEmpty) throw FacilityException('Enter a label.');
    final priceError = validatePrice(price);
    if (priceError != null) throw FacilityException(priceError);
    await _updateCategoryRow(facilityCode, code, {
      'label': label.trim(),
      'price': price,
    });
  }

  Future<void> setCategoryActive(
    String facilityCode,
    String code,
    bool isActive,
  ) async {
    if (!isActive) await _ensureNotLastActiveCategory(facilityCode, code);
    await _updateCategoryRow(facilityCode, code, {'is_active': isActive});
  }

  Future<void> _updateCategoryRow(
    String facilityCode,
    String code,
    Map<String, dynamic> values,
  ) async {
    final rows = await _client
        .from(_categoriesTable)
        .update({...values, 'updated_at': _now})
        .eq('facility_code', facilityCode)
        .eq('code', code)
        .select('code')
        .timeout(_timeout);
    if (rows.isEmpty) {
      throw FacilityException(
        'Category "$code" was not found. It may have been deleted.',
      );
    }
  }

  Future<void> deleteCategory(String facilityCode, String code) async {
    final current = await _client
        .from(_categoriesTable)
        .select('is_active')
        .eq('facility_code', facilityCode)
        .eq('code', code)
        .maybeSingle()
        .timeout(_timeout);
    // Deleting an already-hidden category never changes what the kiosk sells.
    if (current != null && current['is_active'] != false) {
      await _ensureNotLastActiveCategory(facilityCode, code);
    }
    final rows = await _client
        .from(_categoriesTable)
        .delete()
        .eq('facility_code', facilityCode)
        .eq('code', code)
        .select('code')
        .timeout(_timeout);
    if (rows.isEmpty) {
      throw FacilityException(
        'Category "$code" was not deleted. It may already be gone.',
      );
    }
  }
}

class FacilityException implements Exception {
  final String message;

  FacilityException(this.message);

  @override
  String toString() => message;
}
