import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/facility.dart';
import '../services/facility_service.dart';
import '../widgets/kiosk_widgets.dart';

/// Categories and prices of one facility.
class FacilityDetailScreen extends StatefulWidget {
  final Facility facility;

  const FacilityDetailScreen({required this.facility, super.key});

  @override
  State<FacilityDetailScreen> createState() => _FacilityDetailScreenState();
}

class _FacilityDetailScreenState extends State<FacilityDetailScreen> {
  final FacilityService _service = FacilityService();
  List<FacilityCategory> _categories = const [];
  bool _isLoading = true;
  String? _error;

  Facility get _facility => widget.facility;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _categories.isEmpty;
      _error = null;
    });
    try {
      final categories = await _service.getCategories(_facility.code);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = FacilityService.errorMessage(error);
        _isLoading = false;
      });
    }
  }

  /// True when [category] is the only active category of an active facility.
  bool _isLastActive(FacilityCategory category) {
    if (!_facility.isActive || !category.isActive) return false;
    return !_categories.any((c) => c.isActive && c.code != category.code);
  }

  Future<bool> _blockIfLastActive(FacilityCategory category) async {
    if (!_isLastActive(category)) return false;
    await showKioskMessage(
      context,
      title: 'Can’t remove the last category',
      message:
          '"${category.label}" is the last active category of ${_facility.name}. '
          'The kiosk would have nothing to sell.\n\n'
          'To stop selling ${_facility.name}, hide the facility instead '
          '(Kiosk tab → ⋮ → Hide).',
    );
    return true;
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (!mounted) return;
      showKioskSnack(context, successMessage);
    } catch (error) {
      if (!mounted) return;
      final message = FacilityService.errorMessage(error);
      if (message == FacilityService.lastActiveCategoryMessage) {
        await showKioskMessage(
          context,
          title: 'Can’t remove the last category',
          message: message,
        );
      } else {
        showKioskSnack(context, message, error: true);
      }
    }
    await _load();
  }

  Future<void> _addCategory() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CategoryFormDialog(
        facilityCode: _facility.code,
        takenCodes: _categories.map((c) => c.code).toSet(),
      ),
    );
    if (saved == true && mounted) {
      showKioskSnack(context, 'Category added.');
      await _load();
    }
  }

  Future<void> _editCategory(FacilityCategory category) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CategoryFormDialog(facilityCode: _facility.code, category: category),
    );
    if (saved == true && mounted) {
      showKioskSnack(context, 'Category updated.');
      await _load();
    }
  }

  Future<void> _toggleActive(FacilityCategory category) async {
    final show = !category.isActive;
    if (!show && await _blockIfLastActive(category)) return;
    await _runAction(
      () => _service.setCategoryActive(_facility.code, category.code, show),
      show ? '${category.label} is now shown.' : '${category.label} is hidden.',
    );
  }

  Future<void> _deleteCategory(FacilityCategory category) async {
    if (await _blockIfLastActive(category)) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          "Delete ${category.label}? This can't be undone. Past sales are kept.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runAction(
      () => _service.deleteCategory(_facility.code, category.code),
      '${category.label} deleted.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_facility.name),
        elevation: 0,
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _addCategory,
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
      body: Column(
        children: [
          const KioskSyncNote(),
          _buildFacilityHeader(),
          Expanded(
            child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
          ),
        ],
      ),
    );
  }

  Widget _buildFacilityHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Text(
            _facility.code,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              Facility.typeLabel(_facility.type),
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ActiveBadge(isActive: _facility.isActive),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _categories.isEmpty) {
      return KioskErrorView(
        title: 'Could not load categories',
        message: _error!,
        onRetry: _load,
      );
    }
    if (_categories.isEmpty) {
      return const KioskEmptyView(
        icon: Icons.sell_outlined,
        title: 'No categories yet',
        message: 'Tap "Add category" to add a price.',
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade100),
            ),
            child: Text(
              'Could not refresh: $_error',
              style: TextStyle(color: Colors.red.shade800),
            ),
          ),
        if (_facility.isActive && !_categories.any((c) => c.isActive))
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Text(
              'This facility is active but has no active categories. '
              'Show a category or hide the facility.',
              style: TextStyle(color: Colors.orange.shade800),
            ),
          ),
        for (final category in _categories) _buildCategoryCard(category),
      ],
    );
  }

  Widget _buildCategoryCard(FacilityCategory category) {
    return Opacity(
      opacity: category.isActive ? 1 : 0.65,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppTheme.softShadow,
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: () => _editCategory(category),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            title: Text(
              category.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ActiveBadge(isActive: category.isActive),
                  Text(category.code),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  FacilityService.formatPrice(category.price),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryDark,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Actions',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _editCategory(category);
                      case 'toggle':
                        _toggleActive(category);
                      case 'delete':
                        _deleteCategory(category);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: ListTile(
                        leading: Icon(
                          category.isActive
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        title: Text(category.isActive ? 'Hide' : 'Show'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(
                          Icons.delete_outline,
                          color: Colors.red.shade700,
                        ),
                        title: Text(
                          'Delete',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Add (when [category] is null) or edit a category. Saves itself and pops
/// `true` on success; a price change is confirmed first.
class CategoryFormDialog extends StatefulWidget {
  final String facilityCode;
  final FacilityCategory? category;
  final Set<String> takenCodes;

  const CategoryFormDialog({
    required this.facilityCode,
    this.category,
    this.takenCodes = const {},
    super.key,
  });

  @override
  State<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _priceController;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.category == null;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _labelController = TextEditingController(text: category?.label ?? '');
    _priceController = TextEditingController(
      text: category == null
          ? ''
          : FacilityService.formatPrice(category.price).substring(1),
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final price = FacilityService.parsePrice(_priceController.text)!;
    final category = widget.category;

    if (category != null && price != category.price) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Change price?'),
          content: Text(
            '${category.label}\n\n'
            'Old ${FacilityService.formatPrice(category.price)} → '
            'new ${FacilityService.formatPrice(price)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Change price'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final service = FacilityService();
    try {
      if (category == null) {
        await service.addCategory(
          facilityCode: widget.facilityCode,
          label: _labelController.text,
          price: price,
        );
      } else {
        await service.updateCategory(
          facilityCode: widget.facilityCode,
          code: category.code,
          label: _labelController.text,
          price: price,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = FacilityService.errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _isNew
        ? FacilityService.categoryCodeFromLabel(_labelController.text)
        : widget.category!.code;

    return AlertDialog(
      title: Text(_isNew ? 'Add category' : 'Edit category'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _labelController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Label',
                    hintText: 'e.g. Adult',
                    helperText: code.isEmpty
                        ? null
                        : _isNew
                        ? 'Code: $code'
                        : 'Code: $code (can’t be changed)',
                  ),
                  onChanged: _isNew ? (_) => setState(() {}) : null,
                  validator: (value) {
                    final label = (value ?? '').trim();
                    if (label.isEmpty) return 'Enter a label.';
                    if (_isNew) {
                      final newCode = FacilityService.categoryCodeFromLabel(
                        label,
                      );
                      if (newCode.isEmpty) {
                        return 'Use at least one letter or digit.';
                      }
                      if (widget.takenCodes.contains(newCode)) {
                        return 'Code "$newCode" already exists here.';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    prefixText: '₱ ',
                    helperText: 'More than 0, in steps of 5.',
                  ),
                  validator: (value) => FacilityService.validatePrice(
                    FacilityService.parsePrice(value ?? ''),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  SelectableText(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
