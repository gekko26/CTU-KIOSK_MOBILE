import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/facility.dart';
import 'admin_rpc.dart';

/// Reads the kiosk's `facilities` and `facility_categories` tables and edits
/// them through the PIN-protected admin RPCs. The kiosk polls these tables,
/// so edits reach it within minutes.
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
    if (error is AdminRpcException) return error.userMessage;
    if (error is PinCancelledException) return 'Cancelled.';
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

  // ---------------------------------------------------------------------------
  // Facilities
  // ---------------------------------------------------------------------------
  //
  // Reads use the tables directly. Every write goes through a PIN-protected
  // admin RPC (docs/admin-pin.md §4); direct writes are refused by RLS.

  Future<List<Facility>> getFacilities() async {
    final rows = await _client
        .from(_facilitiesTable)
        .select()
        .order('sort_order', ascending: true)
        .order('code', ascending: true)
        .timeout(_timeout);
    return rows.map(Facility.fromMap).toList();
  }

  Future<Map<String, dynamic>> _upsertFacility({
    required String code,
    required String name,
    required String type,
    required bool isActive,
    required int? sortOrder,
    required String pin,
  }) {
    return callAdminRpc('admin_upsert_facility', {
      'p_code': code,
      'p_name': name,
      'p_type': type,
      'p_is_active': isActive,
      'p_sort_order': sortOrder,
      'p_pin': pin,
    });
  }

  /// Checks the new facility's fields before the PIN is asked for.
  /// Throws [FacilityException] with the first problem.
  void validateNewFacility({
    required String code,
    required String name,
    required String type,
    required String firstCategoryLabel,
    required num firstCategoryPrice,
  }) {
    final codeError = validateFacilityCode(code);
    if (codeError != null) throw FacilityException(codeError);
    if (name.trim().isEmpty) throw FacilityException('Enter a name.');
    if (!Facility.types.contains(type)) {
      throw FacilityException('Choose a type.');
    }
    _checkCategoryFields(firstCategoryLabel, firstCategoryPrice);
  }

  /// Creates a facility together with its first category (one PIN for
  /// both). If the category can't be saved, the new facility is deleted
  /// again so the kiosk never sees a facility without prices.
  Future<void> addFacility({
    required String code,
    required String name,
    required String type,
    required String firstCategoryLabel,
    required num firstCategoryPrice,
    required String pin,
  }) async {
    validateNewFacility(
      code: code,
      name: name,
      type: type,
      firstCategoryLabel: firstCategoryLabel,
      firstCategoryPrice: firstCategoryPrice,
    );

    // "Upsert" would overwrite an existing facility, so check first.
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

    await _upsertFacility(
      code: code,
      name: name.trim(),
      type: type,
      isActive: true,
      sortOrder: maxOrder + 1,
      pin: pin,
    );

    try {
      await _upsertCategory(
        facilityCode: code,
        code: categoryCodeFromLabel(firstCategoryLabel),
        label: firstCategoryLabel.trim(),
        price: firstCategoryPrice,
        isActive: true,
        sortOrder: 1,
        pin: pin,
      );
    } catch (error) {
      try {
        await callAdminRpc('admin_delete_facility', {
          'p_code': code,
          'p_pin': pin,
        });
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
    required Facility facility,
    required String name,
    required String pin,
  }) async {
    if (name.trim().isEmpty) throw FacilityException('Enter a name.');
    await _upsertFacility(
      code: facility.code,
      name: name.trim(),
      type: facility.type,
      isActive: facility.isActive,
      sortOrder: facility.sortOrder,
      pin: pin,
    );
  }

  /// Show (true) or hide (false) a facility.
  Future<void> setFacilityActive(
    Facility facility,
    bool isActive,
    String pin,
  ) async {
    await _upsertFacility(
      code: facility.code,
      name: facility.name,
      type: facility.type,
      isActive: isActive,
      sortOrder: facility.sortOrder,
      pin: pin,
    );
  }

  /// Deletes the facility and its categories (done by the RPC).
  Future<void> deleteFacility(String code, String pin) async {
    await callAdminRpc('admin_delete_facility', {'p_code': code, 'p_pin': pin});
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

  Future<Map<String, dynamic>> _upsertCategory({
    required String facilityCode,
    required String code,
    required String label,
    required num price,
    required bool isActive,
    required int? sortOrder,
    required String pin,
  }) {
    return callAdminRpc('admin_upsert_category', {
      'p_facility_code': facilityCode,
      'p_code': code,
      'p_label': label,
      'p_price': price,
      'p_is_active': isActive,
      'p_sort_order': sortOrder,
      'p_pin': pin,
    });
  }

  /// Label and price checks shared by add and edit.
  void _checkCategoryFields(String label, num price) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) throw FacilityException('Enter a category label.');
    if (categoryCodeFromLabel(trimmed).isEmpty) {
      throw FacilityException(
        'The category label needs at least one letter or digit.',
      );
    }
    final priceError = validatePrice(price);
    if (priceError != null) throw FacilityException(priceError);
  }

  Future<void> addCategory({
    required String facilityCode,
    required String label,
    required num price,
    required String pin,
  }) async {
    _checkCategoryFields(label, price);
    final code = categoryCodeFromLabel(label);

    // "Upsert" would overwrite an existing category, so check first.
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
    final sortOrder = existing.isEmpty
        ? 1
        : ((existing.first['sort_order'] as num?)?.toInt() ?? 0) + 1;

    await _upsertCategory(
      facilityCode: facilityCode,
      code: code,
      label: label.trim(),
      price: price,
      isActive: true,
      sortOrder: sortOrder,
      pin: pin,
    );
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

  /// Checks a hide/delete against the server before the PIN is asked for.
  Future<void> checkCanRemoveCategory(FacilityCategory category) async {
    // Removing an already-hidden category never changes what the kiosk sells.
    if (!category.isActive) return;
    await _ensureNotLastActiveCategory(category.facilityCode, category.code);
  }

  Future<void> updateCategory({
    required FacilityCategory category,
    required String label,
    required num price,
    required String pin,
  }) async {
    if (label.trim().isEmpty) throw FacilityException('Enter a label.');
    final priceError = validatePrice(price);
    if (priceError != null) throw FacilityException(priceError);
    await _upsertCategory(
      facilityCode: category.facilityCode,
      code: category.code,
      label: label.trim(),
      price: price,
      isActive: category.isActive,
      sortOrder: category.sortOrder,
      pin: pin,
    );
  }

  /// Show (true) or hide (false) a category.
  Future<void> setCategoryActive(
    FacilityCategory category,
    bool isActive,
    String pin,
  ) async {
    await _upsertCategory(
      facilityCode: category.facilityCode,
      code: category.code,
      label: category.label,
      price: category.price,
      isActive: isActive,
      sortOrder: category.sortOrder,
      pin: pin,
    );
  }

  Future<void> deleteCategory(FacilityCategory category, String pin) async {
    await callAdminRpc('admin_delete_category', {
      'p_facility_code': category.facilityCode,
      'p_code': category.code,
      'p_pin': pin,
    });
  }
}

class FacilityException implements Exception {
  final String message;

  FacilityException(this.message);

  @override
  String toString() => message;
}
