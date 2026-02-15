import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:season_planner/services/providers/flight_school_provider.dart';
import 'package:season_planner/services/flight_school_service.dart';
import 'package:season_planner/data/models/admin_models/flight_school_model_flight_school_view.dart';

class ManageFlightSchoolAdminInfoView extends StatefulWidget {
  const ManageFlightSchoolAdminInfoView({super.key});

  @override
  State<ManageFlightSchoolAdminInfoView> createState() =>
      _ManageFlightSchoolAdminInfoViewState();
}

class _ManageFlightSchoolAdminInfoViewState
    extends State<ManageFlightSchoolAdminInfoView> {
  final _fsService = FlightSchoolService();
  final _picker = ImagePicker();

  final _shortNameCtrl = TextEditingController();
  final _shortNameFocus = FocusNode();

  bool _editShortName = false;
  bool _busy = false;
  bool _initialized = false;

  String _initialShortName = "";
  String _initialLogoLink = "";
  String _initialLogoId = "";

  Uint8List? _pickedLogoBytes;
  String? _pickedLogoFilename;

  bool get _shortNameDirty => _shortNameCtrl.text.trim() != _initialShortName;
  bool get _logoDirty => _pickedLogoBytes != null;
  bool get _isDirty => _shortNameDirty || _logoDirty;

  @override
  void dispose() {
    _shortNameCtrl.dispose();
    _shortNameFocus.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _loadFromFs(FlightSchoolModelFlightSchoolView fs) {
    _initialShortName = fs.displayShortName.trim().isNotEmpty
        ? fs.displayShortName.trim()
        : fs.displayName.trim();

    _initialLogoLink = fs.logoLink;
    _initialLogoId = fs.logoId;

    _shortNameCtrl.text = _initialShortName;

    _pickedLogoBytes = null;
    _pickedLogoFilename = null;

    _editShortName = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (!_initialized && fs != null) {
      _initialized = true;
      _loadFromFs(fs);
    }
  }

  void _toggleShortName() {
    if (_busy) return;

    setState(() => _editShortName = !_editShortName);

    if (_editShortName) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_shortNameFocus);
        _shortNameCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _shortNameCtrl.text.length,
        );
      });
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _pickLogo() async {
    if (_busy) return;

    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();

    setState(() {
      _pickedLogoBytes = bytes;
      _pickedLogoFilename = file.name;
    });
  }

  void _discard(FlightSchoolModelFlightSchoolView fs) {
    setState(() => _loadFromFs(fs));
    FocusScope.of(context).unfocus();
  }

  Widget _roundLogo({
    required String logoUrl,
    required Uint8List? pickedBytes,
  }) {
    return ClipOval(
      child: pickedBytes != null
          ? Image.memory(
        pickedBytes,
        width: 150,
        height: 150,
        fit: BoxFit.cover,
      )
          : (logoUrl.isNotEmpty
          ? Image.network(
        logoUrl,
        width: 150,
        height: 150,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          "lib/assets/images/fsBaseImage.webp",
          width: 150,
          height: 150,
          fit: BoxFit.cover,
        ),
      )
          : Image.asset(
        "lib/assets/images/fsBaseImage.webp",
        width: 150,
        height: 150,
        fit: BoxFit.cover,
      )),
    );
  }

  InputDecoration _dec({
    required String label,
    required bool isEditing,
    required VoidCallback onToggle,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      filled: !isEditing,
      fillColor: !isEditing ? Colors.black12.withOpacity(0.04) : null,
      suffixIcon: IconButton(
        tooltip: isEditing ? "Lock" : "Edit",
        onPressed: _busy ? null : onToggle,
        icon: Icon(isEditing ? Icons.lock_open : Icons.edit),
      ),
    );
  }

  Future<void> _save(FlightSchoolModelFlightSchoolView fs) async {
    final shortName = _shortNameCtrl.text.trim();

    if (shortName.isEmpty) {
      _toast("Short name is required");
      return;
    }
    if (shortName.length > 25) {
      _toast("Short name must be max 25 characters");
      return;
    }

    setState(() => _busy = true);

    try {
      /*// 1) ShortName speichern (falls geändert)
      if (_shortNameDirty) {
        final ok = await _fsService.updateFlightSchoolShortName(
          flightSchoolId: fs.id,
          shortName: shortName,
        );
        if (!ok) throw Exception("Failed to update short name");
      }

      // 2) Logo hochladen (falls neu gewählt)
      if (_pickedLogoBytes != null) {
        final upload = await _fsService.uploadFlightSchoolLogo(
          flightSchoolId: fs.id,
          bytes: _pickedLogoBytes!,
          filename: _pickedLogoFilename ?? "logo.jpg",
          oldLogoFileId: _initialLogoId.isEmpty ? null : _initialLogoId,
        );

        // Erwartung: upload liefert neues logoLink + logoId zurück
        // (wenn deine Methode anders ist, sag kurz)
        if (upload == null) {
          throw Exception("Failed to upload logo");
        }

        final ok = await _fsService.updateFlightSchoolLogo(
          flightSchoolId: fs.id,
          logoLink: upload.logoLink,
          logoId: upload.logoId,
        );
        if (!ok) throw Exception("Failed to save logo");
      }

      // 3) FS neu laden (kein optimistic UI)
      final refreshed = await _fsService.getFlightSchool(fs.id);
      if (refreshed == null) {
        _toast("Saved, but reload failed");
        return;
      }

      if (!mounted) return;
      context.read<FlightSchoolProvider>().setFlightSchool(refreshed);

      setState(() => _loadFromFs(refreshed));
      FocusScope.of(context).unfocus();*/
      _toast("Saved");
    } catch (e) {
      _toast("Save failed: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;

    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final remaining = 25 - _shortNameCtrl.text.trim().length;

    return Scaffold(
      appBar: AppBar(title: Text("Edit ${fs.displayName}")),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                children: [
                  const Text(
                    "Edit short name and logo. Fields are locked by default.",
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),

                  Center(
                    child: _roundLogo(
                      logoUrl: _initialLogoLink,
                      pickedBytes: _pickedLogoBytes,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickLogo,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(_pickedLogoBytes == null ? "Change logo" : "Change again"),
                    ),
                  ),

                  const SizedBox(height: 18),

                  TextField(
                    controller: _shortNameCtrl,
                    focusNode: _shortNameFocus,
                    readOnly: _busy || !_editShortName,
                    showCursor: !_busy && _editShortName,
                    maxLength: 25,
                    decoration: _dec(
                      label: "Short name (max 25)",
                      isEditing: _editShortName,
                      onToggle: _toggleShortName,
                    ).copyWith(
                      counterText: _editShortName ? "Remaining: $remaining" : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),

            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: (!_isDirty || _busy) ? null : () => _discard(fs),
                        child: const Text("Discard"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: (!_isDirty || _busy) ? null : () => _save(fs),
                        child: const Text("Save"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
