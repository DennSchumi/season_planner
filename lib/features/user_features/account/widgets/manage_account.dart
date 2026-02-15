import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/features/user_features/account/account_view.dart';
import 'package:season_planner/services/database_service.dart';
import 'package:season_planner/services/providers/user_provider.dart';

import '../../../../data/models/user_models/user_model_userView.dart';

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

  final _firstNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();

  bool _editFirstName = false;
  bool _editLastName = false;
  bool _editEmail = false;
  bool _editPhone = false;

  bool _busy = false;

  String _initialFirstName = "";
  String _initialLastName = "";
  String _initialEmail = "";
  String _initialPhone = "";

  bool _initialized = false;

  bool get _isDirty =>
      _firstNameCtrl.text.trim() != _initialFirstName ||
          _lastNameCtrl.text.trim() != _initialLastName ||
          _emailCtrl.text.trim() != _initialEmail ||
          _phoneCtrl.text.trim() != _initialPhone;

  bool get _emailChanged => _emailCtrl.text.trim() != _initialEmail;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();

    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();

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
  }

  void _loadControllersFromUser(UserModelUserView user) {
    final parts = user.name.trim().split(RegExp(r"\s+"));
    final first = parts.isNotEmpty ? parts.first : "";
    final last = parts.length > 1 ? parts.sublist(1).join(" ") : "";

    _initialFirstName = first;
    _initialLastName = last;
    _initialEmail = user.mail;
    _initialPhone = user.phone;

    _firstNameCtrl.text = _initialFirstName;
    _lastNameCtrl.text = _initialLastName;
    _emailCtrl.text = _initialEmail;
    _phoneCtrl.text = _initialPhone;
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

      // optional: nur ein Feld gleichzeitig editierbar
      _editFirstName = false;
      _editLastName = false;
      _editEmail = false;
      _editPhone = false;

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

  Future<String?> _askPasswordDialog() async {
    final ctrl = TextEditingController();
    bool obscure = true;

    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text("Confirm with password"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Changing your email requires your password for security reasons.",
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: "Password",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setLocal(() => obscure = !obscure),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text("Confirm"),
              ),
            ],
          ),
        );
      },
    );

    final pw = result?.trim();
    if (pw == null || pw.isEmpty) return null;
    return pw;
  }

  Future<void> _save(UserModelUserView user) async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim(); // optional

    if (firstName.isEmpty) {
      _toast("First name is required");
      return;
    }
    if (lastName.isEmpty) {
      _toast("Last name is required");
      return;
    }
    if (email.isEmpty || !email.contains("@")) {
      _toast("Please enter a valid email address");
      return;
    }

    String? password;
    if (_emailChanged) {
      password = await _askPasswordDialog();
      if (password == null) return; // user cancelled
    }

    setState(() => _busy = true);

    try {
      final ok = await _service.updateAccount(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        password: password,
      );

      if (!ok) {
        _toast("Save failed");
        return;
      }

      if (!mounted) return;

      final refreshed = await _service.getUserInformation();
      if (refreshed != null) {
        context.read<UserProvider>().setUser(refreshed);
        setState(() {
          _loadControllersFromUser(refreshed);
          _resetLocks();
        });
      } else {
        _resetLocks();
      }

      FocusScope.of(context).unfocus();

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AccountView()),
      );
      _toast("Saved");
    } catch (e) {
      _toast("Save failed: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Account")),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                children: [
                  const Text(
                    "Edit your personal information. Fields are locked by default.",
                    style: TextStyle(color: Colors.black54),
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
                            label: "First name",
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
                            label: "Last name",
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
                      label: "Email",
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
                      label: "Phone (optional)",
                      isEditing: _editPhone,
                      hint: "e.g. +49 123 456789",
                      onToggle: () => _toggleAndFocus(
                        currentlyEditing: _editPhone,
                        setEditing: (v) => _editPhone = v,
                        focusNode: _phoneFocus,
                      ),
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
                        onPressed: (!_isDirty || _busy) ? null : () => _discard(user),
                        child: const Text("Discard"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: (!_isDirty || _busy) ? null : () => _save(user),
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
