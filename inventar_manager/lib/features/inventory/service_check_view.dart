import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/core/services/database_service.dart';
import 'package:inventar_manager/core/appwrite_config.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class ServiceCheckView extends StatefulWidget {
  final ItemModel item;

  const ServiceCheckView({Key? key, required this.item}) : super(key: key);

  @override
  _ServiceCheckViewState createState() => _ServiceCheckViewState();
}

class _ServiceCheckViewState extends State<ServiceCheckView> {
  final _formKey = GlobalKey<FormState>();
  
  bool _isLoading = true;
  bool _isSaving = false;
  String _proofType = 'form'; // 'form' or 'pdf'
  
  // PDF Upload State
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;

  // Form State
  String _checkType = 'Routinecheck';
  String _triggerType = 'Hebel';

  // Form Controllers
  final _inspectorController = TextEditingController();
  final _domCo2Controller = TextEditingController();
  final _minWeightController = TextEditingController();
  final _istWeightController = TextEditingController();
  final _expAutoController = TextEditingController();
  
  // Dropdown values
  String _dry = 'Ja';
  String _funcTest = 'OK';
  String _sealMan = 'OK';
  String _sealAuto = 'OK';
  String _pressure = 'Bestanden';
  String _triggerState = 'geschlossene Position';
  String _packed = 'Ja';
  String _condition = 'Einsatzbereit';

  @override
  void initState() {
    super.initState();
    _loadPreviousData();
  }

