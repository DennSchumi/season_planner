import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/core/services/database_service.dart';
import 'package:inventar_manager/core/services/security_privacy_service.dart';
import 'package:inventar_manager/core/appwrite_config.dart';
import 'package:inventar_manager/core/theme.dart';
import 'package:inventar_manager/core/widgets/ui_primitives.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/services.dart';

class MonthYearInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    if (text.length > oldValue.text.length) {
      if (text.length > 7) {
        return oldValue;
      }

      final cleanText = text.replaceAll('/', '');
      if (cleanText.length > 6) return oldValue;

      String newText = '';
      for (int i = 0; i < cleanText.length; i++) {
        newText += cleanText[i];
        if (i == 1 && cleanText.length > 2) {
          newText += '/';
        }
      }

      if (text.length == 2 && oldValue.text.length == 1) {
        newText += '/';
      }

      return TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
    return newValue;
  }
}

class WeightInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    if (text.length > oldValue.text.length) {
      final cleanText = text.replaceAll(',', '').replaceAll('.', '');

      String newText = '';
      for (int i = 0; i < cleanText.length; i++) {
        newText += cleanText[i];
        if (i == 2 && cleanText.length > 3) {
          newText += ',';
        }
      }

      if (text.length == 3 && oldValue.text.length == 2) {
        newText += ',';
      }

      return TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
    return newValue;
  }
}

class ServiceCheckView extends StatefulWidget {
  final ItemModel item;

  const ServiceCheckView({super.key, required this.item});

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
  bool _unlockItem = true;

  @override
  void initState() {
    super.initState();
    _loadPreviousData();
  }

