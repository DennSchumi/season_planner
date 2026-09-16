import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/flight_school_service.dart';

class NewItemView extends StatefulWidget {
  const NewItemView({Key? key}) : super(key: key);

  @override
  _NewItemViewState createState() => _NewItemViewState();
}

class _NewItemViewState extends State<NewItemView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serialController = TextEditingController();
  final _materialNrController = TextEditingController();
  
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
  
  void _updateMaterialNumberPrefix() {
    if (_selectedCategory != null) {
      final currentText = _materialNrController.text;
      // Strip any existing prefix (assuming old categories) and apply new one
      // If empty, just set prefix
      if (currentText.isEmpty || currentText.length <= 2) {
        _materialNrController.text = _selectedCategory!.prefix;
      } else {
        // Find existing letters and replace them
        final regex = RegExp(r'^[A-Z]+');
        if (regex.hasMatch(currentText)) {
          _materialNrController.text = currentText.replaceFirst(regex, _selectedCategory!.prefix);
        } else {
          _materialNrController.text = _selectedCategory!.prefix + currentText;
        }
      }
    }
  }

  void _saveItem() async {
    if (_formKey.currentState!.validate()) {
      final String matNr = _materialNrController.text.trim();
      
      // Check for duplicates
      final isDuplicate = _itemService.items.any((item) => item.materialNumber.toLowerCase() == matNr.toLowerCase());
      if (isDuplicate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Fehler: Diese Gerätenummer existiert bereits!"),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        return;
      }

      final schoolId = FlightSchoolService().selectedSchool?.id;
      if (schoolId == null) return;
      
      final newItem = ItemModel(
        id: '',
        schoolId: schoolId,
        categoryId: _selectedCategory!.id,
        materialNumber: matNr,
        name: _nameController.text.trim(),
        serialNumber: _serialController.text.trim(),
        status: 'in_stock',
        lastServiceDate: DateTime.now(), // default to now
        nextServiceDate: DateTime.now().add(Duration(days: _selectedCategory!.serviceIntervalMonths * 30)),
      );
      
      final createdItem = await _itemService.addItem(newItem);
      if (createdItem != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gegenstand erfolgreich gespeichert!")),
        );
        Navigator.pop(context);
      } else if (mounted) {
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
        body: const Center(child: Text("Bitte zuerst Kategorien in den Einstellungen anlegen!")),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          "Neuer Gegenstand",
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Allgemeine Daten", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                        const SizedBox(height: 24),
                        DropdownButtonFormField<CategoryModel>(
                          decoration: const InputDecoration(labelText: "Kategorie", border: OutlineInputBorder()),
                          value: _selectedCategory,
                          items: _categoryService.categories.map((c) {
                            return DropdownMenuItem(value: c, child: Text(c.name));
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedCategory = val;
                              _updateMaterialNumberPrefix();
                            });
                          },
                          validator: (val) => val == null ? "Bitte Kategorie wählen" : null,
                        ),
                        const SizedBox(height: 16),
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
                          decoration: const InputDecoration(labelText: "Seriennummer", border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 16),
                        if (_selectedCategory != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: Color(0xFF3B82F6)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Service-Intervall für ${_selectedCategory!.name}: ${_selectedCategory!.serviceIntervalMonths} Monate.\nNachweis erforderlich: ${_selectedCategory!.serviceRequiresDocument ? 'Ja' : 'Nein'}",
                                    style: const TextStyle(color: Color(0xFF1E40AF)),
                                  ),
                                ),
                              ],
                            ),
                          )
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _saveItem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("Gegenstand anlegen", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
