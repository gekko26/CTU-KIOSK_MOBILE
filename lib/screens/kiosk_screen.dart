import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/facility.dart';
import '../services/facility_service.dart';
import '../widgets/kiosk_widgets.dart';
import 'facility_detail_screen.dart';

/// Kiosk tab: manage the facilities the kiosk sells and their prices.
class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  final FacilityService _service = FacilityService();
  List<Facility> _facilities = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _facilities.isEmpty;
      _error = null;
    });
    try {
      final facilities = await _service.getFacilities();
      if (!mounted) return;
      setState(() {
        _facilities = facilities;
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
      showKioskSnack(context, FacilityService.errorMessage(error), error: true);
    }
    await _load();
  }

  Future<void> _addFacility() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FacilityFormDialog(
        takenCodes: _facilities.map((f) => f.code).toSet(),
      ),
    );
    if (saved == true && mounted) {
      showKioskSnack(context, 'Facility added.');
      await _load();
    }
  }

  Future<void> _editFacility(Facility facility) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FacilityFormDialog(facility: facility),
    );
    if (saved == true && mounted) {
      showKioskSnack(context, 'Facility updated.');
      await _load();
    }
  }

  Future<void> _toggleActive(Facility facility) {
    final show = !facility.isActive;
    return _runAction(
      () => _service.setFacilityActive(facility.code, show),
      show ? '${facility.name} is now shown.' : '${facility.name} is hidden.',
    );
  }

  Future<void> _deleteFacility(Facility facility) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete facility?'),
        content: Text(
          "Delete ${facility.name}? This can't be undone. Past sales are kept."
          '${facility.isActive ? '\n\nYou can hide it instead, so the kiosk stops showing it but you can bring it back later.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Cancel'),
          ),
          if (facility.isActive)
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop('hide'),
              child: const Text('Hide'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () => Navigator.of(dialogContext).pop('delete'),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (choice == 'hide') {
      await _toggleActive(facility);
    } else if (choice == 'delete') {
      await _runAction(
        () => _service.deleteFacility(facility.code),
        '${facility.name} deleted.',
      );
    }
  }

  Future<void> _openFacility(Facility facility) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacilityDetailScreen(facility: facility),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Kiosk'),
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
        onPressed: _isLoading ? null : _addFacility,
        icon: const Icon(Icons.add),
        label: const Text('Add facility'),
      ),
      body: Column(
        children: [
          const KioskSyncNote(),
          Expanded(
            child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _facilities.isEmpty) {
      return KioskErrorView(
        title: 'Could not load facilities',
        message: _error!,
        onRetry: _load,
      );
    }
    if (_facilities.isEmpty) {
      return const KioskEmptyView(
        icon: Icons.storefront_outlined,
        title: 'No facilities yet',
        message: 'Tap "Add facility" to create the first one.',
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _facilities.length + (_error != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (_error != null) {
          if (index == 0) return _buildInlineError(_error!);
          index -= 1;
        }
        return _buildFacilityCard(_facilities[index]);
      },
    );
  }

  Widget _buildInlineError(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Text(
        'Could not refresh: $message',
        style: TextStyle(color: Colors.red.shade800),
      ),
    );
  }

  Widget _buildFacilityCard(Facility facility) {
    return Opacity(
      opacity: facility.isActive ? 1 : 0.65,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppTheme.softShadow,
        ),
        child: ListTile(
          onTap: () => _openFacility(facility),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          leading: CircleAvatar(
            backgroundColor: Colors.blue.shade50,
            foregroundColor: Colors.blue.shade700,
            child: Text(
              facility.code,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(
            facility.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ActiveBadge(isActive: facility.isActive),
                Text(Facility.typeLabel(facility.type)),
              ],
            ),
          ),
          trailing: PopupMenuButton<String>(
            tooltip: 'Actions',
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _editFacility(facility);
                case 'toggle':
                  _toggleActive(facility);
                case 'delete':
                  _deleteFacility(facility);
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
                    facility.isActive ? Icons.visibility_off : Icons.visibility,
                  ),
                  title: Text(facility.isActive ? 'Hide' : 'Show'),
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
        ),
      ),
    );
  }
}

/// Add (when [facility] is null) or edit a facility. Saves itself and pops
/// `true` on success; Supabase errors are shown inside the dialog.
class FacilityFormDialog extends StatefulWidget {
  final Facility? facility;
  final Set<String> takenCodes;

  const FacilityFormDialog({
    this.facility,
    this.takenCodes = const {},
    super.key,
  });

  @override
  State<FacilityFormDialog> createState() => _FacilityFormDialogState();
}

class _FacilityFormDialogState extends State<FacilityFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  final _categoryLabelController = TextEditingController();
  final _categoryPriceController = TextEditingController();
  String? _type;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.facility == null;

  @override
  void initState() {
    super.initState();
    final facility = widget.facility;
    _codeController = TextEditingController(text: facility?.code ?? '');
    _nameController = TextEditingController(text: facility?.name ?? '');
    _type = Facility.types.contains(facility?.type) ? facility!.type : null;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _categoryLabelController.dispose();
    _categoryPriceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final service = FacilityService();
    try {
      if (_isNew) {
        await service.addFacility(
          code: _codeController.text.trim(),
          name: _nameController.text,
          type: _type!,
          firstCategoryLabel: _categoryLabelController.text,
          firstCategoryPrice: FacilityService.parsePrice(
            _categoryPriceController.text,
          )!,
        );
      } else {
        await service.updateFacility(
          code: widget.facility!.code,
          name: _nameController.text,
          type: _type!,
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
    final categoryCode = FacilityService.categoryCodeFromLabel(
      _categoryLabelController.text,
    );

    return AlertDialog(
      title: Text(_isNew ? 'Add facility' : 'Edit facility'),
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
                  controller: _codeController,
                  enabled: _isNew && !_saving,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                  decoration: InputDecoration(
                    labelText: 'Code',
                    hintText: 'e.g. SW',
                    helperText: _isNew
                        ? '2–3 capital letters. Can’t be changed later.'
                        : 'Code can’t be changed.',
                  ),
                  onChanged: (value) {
                    final upper = value.toUpperCase();
                    if (upper != value) {
                      _codeController.value = _codeController.value.copyWith(
                        text: upper,
                      );
                    }
                  },
                  validator: (value) {
                    if (!_isNew) return null;
                    final code = (value ?? '').trim();
                    final error = FacilityService.validateFacilityCode(code);
                    if (error != null) return error;
                    if (widget.takenCodes.contains(code)) {
                      return 'Code $code is already used.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Enter a name.' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final type in Facility.types)
                      DropdownMenuItem(
                        value: type,
                        child: Text(Facility.typeLabel(type)),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _type = value),
                  validator: (value) => value == null ? 'Choose a type.' : null,
                ),
                if (!_isNew &&
                    !Facility.types.contains(widget.facility!.type)) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Current type "${widget.facility!.type}" is not supported. '
                    'Choose one of the types above.',
                    style: TextStyle(color: Colors.orange.shade800),
                  ),
                ],
                if (_isNew) ...[
                  const SizedBox(height: 20),
                  Text(
                    'First category',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'A facility needs at least one price. You can add more '
                    'after saving.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _categoryLabelController,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Category label',
                      hintText: 'e.g. Adult',
                      helperText: categoryCode.isEmpty
                          ? null
                          : 'Code: $categoryCode',
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Enter a category label.';
                      }
                      if (FacilityService.categoryCodeFromLabel(
                        value!,
                      ).isEmpty) {
                        return 'Use at least one letter or digit.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _categoryPriceController,
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
                ],
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
