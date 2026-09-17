import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/flight_school_service.dart';
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
  const NewItemView({Key? key}) : super(key: key);

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
        if (entry.materialNrCtrl.text.isEmpty || entry.materialNrCtrl.text == _selectedCategory!.prefix) {
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF3B82F6),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
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
        ? _batchItems.map((e) => e.materialNrCtrl.text.trim().toLowerCase()).toList()
        : [_materialNrController.text.trim().toLowerCase()];
        
    // Check for internal duplicates in batch
    if (allMatNrs.toSet().length != allMatNrs.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fehler: Doppelte Gerätenummern in der Sammelerfassung!"), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }

    final hasDbDuplicate = _itemService.items.any((item) => allMatNrs.contains(item.materialNumber.toLowerCase()));
    if (hasDbDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fehler: Mindestens eine Gerätenummer existiert bereits!"), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }

    // Build Items
    List<ItemModel> itemsToSave = [];
    final nextServiceDate = _serviceStartDate.add(Duration(days: _selectedCategory!.serviceIntervalMonths * 30));

    if (_isBatchMode) {
      for (var entry in _batchItems) {
        itemsToSave.add(ItemModel(
          id: '',
          schoolId: schoolId,
          categoryId: _selectedCategory!.id,
          materialNumber: entry.materialNrCtrl.text.trim(),
          name: entry.nameCtrl.text.trim(),
          serialNumber: entry.serialCtrl.text.trim(),
          status: 'in_stock',
          lastServiceDate: _serviceStartDate,
          nextServiceDate: nextServiceDate,
        ));
      }
    } else {
      itemsToSave.add(ItemModel(
        id: '',
        schoolId: schoolId,
        categoryId: _selectedCategory!.id,
        materialNumber: _materialNrController.text.trim(),
        name: _nameController.text.trim(),
        serialNumber: _serialController.text.trim(),
        status: 'in_stock',
        lastServiceDate: _serviceStartDate,
        nextServiceDate: nextServiceDate,
      ));
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
          SnackBar(content: Text("${itemsToSave.length} Gegenstand/Gegenstände erfolgreich gespeichert!")),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Fehler beim Speichern in der Datenbank."), backgroundColor: Color(0xFFEF4444)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_categoryService.categories.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Neuer Gegenstand")),
        body: const Center(child: Text("Bitte zuerst Kategorien in den Einstellungen anlegen!")),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text("Neuer Gegenstand", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _isBatchMode ? 800 : 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildModeToggle(),
                  const SizedBox(height: 24),
                  _buildGeneralSettings(),
                  const SizedBox(height: 24),
                  if (_isBatchMode) _buildBatchForm() else _buildSingleForm(),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _saveData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(_isBatchMode ? "Alle speichern (${_batchItems.length})" : "Gegenstand anlegen", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isBatchMode = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: !_isBatchMode ? const Color(0xFFEFF6FF) : Colors.transparent,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                  border: Border.all(color: !_isBatchMode ? const Color(0xFF3B82F6) : Colors.transparent, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text("Einzelerfassung", style: TextStyle(fontWeight: FontWeight.bold, color: !_isBatchMode ? const Color(0xFF1D4ED8) : const Color(0xFF64748B))),
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
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _isBatchMode ? const Color(0xFFEFF6FF) : Colors.transparent,
                  borderRadius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
                  border: Border.all(color: _isBatchMode ? const Color(0xFF3B82F6) : Colors.transparent, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text("Sammelerfassung", style: TextStyle(fontWeight: FontWeight.bold, color: _isBatchMode ? const Color(0xFF1D4ED8) : const Color(0xFF64748B))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralSettings() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Allgemeine Einstellungen", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
          const SizedBox(height: 24),
          DropdownButtonFormField<CategoryModel>(
            decoration: const InputDecoration(labelText: "Kategorie", border: OutlineInputBorder()),
            value: _selectedCategory,
            items: _categoryService.categories.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
            onChanged: (val) {
              setState(() {
                _selectedCategory = val;
                _updateMaterialNumberPrefix();
              });
            },
            validator: (val) => val == null ? "Bitte Kategorie wählen" : null,
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () => _selectDate(context),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Intervallbeginn (Letzter Service)', border: OutlineInputBorder()),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(DateFormat('dd.MM.yyyy').format(_serviceStartDate), style: const TextStyle(fontSize: 16)),
                  const Icon(Icons.calendar_today, color: Color(0xFF64748B)),
                ],
              ),
            ),
          ),
          if (_selectedCategory != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF3B82F6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Service-Intervall für ${_selectedCategory!.name}: ${_selectedCategory!.serviceIntervalMonths} Monate.\nNächster Service: ${DateFormat('dd.MM.yyyy').format(_serviceStartDate.add(Duration(days: _selectedCategory!.serviceIntervalMonths * 30)))}",
                      style: const TextStyle(color: Color(0xFF1E40AF)),
                    ),
                  ),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildSingleForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Gegenstandsdaten", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
          const SizedBox(height: 24),
          TextFormField(
            controller: _materialNrController,
            decoration: const InputDecoration(labelText: "Gerätenummer (Material-ID)", border: OutlineInputBorder()),
            validator: (val) => val == null || val.isEmpty ? "Pflichtfeld" : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: "Modell / Name", border: OutlineInputBorder()),
            validator: (val) => val == null || val.isEmpty ? "Pflichtfeld" : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _serialController,
            decoration: const InputDecoration(labelText: "Seriennummer (Optional)", border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Gegenstandsdaten", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    final entry = BatchItemEntry();
                    entry.materialNrCtrl.text = _selectedCategory?.prefix ?? '';
                    // Optional: prefill name with previous entry's name to speed up data entry
                    if (_batchItems.isNotEmpty) {
                      entry.nameCtrl.text = _batchItems.last.nameCtrl.text;
                    }
                    _batchItems.add(entry);
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text("Zeile hinzufügen"),
              )
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _batchItems.length,
            separatorBuilder: (context, index) => const Divider(height: 32),
            itemBuilder: (context, index) {
              final entry = _batchItems[index];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(top: 12, right: 12),
                    decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text("${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: entry.materialNrCtrl,
                          decoration: const InputDecoration(labelText: "Gerätenummer", border: OutlineInputBorder(), isDense: true),
                          validator: (val) => val == null || val.isEmpty ? "Pflichtfeld" : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: entry.nameCtrl,
                                decoration: const InputDecoration(labelText: "Modell / Name", border: OutlineInputBorder(), isDense: true),
                                validator: (val) => val == null || val.isEmpty ? "Pflichtfeld" : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: entry.serialCtrl,
                                decoration: const InputDecoration(labelText: "Seriennummer", border: OutlineInputBorder(), isDense: true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_batchItems.length > 1)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                        onPressed: () {
                          setState(() {
                            entry.dispose();
                            _batchItems.removeAt(index);
                          });
                        },
                      ),
                    )
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
