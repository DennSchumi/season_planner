import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/flight_school_service.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({Key? key}) : super(key: key);

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final CategoryService _categoryService = CategoryService();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _categoryService,
      builder: (context, child) {
        if (_categoryService.isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFFF1F5F9),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final categories = _categoryService.categories;

        return Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Kategorieverwaltung",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showAddCategoryModal(),
                      icon: const Icon(Icons.add),
                      label: const Text("Neue Kategorie"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  "Definiere hier die Präfixe und Service-Einstellungen für jede Kategorie.",
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: categories.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(category.icon, color: const Color(0xFF3B82F6)),
                        ),
                        title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              _buildInfoChip(Icons.tag, "Präfix: ${category.prefix}"),
                              _buildInfoChip(Icons.update, "Intervall: ${category.serviceIntervalMonths} Monate"),
                              _buildInfoChip(
                                category.serviceRequiresDocument ? Icons.upload_file : Icons.edit_document,
                                category.serviceRequiresDocument ? "Dokument nötig" : "Protokoll",
                              ),
                            ],
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: Color(0xFF64748B)),
                          onPressed: () => _showEditCategoryModal(category),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
      },
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
        ],
      ),
    );
  }

  void _showAddCategoryModal() {
    final nameController = TextEditingController();
    final prefixController = TextEditingController();
    final intervalController = TextEditingController(text: "12");
    bool requiresDoc = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: const Text("Neue Kategorie anlegen"),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "Name (z.B. Schwimmwesten)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: prefixController,
                      decoration: const InputDecoration(
                        labelText: "Präfix (z.B. SW, GZ)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Service-Intervall (Monate)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text("Service-Nachweis"),
                      subtitle: Text(requiresDoc ? "Dokument muss hochgeladen werden" : "Nur Text-Protokoll"),
                      value: requiresDoc,
                      onChanged: (val) {
                        setStateModal(() {
                          requiresDoc = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Abbrechen"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newName = nameController.text.trim();
                    final newPrefix = prefixController.text.trim();
                    final newInterval = int.tryParse(intervalController.text.trim()) ?? 12;
                    
                    if (newName.isNotEmpty && newPrefix.isNotEmpty) {
                      final schoolId = FlightSchoolService().selectedSchool?.id;
                      if (schoolId != null) {
                        final newCat = CategoryModel(
                          id: '',
                          schoolId: schoolId,
                          name: newName,
                          prefix: newPrefix,
                          serviceIntervalMonths: newInterval,
                          serviceRequiresDocument: requiresDoc,
                          iconData: 'support', // default icon
                        );
                        
                        await _categoryService.addCategory(newCat);
                        
                        if (mounted) {
                          Navigator.pop(context);
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white),
                  child: const Text("Erstellen"),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _showEditCategoryModal(CategoryModel category) {
    final prefixController = TextEditingController(text: category.prefix);
    final intervalController = TextEditingController(text: category.serviceIntervalMonths.toString());
    bool requiresDoc = category.serviceRequiresDocument;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: Text("Kategorie bearbeiten: ${category.name}"),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: prefixController,
                      decoration: const InputDecoration(
                        labelText: "Präfix (z.B. SW, GZ)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Service-Intervall (Monate)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text("Service-Nachweis"),
                      subtitle: Text(requiresDoc ? "Dokument muss hochgeladen werden" : "Nur Text-Protokoll"),
                      value: requiresDoc,
                      onChanged: (val) {
                        setStateModal(() {
                          requiresDoc = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Abbrechen"),
                ),
                ElevatedButton(
                  onPressed: () {
                    final newPrefix = prefixController.text.trim();
                    final newInterval = int.tryParse(intervalController.text.trim()) ?? category.serviceIntervalMonths;
                    
                    if (newPrefix.isNotEmpty) {
                      category.prefix = newPrefix;
                      category.serviceIntervalMonths = newInterval;
                      category.serviceRequiresDocument = requiresDoc;
                      
                      _categoryService.updateCategory(category);
                      
                      this.setState(() {}); // refresh list
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white),
                  child: const Text("Speichern"),
                ),
              ],
            );
          }
        );
      },
    );
  }
}
