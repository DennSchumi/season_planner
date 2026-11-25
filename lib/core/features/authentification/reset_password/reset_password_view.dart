import 'package:flutter/material.dart';
import 'package:season_planner/core/features/authentification/login/login_view.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/web_url_helper.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';

/// Zielseite für den Passwort-Zurücksetzen-Link aus der Appwrite-Recovery-E-Mail
/// (`/reset-password?userId=...&secret=...`).
class ResetPasswordView extends StatefulWidget {
  final String userId;
  final String secret;

  const ResetPasswordView({
    super.key,
    required this.userId,
    required this.secret,
  });

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<ResetPasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  bool _completed = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _hasValidParams =>
      widget.userId.trim().isNotEmpty && widget.secret.trim().isNotEmpty;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_hasValidParams) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await AuthService().completePasswordRecovery(
        userId: widget.userId,
        secret: widget.secret,
        newPassword: _passwordCtrl.text,
      );
      clearBrowserUrlToRoot();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _completed = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = AuthService.formatAuthError(e);
      });
    }
  }

  void _goToLogin() {
    clearBrowserUrlToRoot();
    Navigator.of(context).pushAndRemoveUntil(
      fadePageRoute(const LoginView()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: _completed
                              ? AppTheme.successColor
                              : AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: AppTheme.primaryGlow,
                        ),
                        child: Icon(
                          _completed
                              ? Icons.check_rounded
                              : Icons.lock_reset_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _completed
                            ? 'Passwort gespeichert'
                            : 'Neues Passwort festlegen',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displayLarge?.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _completed
                            ? 'Dein Passwort wurde erfolgreich geändert. Du kannst dich jetzt anmelden.'
                            : 'Vergib ein neues Passwort mit mindestens 8 Zeichen für dein Season-Planner-Konto.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SoftCard(
                    padding: const EdgeInsets.all(20),
                    radius: 24,
                    child: _completed
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppTheme.successColor
                                      .withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.verified_outlined,
                                      color: AppTheme.successColor,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Alles bereit! Melde dich jetzt mit deiner E-Mail und dem neuen Passwort an.',
                                        style: TextStyle(fontSize: 13.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 50,
                                child: FilledButton(
                                  onPressed: _goToLogin,
                                  child: const Text('Zur Anmeldung'),
                                ),
                              ),
                            ],
                          )
                        : !_hasValidParams
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Dieser Passwort-Reset-Link ist unvollständig oder ungültig. Bitte fordere auf der Anmeldeseite einen neuen Link an.',
                                    style: TextStyle(
                                      color: cs.error,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    height: 48,
                                    child: FilledButton(
                                      onPressed: _goToLogin,
                                      child: const Text('Zur Anmeldung'),
                                    ),
                                  ),
                                ],
                              )
                            : Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TextFormField(
                                      controller: _passwordCtrl,
                                      obscureText: _obscurePassword,
                                      enabled: !_submitting,
                                      autofillHints: const [
                                        AutofillHints.newPassword,
                                      ],
                                      textInputAction: TextInputAction.next,
                                      decoration: InputDecoration(
                                        labelText: 'Neues Passwort',
                                        helperText: 'Mindestens 8 Zeichen',
                                        prefixIcon:
                                            const Icon(Icons.lock_outline),
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                          ),
                                        ),
                                      ),
                                      validator: (value) {
                                        final v = value ?? '';
                                        if (v.isEmpty) {
                                          return 'Bitte neues Passwort eingeben.';
                                        }
                                        if (v.length < 8) {
                                          return 'Mindestens 8 Zeichen erforderlich.';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _confirmCtrl,
                                      obscureText: _obscureConfirm,
                                      enabled: !_submitting,
                                      autofillHints: const [
                                        AutofillHints.newPassword,
                                      ],
                                      textInputAction: TextInputAction.done,
                                      onFieldSubmitted: (_) => _submit(),
                                      decoration: InputDecoration(
                                        labelText: 'Passwort wiederholen',
                                        prefixIcon: const Icon(
                                          Icons.lock_outline_rounded,
                                        ),
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(
                                            () => _obscureConfirm =
                                                !_obscureConfirm,
                                          ),
                                          icon: Icon(
                                            _obscureConfirm
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                          ),
                                        ),
                                      ),
                                      validator: (value) {
                                        if ((value ?? '') !=
                                            _passwordCtrl.text) {
                                          return 'Die Passwörter stimmen nicht überein.';
                                        }
                                        return null;
                                      },
                                    ),
                                    if (_errorMessage != null) ...[
                                      const SizedBox(height: 14),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: cs.errorContainer
                                              .withValues(alpha: 0.45),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _errorMessage!,
                                          style: TextStyle(
                                            color: cs.error,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 18),
                                    SizedBox(
                                      height: 50,
                                      child: FilledButton(
                                        onPressed: _submitting ? null : _submit,
                                        child: _submitting
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Text(
                                                'Passwort speichern',
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed:
                                          _submitting ? null : _goToLogin,
                                      child: const Text('Zurück zur Anmeldung'),
                                    ),
                                  ],
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
}
