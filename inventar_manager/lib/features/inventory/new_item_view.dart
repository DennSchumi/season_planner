import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/flight_school_service.dart';
import 'package:inventar_manager/core/theme.dart';
import 'package:inventar_manager/core/widgets/ui_primitives.dart';
import 'package:intl/intl.dart';

class BatchItemEntry {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController serialCtrl = TextEditingController();
  final TextEditingController materialNrCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    serialCtrl.dispose();
    materialNrCtrl.dispose();
  }
}

class NewItemView extends StatefulWidget {
  const NewItemView({super.key});

  @override
  _NewItemViewState createState() => _NewItemViewState();
}

class _NewItemViewState extends State<NewItemView> {
  final _formKey = GlobalKey<FormState>();

  bool _isBatchMode = false;

  // Single mode controllers
  final _nameController = TextEditingController();
  final _serialController = TextEditingController();
  final _materialNrController = TextEditingController();

  // Batch mode entries
  final List<BatchItemEntry> _batchItems = [BatchItemEntry()];

  DateTime _serviceStartDate = DateTime.now();

  final CategoryService _categoryService = CategoryService();
  final ItemService _itemService = ItemService();
  CategoryModel? _selectedCategory;

  @override
  void initState() {
    super.initState();
    if (_categoryService.categories.isNotEmpty) {
      _selectedCategory = _categoryService.categories.first;
      _updateMaterialNumberPrefix();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serialController.dispose();
    _materialNrController.dispose();
    for (var entry in _batchItems) {
      entry.dispose();
    }
    super.dispose();
  }

  String _applyPrefix(String currentText) {
    if (_selectedCategory == null) return currentText;
    final prefix = _selectedCategory!.prefix;
    if (currentText.isEmpty || currentText.length <= 2) {
      return prefix;
    } else {
      final regex = RegExp(r'^[A-Z]+');
      if (regex.hasMatch(currentText)) {
        return currentText.replaceFirst(regex, prefix);
      } else {
        return prefix + currentText;
      }
    }
  }

  void _updateMaterialNumberPrefix() {
    if (_selectedCategory != null) {
      _materialNrController.text = _applyPrefix(_materialNrController.text);
      for (var entry in _batchItems) {
        if (entry.materialNrCtrl.text.isEmpty ||
            entry.materialNrCtrl.text == _selectedCategory!.prefix) {
          entry.materialNrCtrl.text = _selectedCategory!.prefix;
        } else {
          entry.materialNrCtrl.text = _applyPrefix(entry.materialNrCtrl.text);
        }
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _serviceStartDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _serviceStartDate) {
      setState(() {
        _serviceStartDate = picked;
      });
    }
  }

  void _saveData() async {
    if (!_formKey.currentState!.validate()) return;

    final schoolId = FlightSchoolService().selectedSchool?.id;
    if (schoolId == null) return;

    // Check duplicates across DB and current batch
    final allMatNrs = _isBatchMode
        ? _batchItems
              .map((e) => e.materialNrCtrl.text.trim().toLowerCase())
              .toList()
        : [_materialNrController.text.trim().toLowerCase()];

    // Check for internal duplicates in batch
    if (allMatNrs.toSet().length != allMatNrs.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Fehler: Doppelte Gerätenummern in der Sammelerfassung!",
          ),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final hasDbDuplicate = _itemService.items.any(
      (item) => allMatNrs.contains(item.materialNumber.toLowerCase()),
    );
    if (hasDbDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Fehler: Mindestens eine Gerätenummer existiert bereits!",
          ),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    // Build Items
    List<ItemModel> itemsToSave = [];
    final nextServiceDate = _serviceStartDate.add(
      Duration(days: _selectedCategory!.serviceIntervalMonths * 30),
    );

    if (_isBatchMode) {
      for (var entry in _batchItems) {
        itemsToSave.add(
          ItemModel(
            id: '',
            schoolId: schoolId,
            categoryId: _selectedCategory!.id,
            materialNumber: entry.materialNrCtrl.text.trim(),
            name: entry.nameCtrl.text.trim(),
            serialNumber: entry.serialCtrl.text.trim(),
            status: 'in_stock',
            lastServiceDate: _serviceStartDate,
            nextServiceDate: nextServiceDate,
          ),
        );
      }
    } else {
      itemsToSave.add(
        ItemModel(
          id: '',
          schoolId: schoolId,
          categoryId: _selectedCategory!.id,
          materialNumber: _materialNrController.text.trim(),
          name: _nameController.text.trim(),
          serialNumber: _serialController.text.trim(),
          status: 'in_stock',
          lastServiceDate: _serviceStartDate,
          nextServiceDate: nextServiceDate,
        ),
      );
    }

    // Save all
    bool success = true;
    for (var item in itemsToSave) {
      final res = await _itemService.addItem(item);
      if (res == null) success = false;
    }

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${itemsToSave.length} Gegenstand/Gegenstände erfolgreich gespeichert!",
            ),
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Fehler beim Speichern in der Datenbank."),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_categoryService.categories.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Neuer Gegenstand")),
        body: const Center(
          child: Text("Bitte zuerst Kategorien in den Einstellungen anlegen!"),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Neuer Gegenstand")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _isBatchMode ? 800 : 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildModeToggle(),
                  const SizedBox(height: 18),
                  _buildGeneralSettings(),
                  const SizedBox(height: 18),
                  if (_isBatchMode) _buildBatchForm() else _buildSingleForm(),
                  const SizedBox(height: 24),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: AppTheme.primaryGlow,
                    ),
                    child: SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _saveData,
                        child: Text(
                          _isBatchMode
                              ? "Alle speichern (${_batchItems.length})"
                              : "Gegenstand anlegen",
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = isDark
        ? AppTheme.primaryColor.withValues(alpha: 0.20)
        : AppTheme.primaryTint;
    final activeFg = isDark ? AppTheme.darkPrimary : AppTheme.primaryColor;

    return SoftCard(
      radius: 16,
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isBatchMode = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_isBatchMode ? activeBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  "Einzelerfassung",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: !_isBatchMode ? activeFg : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isBatchMode = true;
                  if (_batchItems.isEmpty) {
                    final entry = BatchItemEntry();
                    entry.materialNrCtrl.text = _selectedCategory?.prefix ?? '';
                    _batchItems.add(entry);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _isBatchMode ? activeBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  "Sammelerfassung",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _isBatchMode ? activeFg : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralSettings() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SoftCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Allgemeine Einstellungen",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<CategoryModel>(
            decoration: const InputDecoration(labelText: "Kategorie"),
            initialValue: _selectedCategory,
            items: _categoryService.categories
                .map(
                  (c) => DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [
                        c.buildIcon(color: cs.onSurfaceVariant, size: 20),
                        const SizedBox(width: 8),
                        Text(c.name),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) {
              setState(() {
                _selectedCategory = val;
                _updateMaterialNumberPrefix();
              });
            },
            validator: (val) => val == null ? "Bitte Kategorie wählen" : null,
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () => _selectDate(context),
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Intervallbeginn (Letzter Service)',
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('dd.MM.yyyy').format(_serviceStartDate),
                    style: const TextStyle(fontSize: 15),
                  ),
                  Icon(Icons.calendar_today_rounded,
                      size: 19, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (_selectedCategory != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.primaryColor.withValues(alpha: 0.16)
                    : AppTheme.primaryTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: isDark ? AppTheme.darkPrimary : AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Service-Intervall für ${_selectedCategory!.name}: ${_selectedCategory!.serviceIntervalMonths} Monate.\nNächster Service: ${DateFormat('dd.MM.yyyy').format(_serviceStartDate.add(Duration(days: _selectedCategory!.serviceIntervalMonths * 30)))}",
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? cs.onSurface : AppTheme.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSingleForm() {
    return SoftCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Gegenstandsdaten",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _materialNrController,
            decoration: const InputDecoration(
              labelText: "Gerätenummer (Material-ID)",
            ),
            validator: (val) =>
                val == null || val.isEmpty ? "Pflichtfeld" : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: "Modell / Name"),
            validator: (val) =>
                val == null || val.isEmpty ? "Pflichtfeld" : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _serialController,
            decoration: const InputDecoration(
              labelText: "Seriennummer (Optional)",
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchForm() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SoftCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Gegenstandsdaten",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    final entry = BatchItemEntry();
                    entry.materialNrCtrl.text = _selectedCategory?.prefix ?? '';
                    if (_batchItems.isNotEmpty) {
                      entry.nameCtrl.text = _batchItems.last.nameCtrl.text;
                    }
                    _batchItems.add(entry);
                  });
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text("Zeile hinzufügen"),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _batchItems.length,
            separatorBuilder: (context, index) => const Divider(height: 28),
            itemBuilder: (context, index) {
              final entry = _batchItems[index];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(top: 10, right: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.darkCardElevated
                          : AppTheme.primaryTint,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "${index + 1}",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkPrimary
                            : AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: entry.materialNrCtrl,
                          decoration: const InputDecoration(
                            labelText: "Gerätenummer",
                            isDense: true,
                          ),
                          validator: (val) =>
                              val == null || val.isEmpty ? "Pflichtfeld" : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: entry.nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Modell / Name",
                                  isDense: true,
                                ),
                                validator: (val) => val == null || val.isEmpty
                                    ? "Pflichtfeld"
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: entry.serialCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Seriennummer",
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_batchItems.length > 1)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      child: IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: cs.error,
                        ),
                        onPressed: () {
                          setState(() {
                            entry.dispose();
                            _batchItems.removeAt(index);
                          });
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
