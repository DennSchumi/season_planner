import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/user/services/database_service.dart';
import 'package:season_planner/user/user_provider.dart';
import '../../../../user/data/models/user_model_userView.dart';

class ManageAccountView extends StatefulWidget {
  const ManageAccountView({super.key});

  @override
  State<ManageAccountView> createState() => _ManageAccountViewState();
}

class _ManageAccountViewState extends State<ManageAccountView> {
  final _service = DatabaseService();

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyRelationCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _licenseNumberCtrl = TextEditingController();
  final _licenseRatingsCtrl = TextEditingController();
  final _employmentTypeCtrl = TextEditingController();
  final _activeSinceCtrl = TextEditingController();

  final _firstNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emergencyNameFocus = FocusNode();
  final _emergencyRelationFocus = FocusNode();
  final _emergencyPhoneFocus = FocusNode();
  final _birthDateFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _licenseNumberFocus = FocusNode();
  final _licenseRatingsFocus = FocusNode();
  final _employmentTypeFocus = FocusNode();
  final _activeSinceFocus = FocusNode();

  bool _editFirstName = false;
  bool _editLastName = false;
  bool _editEmail = false;
  bool _editPhone = false;
  bool _editEmergencyName = false;
  bool _editEmergencyRelation = false;
  bool _editEmergencyPhone = false;
  bool _editBirthDate = false;
  bool _editAddress = false;
  bool _editLicenseNumber = false;
  bool _editLicenseRatings = false;
  bool _editEmploymentType = false;
  bool _editActiveSince = false;
  bool _busy = false;
  bool _uploadingAvatar = false;

  String _initialFirstName = "";
  String _initialLastName = "";
  String _initialEmail = "";
  String _initialPhone = "";
  String _initialEmergencyName = "";
  String _initialEmergencyRelation = "";
  String _initialEmergencyPhone = "";
  String _initialBirthDate = "";
  String _initialAddress = "";
  String _initialLicenseNumber = "";
  String _initialLicenseRatings = "";
  String _initialEmploymentType = "";
  String _initialActiveSince = "";
  bool _initialized = false;

  static const List<String> _relationSuggestions = [
    'Partner/in',
    'Ehepartner/in',
    'Eltern',
    'Geschwister',
    'Freund/in',
  ];

  static const List<String> _employmentSuggestions = [
    'Freier Mitarbeiter',
    'Angestellt',
    'Geschäftsführer/in',
    'Selbstständig',
  ];

  bool get _isDirty =>
      _firstNameCtrl.text.trim() != _initialFirstName ||
      _lastNameCtrl.text.trim() != _initialLastName ||
      _emailCtrl.text.trim() != _initialEmail ||
      _phoneCtrl.text.trim() != _initialPhone ||
      _emergencyNameCtrl.text.trim() != _initialEmergencyName ||
      _emergencyRelationCtrl.text.trim() != _initialEmergencyRelation ||
      _emergencyPhoneCtrl.text.trim() != _initialEmergencyPhone ||
      _birthDateCtrl.text.trim() != _initialBirthDate ||
      _addressCtrl.text.trim() != _initialAddress ||
      _licenseNumberCtrl.text.trim() != _initialLicenseNumber ||
      _licenseRatingsCtrl.text.trim() != _initialLicenseRatings ||
      _employmentTypeCtrl.text.trim() != _initialEmploymentType ||
      _activeSinceCtrl.text.trim() != _initialActiveSince;