  Future<void> _loadPreviousData() async {
    final lastTx = await TransactionService().getLastServiceTransaction(
      widget.item.id,
    );
    if (lastTx != null &&
        lastTx.details != null &&
        lastTx.details!.isNotEmpty) {
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
            _triggerState = _triggerType == 'Hebel'
                ? 'geschlossene Position'
                : 'angezogen mit 2.7NM';
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

      if (bytes.length > 10485760) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Datei ist zu groß (max 10MB)')),
          );
        }
        return;
      }

      if (bytes.length < 5 ||
          bytes[0] != 0x25 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x44 ||
          bytes[3] != 0x46 ||
          bytes[4] != 0x2D) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ungültiges Dateiformat (nur echtes PDF erlaubt)'),
            ),
          );
        }
        return;
      }

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
        // Upload File (mit expliziten Team-Permissions für fileSecurity=true)
        final file = await DatabaseService().uploadFile(
          AppwriteConfig.serviceProofsBucketId,
          _selectedFileName ?? "service_proof.pdf",
          _selectedFileBytes!,
          permissions: SecurityPrivacyService.schoolMemberUpdatePerms(
            widget.item.schoolId,
          ),
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
          "minWeight": _minWeightController.text.trim().replaceAll(
            '.',
            ',',
          ), // Enforce comma format
          "istWeight": _istWeightController.text.trim().replaceAll(
            '.',
            ',',
          ), // Enforce comma format
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
      widget.item.nextServiceDate = DateTime.now().add(
        const Duration(days: 365 * 2),
      );

      if (widget.item.isLocked && _unlockItem) {
        widget.item.isLocked = false;
        widget.item.lockReason = null;
      }

      await ItemService().updateItem(widget.item);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Service Check gespeichert!',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $e'),
            backgroundColor: Colors.red,
          ),
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text("Service Check")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SoftCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const TintedIconBadge(
                              icon: Icons.inventory_2_outlined,
                              size: 40,
                              iconSize: 20,
                              radius: 12,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "${widget.item.name} (SN: ${widget.item.serialNumber ?? '-'})",
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Segmented Control for Proof Type
                      SoftCard(
                        radius: 16,
                        padding: const EdgeInsets.all(5),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _proofType = 'form'),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 11),
                                  decoration: BoxDecoration(
                                    color: _proofType == 'form'
                                        ? (isDark
                                            ? AppTheme.primaryColor
                                                .withValues(alpha: 0.2)
                                            : AppTheme.primaryTint)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "Schwimmwesten Formular",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _proofType == 'form'
                                            ? (isDark
                                                ? AppTheme.darkPrimary
                                                : AppTheme.primaryColor)
                                            : cs.onSurfaceVariant,
                                        fontSize: 13.5,
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 11),
                                  decoration: BoxDecoration(
                                    color: _proofType == 'pdf'
                                        ? (isDark
                                            ? AppTheme.primaryColor
                                                .withValues(alpha: 0.2)
                                            : AppTheme.primaryTint)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "Dateiupload (PDF)",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _proofType == 'pdf'
                                            ? (isDark
                                                ? AppTheme.darkPrimary
                                                : AppTheme.primaryColor)
                                            : cs.onSurfaceVariant,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      if (_proofType == 'pdf')
                        _buildPdfUploadSection()
                      else
                        _buildFormSection(),

                      if (widget.item.isLocked) ...[
                        const SizedBox(height: 18),
                        SoftCard(
                          child: CheckboxListTile(
                            title: const Text(
                              "Gerät nach Speichern entsperren",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              "Hebt die aktuelle manuelle Sperre des Gegenstands auf.",
                            ),
                            value: _unlockItem,
                            onChanged: (v) =>
                                setState(() => _unlockItem = v ?? true),
                          ),
                        ),
                      ],

                      const SizedBox(height: 22),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: _isSaving ? null : AppTheme.primaryGlow,
                        ),
                        child: SizedBox(
                          height: 52,
                          child: FilledButton(
                            onPressed: _isSaving ? null : _save,
                            child: _isSaving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text("Speichern"),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPdfUploadSection() {
    final cs = Theme.of(context).colorScheme;
    return SoftCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const TintedIconBadge(
            icon: Icons.picture_as_pdf_outlined,
            size: 52,
            iconSize: 26,
            radius: 16,
          ),
          const SizedBox(height: 14),
          Text(
            "Service-Protokoll hochladen",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            "Lade ein eingescanntes Protokoll oder ein PDF hoch.",
            style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(_selectedFileName ?? "PDF auswählen"),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSection() {
    final cs = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: SoftCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTextField(
              "Prüfer Name",
              _inspectorController,
              placeholder: "Max Mustermann",
            ),

            const SizedBox(height: 6),
            Text(
              "Art des Checks",
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            _buildToggleGroup(
              ['Routinecheck', 'Neupacken nach Auslösung'],
              _checkType,
              (v) => setState(() => _checkType = v),
            ),
            const SizedBox(height: 16),

            if (_checkType == 'Neupacken nach Auslösung') ...[
              _buildDropdown(
                "Weste vollständig getrocknet",
                ['Ja', 'Nein'],
                _dry,
                (v) => setState(() => _dry = v!),
              ),
              _buildDropdown(
                "Funktion bei Auslösung",
                ['OK', 'Fehlerhaft'],
                _funcTest,
                (v) => setState(() => _funcTest = v!),
              ),
            ],

            _buildTextField(
              "DOM CO2 Kartusche",
              _domCo2Controller,
              placeholder: "MM/JJJJ",
              maxLength: 7,
              formatters: [MonthYearInputFormatter()],
            ),

            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    "Min-Gewicht (g)",
                    _minWeightController,
                    isNumber: true,
                    placeholder: "ggg,dd",
                    formatters: [WeightInputFormatter()],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildTextField(
                    "Ist-Gewicht (g)",
                    _istWeightController,
                    isNumber: true,
                    placeholder: "ggg,dd",
                    formatters: [WeightInputFormatter()],
                  ),
                ),
              ],
            ),

            _buildTextField(
              "Ablaufdatum Automatik",
              _expAutoController,
              placeholder: "MM/JJJJ",
              maxLength: 7,
              formatters: [MonthYearInputFormatter()],
            ),

            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    "Siegel man. Auslösung",
                    ['OK', 'Fehlt', 'Erneuert'],
                    _sealMan,
                    (v) => setState(() => _sealMan = v!),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildDropdown(
                    "Siegel autom. Auslösung",
                    ['OK', 'Fehlt', 'Erneuert'],
                    _sealAuto,
                    (v) => setState(() => _sealAuto = v!),
                  ),
                ),
              ],
            ),

            _buildDropdown(
              "Drucktest (min. 12h)",
              ['nicht durchgeführt', 'Bestanden', 'Nicht bestanden'],
              _pressure,
              (v) => setState(() => _pressure = v!),
            ),

            const SizedBox(height: 6),
            Text(
              "Sicherungstyp",
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            _buildToggleGroup(['Hebel', 'Schraube'], _triggerType, (v) {
              setState(() {
                _triggerType = v;
                _triggerState = _triggerType == 'Hebel'
                    ? 'geschlossene Position'
                    : 'angezogen mit 2.7NM';
              });
            }),
            const SizedBox(height: 16),

            _buildDropdown(
              "Sicherung Zustand",
              _triggerType == 'Hebel'
                  ? ['geschlossene Position', 'Nicht ok']
                  : ['angezogen mit 2.7NM', 'nicht ok'],
              _triggerState,
              (v) => setState(() => _triggerState = v!),
            ),

            _buildDropdown(
              "Korrekt gepackt",
              ['Ja', 'Nein'],
              _packed,
              (v) => setState(() => _packed = v!),
            ),
            _buildDropdown(
              "Gesamtzustand",
              ['Einsatzbereit', 'Gesperrt / Defekt'],
              _condition,
              (v) => setState(() => _condition = v!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleGroup(
    List<String> options,
    String currentValue,
    Function(String) onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardElevated : AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
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
                  color: isSelected
                      ? AppTheme.primaryColor
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    opt,
                    style: TextStyle(
                      color: isSelected ? Colors.white : cs.onSurfaceVariant,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
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

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
    String? placeholder,
    int? maxLength,
    List<TextInputFormatter>? formatters,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: isNumber
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            maxLength: maxLength,
            inputFormatters: formatters,
            decoration: InputDecoration(
              hintText: placeholder,
              counterText: "",
            ),
            validator: (value) =>
                value == null || value.isEmpty ? "Pflichtfeld" : null,
            onChanged: isNumber
                ? (val) {
                    if (val.contains('.')) {
                      controller.value = controller.value.copyWith(
                        text: val.replaceAll('.', ','),
                        selection: TextSelection.collapsed(
                          offset: val.replaceAll('.', ',').length,
                        ),
                      );
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String value,
    void Function(String?) onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: value,
            icon: Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
            items: items
                .map(
                  (i) => DropdownMenuItem(
                    value: i,
                    child: Text(i),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