  Future<void> _loadPreviousData() async {
    final lastTx = await TransactionService().getLastServiceTransaction(widget.item.id);
    if (lastTx != null && lastTx.details != null && lastTx.details!.isNotEmpty) {
      try {
        final data = jsonDecode(lastTx.details!);
        if (data['checkType'] != null) {
          // If the last service was a form, pre-fill it.
          _proofType = 'form';
          setState(() {
            _checkType = 'Routinecheck'; // Default back to routine
            if (data['triggerType'] != null) {
              _triggerType = data['triggerType'];
            }
            if (data['inspector'] != null) {
              _inspectorController.text = data['inspector'];
            }
            if (data['domCo2'] != null) {
              _domCo2Controller.text = data['domCo2'];
            }
            if (data['minWeight'] != null) {
              _minWeightController.text = data['minWeight'];
            }
            if (data['expAuto'] != null) {
              _expAutoController.text = data['expAuto'];
            }
            // Trigger state options depend on trigger type
            _triggerState = _triggerType == 'Hebel' ? 'geschlossene Position' : 'angezogen mit 2.7NM';
          });
        }
      } catch (e) {
        debugPrint("Error decoding previous service data: $e");
      }
    } else {
      // If no previous data, guess by name if it's a life jacket
      if (!widget.item.name.toLowerCase().contains("weste")) {
        _proofType = 'pdf';
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _pickFile() async {
    PlatformFile? result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      final bytes = await result.readAsBytes();
      setState(() {
        _selectedFileBytes = bytes;
        _selectedFileName = result.name;
      });
    }
  }

  void _save() async {
    if (_proofType == 'form' && !_formKey.currentState!.validate()) {
      return;
    }
    if (_proofType == 'pdf' && _selectedFileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte wähle eine PDF Datei aus.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final user = AuthService().currentUser;
      final userName = user != null ? user.name : "Unbekannt";
      String detailsJson = "";

      if (_proofType == 'pdf') {
        // Upload File
        final file = await DatabaseService().uploadFile(
          AppwriteConfig.serviceProofsBucketId,
          _selectedFileName ?? "service_proof.pdf",
          _selectedFileBytes!
        );
        if (file == null) {
          throw Exception("Fehler beim Datei-Upload");
        }
        detailsJson = jsonEncode({
          "type": "pdf",
          "fileId": file.$id,
          "fileName": _selectedFileName,
        });
      } else {
        // Formular
        final detailsMap = {
          "checkType": _checkType,
          "triggerType": _triggerType,
          "inspector": _inspectorController.text.trim(),
          "domCo2": _domCo2Controller.text.trim(),
          "minWeight": _minWeightController.text.trim().replaceAll('.', ','), // Enforce comma format
          "istWeight": _istWeightController.text.trim().replaceAll('.', ','), // Enforce comma format
          "expAuto": _expAutoController.text.trim(),
          "dry": _dry,
          "funcTest": _funcTest,
          "sealMan": _sealMan,
          "sealAuto": _sealAuto,
          "pressure": _pressure,
          "triggerState": _triggerState,
          "packed": _packed,
          "condition": _condition,
        };
        detailsJson = jsonEncode(detailsMap);
      }

      final transaction = TransactionModel(
        id: '',
        schoolId: widget.item.schoolId,
        itemId: widget.item.id,
        type: 'service',
        status: 'abgeschlossen',
        initiator: userName,
        captureMethod: 'app',
        details: detailsJson,
        date: DateTime.now(),
      );

      await TransactionService().addTransaction(transaction);

      // Update item service dates
      widget.item.lastServiceDate = DateTime.now();
      // Assume 24 months interval
      widget.item.nextServiceDate = DateTime.now().add(const Duration(days: 365 * 2));
      
      await ItemService().updateItem(widget.item);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service Check gespeichert!', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF10B981)),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Speichern: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          "Service Check",
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: const Color(0xFFE2E8F0), height: 1.0),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "${widget.item.name} (SN: ${widget.item.serialNumber ?? '-'})",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF1E3A8A)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Segmented Control for Proof Type
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _proofType = 'form'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _proofType == 'form' ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _proofType == 'form' ? [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
                            ] : [],
                          ),
                          child: Center(
                            child: Text(
                              "Schwimmwesten Formular",
                              style: TextStyle(
                                fontWeight: _proofType == 'form' ? FontWeight.bold : FontWeight.w500,
                                color: _proofType == 'form' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                fontSize: 14
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _proofType = 'pdf'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _proofType == 'pdf' ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _proofType == 'pdf' ? [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
                            ] : [],
                          ),
                          child: Center(
                            child: Text(
                              "Dateiupload (PDF)",
                              style: TextStyle(
                                fontWeight: _proofType == 'pdf' ? FontWeight.bold : FontWeight.w500,
                                color: _proofType == 'pdf' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                fontSize: 14
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (_proofType == 'pdf') _buildPdfUploadSection()
              else _buildFormSection(),
              
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isSaving 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Speichern", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
    );
  }

  Widget _buildPdfUploadSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.picture_as_pdf, size: 48, color: Color(0xFF94A3B8)),
          const SizedBox(height: 16),
          const Text(
            "Service-Protokoll hochladen",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Text(
            "Lade ein eingescanntes Protokoll oder ein PDF hoch.",
            style: TextStyle(fontSize: 14, color: const Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.upload_file),
            label: Text(_selectedFileName ?? "PDF auswählen"),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF3B82F6),
              side: const BorderSide(color: Color(0xFF3B82F6)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSection() {
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTextField("Prüfer Name", _inspectorController, placeholder: "Max Mustermann"),
            
            const SizedBox(height: 8),
            const Text("Art des Checks", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF0F172A))),
            const SizedBox(height: 8),
            _buildToggleGroup(['Routinecheck', 'Neupacken nach Auslösung'], _checkType, (v) => setState(() => _checkType = v)),
            const SizedBox(height: 16),

            if (_checkType == 'Neupacken nach Auslösung') ...[
              _buildDropdown("Weste vollständig getrocknet", ['Ja', 'Nein'], _dry, (v) => setState(() => _dry = v!)),
              _buildDropdown("Funktion bei Auslösung", ['OK', 'Fehlerhaft'], _funcTest, (v) => setState(() => _funcTest = v!)),
            ],

            _buildTextField("DOM CO2 Kartusche", _domCo2Controller, placeholder: "MM/JJJJ", maxLength: 7),
            
            Row(
              children: [
                Expanded(child: _buildTextField("Min-Gewicht (g)", _minWeightController, isNumber: true, placeholder: "ggg,dd")),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField("Ist-Gewicht (g)", _istWeightController, isNumber: true, placeholder: "ggg,dd")),
              ],
            ),
            
            _buildTextField("Ablaufdatum Automatik", _expAutoController, placeholder: "MM/JJJJ", maxLength: 7),
            
            Row(
              children: [
                Expanded(child: _buildDropdown("Siegel man. Auslösung", ['OK', 'Fehlt', 'Erneuert'], _sealMan, (v) => setState(() => _sealMan = v!))),
                const SizedBox(width: 16),
                Expanded(child: _buildDropdown("Siegel autom. Auslösung", ['OK', 'Fehlt', 'Erneuert'], _sealAuto, (v) => setState(() => _sealAuto = v!))),
              ],
            ),

            _buildDropdown("Drucktest (min. 12h)", ['nicht durchgeführt', 'Bestanden', 'Nicht bestanden'], _pressure, (v) => setState(() => _pressure = v!)),
            
            const SizedBox(height: 8),
            const Text("Sicherungstyp", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF0F172A))),
            const SizedBox(height: 8),
            _buildToggleGroup(['Hebel', 'Schraube'], _triggerType, (v) {
              setState(() {
                _triggerType = v;
                _triggerState = _triggerType == 'Hebel' ? 'geschlossene Position' : 'angezogen mit 2.7NM';
              });
            }),
            const SizedBox(height: 16),

            _buildDropdown("Sicherung Zustand", 
              _triggerType == 'Hebel' ? ['geschlossene Position', 'Nicht ok'] : ['angezogen mit 2.7NM', 'nicht ok'], 
              _triggerState, (v) => setState(() => _triggerState = v!)
            ),

            _buildDropdown("Korrekt gepackt", ['Ja', 'Nein'], _packed, (v) => setState(() => _packed = v!)),
            _buildDropdown("Gesamtzustand", ['Einsatzbereit', 'Gesperrt / Defekt'], _condition, (v) => setState(() => _condition = v!)),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleGroup(List<String> options, String currentValue, Function(String) onChanged) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: options.map((opt) {
          final isSelected = opt == currentValue;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(opt),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    opt,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF64748B),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isNumber = false, String? placeholder, int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF0F172A))),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
            maxLength: maxLength,
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF3B82F6)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              counterText: "",
            ),
            validator: (value) => value == null || value.isEmpty ? "Pflichtfeld" : null,
            onChanged: isNumber ? (val) {
              if (val.contains('.')) {
                // Auto-replace dot with comma for German locale number input
                controller.value = controller.value.copyWith(
                  text: val.replaceAll('.', ','),
                  selection: TextSelection.collapsed(offset: val.replaceAll('.', ',').length),
                );
              }
            } : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> items, String value, void Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF0F172A))),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: value,
            icon: const Icon(Icons.expand_more, color: Color(0xFF64748B)),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF3B82F6)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(color: Color(0xFF0F172A))))).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