  bool get _emailChanged => _emailCtrl.text.trim() != _initialEmail;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyRelationCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _birthDateCtrl.dispose();
    _addressCtrl.dispose();
    _licenseNumberCtrl.dispose();
    _licenseRatingsCtrl.dispose();
    _employmentTypeCtrl.dispose();
    _activeSinceCtrl.dispose();
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _emergencyNameFocus.dispose();
    _emergencyRelationFocus.dispose();
    _emergencyPhoneFocus.dispose();
    _birthDateFocus.dispose();
    _addressFocus.dispose();
    _licenseNumberFocus.dispose();
    _licenseRatingsFocus.dispose();
    _employmentTypeFocus.dispose();
    _activeSinceFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.read<UserProvider>().user;
    if (!_initialized && user != null) {
      _initialized = true;
      _loadControllersFromUser(user);
      _resetLocks();
    }
  }

  void _resetLocks() {
    _editFirstName = false;
    _editLastName = false;
    _editEmail = false;
    _editPhone = false;
    _editEmergencyName = false;
    _editEmergencyRelation = false;
    _editEmergencyPhone = false;
    _editBirthDate = false;
    _editAddress = false;
    _editLicenseNumber = false;
    _editLicenseRatings = false;
    _editEmploymentType = false;
    _editActiveSince = false;
  }

  void _loadControllersFromUser(UserModelUserView user) {
    final parts = user.name.trim().split(RegExp(r"\s+"));
    final first = parts.isNotEmpty ? parts.first : "";
    final last = parts.length > 1 ? parts.sublist(1).join(" ") : "";

    _initialFirstName = first;
    _initialLastName = last;
    _initialEmail = user.mail;
    _initialPhone = user.phone;
    _initialEmergencyName = user.emergencyContactName;
    _initialEmergencyRelation = user.emergencyContactRelation;
    _initialEmergencyPhone = user.emergencyContactPhone;
    _initialBirthDate = user.birthDate;
    _initialAddress = user.address;
    _initialLicenseNumber = user.licenseNumber;
    _initialLicenseRatings = user.licenseRatings;
    _initialEmploymentType = user.employmentType;
    _initialActiveSince = user.activeSince;

    _firstNameCtrl.text = _initialFirstName;
    _lastNameCtrl.text = _initialLastName;
    _emailCtrl.text = _initialEmail;
    _phoneCtrl.text = _initialPhone;
    _emergencyNameCtrl.text = _initialEmergencyName;
    _emergencyRelationCtrl.text = _initialEmergencyRelation;
    _emergencyPhoneCtrl.text = _initialEmergencyPhone;
    _birthDateCtrl.text = _initialBirthDate;
    _addressCtrl.text = _initialAddress;
    _licenseNumberCtrl.text = _initialLicenseNumber;
    _licenseRatingsCtrl.text = _initialLicenseRatings;
    _employmentTypeCtrl.text = _initialEmploymentType;
    _activeSinceCtrl.text = _initialActiveSince;
  }

  void _discard(UserModelUserView user) {
    setState(() {
      _loadControllersFromUser(user);
      _resetLocks();
    });
    FocusScope.of(context).unfocus();
  }

  void _toggleAndFocus({
    required bool currentlyEditing,
    required void Function(bool v) setEditing,
    required FocusNode focusNode,
  }) {
    if (_busy) return;
    setState(() {
      final next = !currentlyEditing;
      _resetLocks();
      setEditing(next);
    });
    if (!currentlyEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusScope.of(context).requestFocus(focusNode);
      });
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _pickAndUploadAvatar(UserModelUserView user) async {
    if (_busy || _uploadingAvatar) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _toast('Bilddatei konnte nicht gelesen werden.');
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        _toast('Das Bild darf maximal 5 MB groß sein.');
        return;
      }

      setState(() => _uploadingAvatar = true);
      final uploaded = await _service.uploadUserAvatar(
        bytes: bytes,
        filename: file.name,
        oldAvatarFileId: user.avatarFileId,
      );
      if (!mounted) return;
      if (uploaded == null) {
        _toast('Upload des Profilbilds fehlgeschlagen.');
        return;
      }
      final updated = user.copyWith(
        avatarUrl: uploaded.url,
        avatarFileId: uploaded.fileId,
      );
      context.read<UserProvider>().setUser(updated);
      _toast('Profilbild aktualisiert.');
    } catch (e) {
      _toast('Profilbild-Upload fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar(UserModelUserView user) async {
    if (_busy || _uploadingAvatar || user.avatarUrl.isEmpty) return;
    setState(() => _uploadingAvatar = true);
    try {
      final ok = await _service.removeUserAvatar(
        oldAvatarFileId: user.avatarFileId,
      );
      if (!mounted) return;
      if (ok) {
        context.read<UserProvider>().setUser(
              user.copyWith(avatarUrl: '', avatarFileId: ''),
            );
        _toast('Profilbild entfernt.');
      } else {
        _toast('Profilbild konnte nicht entfernt werden.');
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<String?> _askPasswordDialog() async {
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PasswordConfirmDialog(),
    );
    final pw = result?.trim();
    if (pw == null || pw.isEmpty) return null;
    return pw;
  }

  Future<void> _save(UserModelUserView user) async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final emergencyName = _emergencyNameCtrl.text.trim();
    final emergencyRelation = _emergencyRelationCtrl.text.trim();
    final emergencyPhone = _emergencyPhoneCtrl.text.trim();
    final birthDate = _birthDateCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final licenseNumber = _licenseNumberCtrl.text.trim();
    final licenseRatings = _licenseRatingsCtrl.text.trim();
    final employmentType = _employmentTypeCtrl.text.trim();
    final activeSince = _activeSinceCtrl.text.trim();

    if (firstName.isEmpty) {
      _toast("Vorname ist erforderlich.");
      return;
    }
    if (lastName.isEmpty) {
      _toast("Nachname ist erforderlich.");
      return;
    }
    if (email.isEmpty || !email.contains("@")) {
      _toast("Bitte gib eine gültige E-Mail-Adresse ein.");
      return;
    }

    String? password;
    if (_emailChanged) {
      password = await _askPasswordDialog();
      if (password == null) return;
    }

    setState(() => _busy = true);
    try {
      final ok = await _service.updateAccount(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        password: password,
        emergencyContactName: emergencyName,
        emergencyContactRelation: emergencyRelation,
        emergencyContactPhone: emergencyPhone,
        birthDate: birthDate,
        address: address,
        licenseNumber: licenseNumber,
        licenseRatings: licenseRatings,
        employmentType: employmentType,
        activeSince: activeSince,
      );

      if (!ok) {
        _toast("Speichern fehlgeschlagen.");
        return;
      }

      if (!mounted) return;
      final refreshed = await _service.getUserInformation();
      if (refreshed != null && mounted) {
        context.read<UserProvider>().setUser(refreshed);
        setState(() {
          _loadControllersFromUser(refreshed);
          _resetLocks();
        });
      }
      FocusScope.of(context).unfocus();
      _toast("Änderungen gespeichert.");
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast("Speichern fehlgeschlagen: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickBirthDate() async {
    if (_busy) return;
    DateTime initial = DateTime(1990, 1, 1);
    final raw = _birthDateCtrl.text.trim();
    final m = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(raw);
    if (m != null) {
      final d = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      final y = int.tryParse(m.group(3)!);
      if (d != null && mo != null && y != null && y >= 1920 && y <= 2020) {
        initial = DateTime(y, mo, d);
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1930, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'Geburtsdatum auswählen',
    );
    if (picked == null || !mounted) return;
    final dd = picked.day.toString().padLeft(2, '0');
    final mm = picked.month.toString().padLeft(2, '0');
    setState(() {
      _editBirthDate = true;
      _birthDateCtrl.text = '$dd.$mm.${picked.year}';
    });
  }

  InputDecoration _dec(
    BuildContext context, {
    required String label,
    required bool isEditing,
    VoidCallback? onToggle,
    String? hint,
    IconData? prefixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
      filled: true,
      fillColor: !isEditing
          ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
          : cs.surface,
      suffixIcon: onToggle == null
          ? null
          : IconButton(
              tooltip: isEditing ? "Sperren" : "Bearbeiten",
              onPressed: _busy ? null : onToggle,
              icon: Icon(isEditing ? Icons.lock_open : Icons.edit),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Persönliche Daten")),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy || _uploadingAvatar)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                children: [
                  // Profilbild-Karte
                  Card(
                    elevation: 0,
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              UserAvatar(
                                avatarUrl: user.avatarUrl,
                                name: user.name,
                                radius: 36,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Material(
                                  color: cs.primary,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: _uploadingAvatar || _busy
                                        ? null
                                        : () => _pickAndUploadAvatar(user),
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.camera_alt_outlined,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Profilbild',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Wird in Events neben deiner Position sowie in der Team-Übersicht angezeigt.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: _uploadingAvatar || _busy
                                          ? null
                                          : () => _pickAndUploadAvatar(user),
                                      icon: const Icon(
                                        Icons.upload_outlined,
                                        size: 17,
                                      ),
                                      label: Text(
                                        user.avatarUrl.isEmpty
                                            ? 'Bild hochladen'
                                            : 'Bild ändern',
                                      ),
                                    ),
                                    if (user.avatarUrl.isNotEmpty)
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppTheme.dangerColor,
                                        ),
                                        onPressed: _uploadingAvatar || _busy
                                            ? null
                                            : () => _removeAvatar(user),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 17,
                                        ),
                                        label: const Text('Entfernen'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Persönliche Daten
                  Text(
                    "Kontodaten",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Felder sind standardmäßig gesperrt – tippe auf das Stift-Symbol zum Bearbeiten.",
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _firstNameCtrl,
                          focusNode: _firstNameFocus,
                          readOnly: _busy || !_editFirstName,
                          showCursor: !_busy && _editFirstName,
                          decoration: _dec(
                            context,
                            label: "Vorname",
                            isEditing: _editFirstName,
                            onToggle: () => _toggleAndFocus(
                              currentlyEditing: _editFirstName,
                              setEditing: (v) => _editFirstName = v,
                              focusNode: _firstNameFocus,
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _lastNameCtrl,
                          focusNode: _lastNameFocus,
                          readOnly: _busy || !_editLastName,
                          showCursor: !_busy && _editLastName,
                          decoration: _dec(
                            context,
                            label: "Nachname",
                            isEditing: _editLastName,
                            onToggle: () => _toggleAndFocus(
                              currentlyEditing: _editLastName,
                              setEditing: (v) => _editLastName = v,
                              focusNode: _lastNameFocus,
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailCtrl,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    readOnly: _busy || !_editEmail,
                    showCursor: !_busy && _editEmail,
                    decoration: _dec(
                      context,
                      label: "E-Mail",
                      prefixIcon: Icons.email_outlined,
                      isEditing: _editEmail,
                      onToggle: () => _toggleAndFocus(
                        currentlyEditing: _editEmail,
                        setEditing: (v) => _editEmail = v,
                        focusNode: _emailFocus,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    focusNode: _phoneFocus,
                    keyboardType: TextInputType.phone,
                    readOnly: _busy || !_editPhone,
                    showCursor: !_busy && _editPhone,
                    decoration: _dec(
                      context,
                      label: "Telefon (optional)",
                      prefixIcon: Icons.phone_outlined,
                      isEditing: _editPhone,
                      hint: "z. B. +49 123 456789",
                      onToggle: () => _toggleAndFocus(
                        currentlyEditing: _editPhone,
                        setEditing: (v) => _editPhone = v,
                        focusNode: _phoneFocus,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),

                  const SizedBox(height: 20),

                  // Notfallkontakt-Sektion
                  Card(
                    elevation: 0,
                    color: AppTheme.dangerColor.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: AppTheme.dangerColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.emergency_outlined,
                                color: AppTheme.dangerColor,
                                size: 22,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Notfallkontakt',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Wird für Flugschul-Admins hinterlegt, damit im Notfall schnell eine Vertrauensperson erreicht werden kann.',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _emergencyNameCtrl,
                            focusNode: _emergencyNameFocus,
                            readOnly: _busy || !_editEmergencyName,
                            showCursor: !_busy && _editEmergencyName,
                            decoration: _dec(
                              context,
                              label: 'Name des Notfallkontakts',
                              hint: 'z. B. Maria Muster',
                              prefixIcon: Icons.person_outline,
                              isEditing: _editEmergencyName,
                              onToggle: () => _toggleAndFocus(
                                currentlyEditing: _editEmergencyName,
                                setEditing: (v) => _editEmergencyName = v,
                                focusNode: _emergencyNameFocus,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _emergencyRelationCtrl,
                            focusNode: _emergencyRelationFocus,
                            readOnly: _busy || !_editEmergencyRelation,
                            showCursor: !_busy && _editEmergencyRelation,
                            decoration: _dec(
                              context,
                              label: 'Beziehung',
                              hint: 'z. B. Partner/in, Eltern, Freund/in',
                              prefixIcon: Icons.favorite_border,
                              isEditing: _editEmergencyRelation,
                              onToggle: () => _toggleAndFocus(
                                currentlyEditing: _editEmergencyRelation,
                                setEditing: (v) => _editEmergencyRelation = v,
                                focusNode: _emergencyRelationFocus,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          if (_editEmergencyRelation) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: _relationSuggestions.map((label) {
                                final selected = _emergencyRelationCtrl.text
                                        .trim()
                                        .toLowerCase() ==
                                    label.toLowerCase();
                                return ChoiceChip(
                                  label: Text(
                                    label,
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  selected: selected,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) {
                                    setState(() {
                                      _emergencyRelationCtrl.text = label;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                          const SizedBox(height: 10),
                          TextField(
                            controller: _emergencyPhoneCtrl,
                            focusNode: _emergencyPhoneFocus,
                            keyboardType: TextInputType.phone,
                            readOnly: _busy || !_editEmergencyPhone,
                            showCursor: !_busy && _editEmergencyPhone,
                            decoration: _dec(
                              context,
                              label: 'Telefonnummer (Notfallkontakt)',
                              hint: 'z. B. +49 170 1234567',
                              prefixIcon: Icons.phone_in_talk_outlined,
                              isEditing: _editEmergencyPhone,
                              onToggle: () => _toggleAndFocus(
                                currentlyEditing: _editEmergencyPhone,
                                setEditing: (v) => _editEmergencyPhone = v,
                                focusNode: _emergencyPhoneFocus,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 15,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Datenschutz-Hinweis: Bitte informiere deinen Notfallkontakt darüber, dass seine Kontaktdaten hier für den Notfall hinterlegt und für Admins deiner Flugschulen einsehbar sind.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.35,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Personal- & Lizenzdaten (ÖAeC Audit / Stellenbesetzungsplan)
                  Card(
                    elevation: 0,
                    color: cs.primary.withValues(alpha: 0.04),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: cs.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.badge_outlined,
                                color: cs.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Personal- & Lizenzdaten',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _birthDateCtrl,
                                  focusNode: _birthDateFocus,
                                  readOnly: _busy || !_editBirthDate,
                                  showCursor: !_busy && _editBirthDate,
                                  decoration: _dec(
                                    context,
                                    label: 'Geburtsdatum',
                                    hint: 'TT.MM.JJJJ',
                                    prefixIcon: Icons.cake_outlined,
                                    isEditing: _editBirthDate,
                                    onToggle: () => _toggleAndFocus(
                                      currentlyEditing: _editBirthDate,
                                      setEditing: (v) => _editBirthDate = v,
                                      focusNode: _birthDateFocus,
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: IconButton.filledTonal(
                                  tooltip: 'Datum auswählen',
                                  onPressed: _busy ? null : _pickBirthDate,
                                  icon: const Icon(Icons.calendar_today_outlined, size: 20),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _addressCtrl,
                            focusNode: _addressFocus,
                            maxLines: 2,
                            minLines: 1,
                            readOnly: _busy || !_editAddress,
                            showCursor: !_busy && _editAddress,
                            decoration: _dec(
                              context,
                              label: 'Anschrift',
                              hint: 'Straße Nr., PLZ Ort',
                              prefixIcon: Icons.home_outlined,
                              isEditing: _editAddress,
                              onToggle: () => _toggleAndFocus(
                                currentlyEditing: _editAddress,
                                setEditing: (v) => _editAddress = v,
                                focusNode: _addressFocus,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _licenseNumberCtrl,
                            focusNode: _licenseNumberFocus,
                            readOnly: _busy || !_editLicenseNumber,
                            showCursor: !_busy && _editLicenseNumber,
                            decoration: _dec(
                              context,
                              label: 'Scheinnummer / Lizenz-Nr.',
                              hint: 'z. B. AT.FCL.12345 oder ÖAeC-Scheinnummer',
                              prefixIcon: Icons.credit_card_outlined,
                              isEditing: _editLicenseNumber,
                              onToggle: () => _toggleAndFocus(
                                currentlyEditing: _editLicenseNumber,
                                setEditing: (v) => _editLicenseNumber = v,
                                focusNode: _licenseNumberFocus,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _licenseRatingsCtrl,
                            focusNode: _licenseRatingsFocus,
                            maxLines: 2,
                            minLines: 1,
                            readOnly: _busy || !_editLicenseRatings,
                            showCursor: !_busy && _editLicenseRatings,
                            decoration: _dec(
                              context,
                              label: 'Berechtigungen',
                              hint: 'z. B. Paragleiter SoPi, Tandempilot, Fluglehrer',
                              prefixIcon: Icons.verified_outlined,
                              isEditing: _editLicenseRatings,
                              onToggle: () => _toggleAndFocus(
                                currentlyEditing: _editLicenseRatings,
                                setEditing: (v) => _editLicenseRatings = v,
                                focusNode: _licenseRatingsFocus,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _employmentTypeCtrl,
                            focusNode: _employmentTypeFocus,
                            readOnly: _busy || !_editEmploymentType,
                            showCursor: !_busy && _editEmploymentType,
                            decoration: _dec(
                              context,
                              label: 'Beschäftigungsart',
                              hint: 'z. B. Freier Mitarbeiter, Angestellt',
                              prefixIcon: Icons.work_outline,
                              isEditing: _editEmploymentType,
                              onToggle: () => _toggleAndFocus(
                                currentlyEditing: _editEmploymentType,
                                setEditing: (v) => _editEmploymentType = v,
                                focusNode: _employmentTypeFocus,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          if (_editEmploymentType) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: _employmentSuggestions.map((label) {
                                final selected = _employmentTypeCtrl.text
                                        .trim()
                                        .toLowerCase() ==
                                    label.toLowerCase();
                                return ChoiceChip(
                                  label: Text(
                                    label,
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  selected: selected,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) {
                                    setState(() {
                                      _employmentTypeCtrl.text = label;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                          const SizedBox(height: 10),
                          TextField(
                            controller: _activeSinceCtrl,
                            focusNode: _activeSinceFocus,
                            readOnly: _busy || !_editActiveSince,
                            showCursor: !_busy && _editActiveSince,
                            decoration: _dec(
                              context,
                              label: 'Tätig seit',
                              hint: 'z. B. 03/2021 oder 2021',
                              prefixIcon: Icons.event_available_outlined,
                              isEditing: _editActiveSince,
                              onToggle: () => _toggleAndFocus(
                                currentlyEditing: _editActiveSince,
                                setEditing: (v) => _editActiveSince = v,
                                focusNode: _activeSinceFocus,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
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
                        onPressed:
                            (!_isDirty || _busy) ? null : () => _discard(user),
                        child: const Text("Verwerfen"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            (!_isDirty || _busy) ? null : () => _save(user),
                        child: const Text("Speichern"),
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

class _PasswordConfirmDialog extends StatefulWidget {
  const _PasswordConfirmDialog();

  @override
  State<_PasswordConfirmDialog> createState() => _PasswordConfirmDialogState();
}

class _PasswordConfirmDialogState extends State<_PasswordConfirmDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Mit Passwort bestätigen"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Für eine Änderung deiner E-Mail-Adresse ist aus Sicherheitsgründen dein Passwort erforderlich.",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: _obscure,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(context, v),
            decoration: InputDecoration(
              labelText: "Passwort",
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text("Abbrechen"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text("Bestätigen"),
        ),
      ],
    );
  }
}
