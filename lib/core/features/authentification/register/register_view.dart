import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:season_planner/core/features/authentification/widgets/social_auth_buttons.dart';
import 'package:season_planner/core/features/onboarding/onboarding_choice_view.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/legal_links.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/services/database_service.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController otpController = TextEditingController();

  final FocusNode _firstNameFocus = FocusNode();
  final FocusNode _lastNameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();
  final FocusNode _otpFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _resendingOtp = false;
  bool _acceptedLegal = false;
  bool _legalError = false;
  enums.OAuthProvider? _oauthLoading;
  String _errorMessage = '';

  // Schritt 2: E-Mail-OTP-Verifizierung
  bool _otpStep = false;
  String _pendingUserId = '';
  int _resendCooldownSec = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    otpController.dispose();

    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldownSec = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldownSec <= 1) {
        timer.cancel();
        setState(() => _resendCooldownSec = 0);
      } else {
        setState(() => _resendCooldownSec--);
      }
    });
  }

  String? _validateRequired(String? value, String fieldName) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$fieldName ist erforderlich.';
    return null;
  }

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'E-Mail ist erforderlich.';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(v)) {
      return 'Bitte eine gültige E-Mail-Adresse eingeben.';
    }
    return null;
  }

  String? _validatePhoneOptional(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final phoneRegex = RegExp(r'^[0-9+\-\s()]{6,}$');
    if (!phoneRegex.hasMatch(v)) {
      return 'Bitte eine gültige Telefonnummer eingeben.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Passwort ist erforderlich.';
    if (v.contains(' ')) {
      return 'Das Passwort darf keine Leerzeichen enthalten.';
    }
    if (v.length < 8) {
      return 'Das Passwort muss mindestens 8 Zeichen lang sein.';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Bitte Passwort bestätigen.';
    if (v != passwordController.text) {
      return 'Die Passwörter stimmen nicht überein.';
    }
    return null;
  }

  /// Schritt 1: Formulardaten prüfen und 6-stelligen Bestätigungscode per E-Mail senden.
  Future<void> handleStartRegistration() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _errorMessage = '';
      _legalError = false;
    });

    final formValid = _formKey.currentState!.validate();
    if (!_acceptedLegal) {
      setState(() {
        _legalError = true;
        _errorMessage =
            'Bitte bestätige die AGB und die Kenntnisnahme der Datenschutzerklärung.';
      });
      return;
    }
    if (!formValid) return;

    final email = emailController.text.trim();
    setState(() => _isLoading = true);

    try {
      final userId = await AuthService().startEmailOtpRegistration(email);
      if (!mounted) return;
      otpController.clear();
      setState(() {
        _pendingUserId = userId;
        _otpStep = true;
        _errorMessage = '';
      });
      _startResendCooldown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpFocus.requestFocus();
      });
    } catch (e) {
      debugPrint('Error sending registration OTP: $e');
      if (!mounted) return;
      setState(() => _errorMessage = _prettyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Schritt 2: 6-stelligen Code prüfen, Konto finalisieren & Profil in `core_db.users` anlegen.
  Future<void> handleVerifyOtp() async {
    FocusScope.of(context).unfocus();
    final code = otpController.text.trim();
    if (code.length != 6) {
      setState(
        () => _errorMessage = 'Bitte gib den 6-stelligen Code aus deiner E-Mail ein.',
      );
      return;
    }

    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final phone = phoneController.text.trim();
    final password = passwordController.text;
    final fullName = '$firstName $lastName'.trim();

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await AuthService().completeEmailOtpRegistration(
        userId: _pendingUserId,
        otpCode: code,
        password: password,
        name: fullName,
        phone: phone,
        legalAccepted: _acceptedLegal,
      );

      if (!mounted) return;

      if (result.alreadyExisted) {
        final existingUser = await DatabaseService().getUserInformation();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Konto existiert bereits – du wurdest direkt angemeldet. Dein bisheriges Passwort bleibt unverändert.',
            ),
          ),
        );
        if (existingUser != null && existingUser.flightSchools.isNotEmpty) {
          Navigator.pushNamedAndRemoveUntil(context, '/main', (_) => false);
          return;
        }
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const OnboardingChoiceView(isInitialOnboarding: true),
        ),
        (_) => false,
      );
    } catch (e) {
      debugPrint('Error verifying registration OTP: $e');
      if (!mounted) return;
      setState(() => _errorMessage = _prettyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> handleResendOtp() async {
    if (_resendingOtp || _isLoading || _resendCooldownSec > 0) return;
    setState(() {
      _resendingOtp = true;
      _errorMessage = '';
    });

    try {
      final email = emailController.text.trim();
      final userId = await AuthService().startEmailOtpRegistration(email);
      if (!mounted) return;
      setState(() => _pendingUserId = userId);
      _startResendCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Neuer 6-stelliger Code an $email gesendet.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _prettyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _resendingOtp = false);
    }
  }

  void _backToFormStep() {
    _cooldownTimer?.cancel();
    setState(() {
      _otpStep = false;
      _pendingUserId = '';
      _resendCooldownSec = 0;
      _errorMessage = '';
      otpController.clear();
    });
  }

  Future<void> handleOAuthRegister(enums.OAuthProvider provider) async {
    FocusScope.of(context).unfocus();
    if (!_acceptedLegal) {
      setState(() {
        _legalError = true;
        _errorMessage =
            'Bitte bestätige vor der Registrierung die AGB und die Kenntnisnahme der Datenschutzerklärung.';
      });
      return;
    }
    setState(() {
      _errorMessage = '';
      _legalError = false;
      _oauthLoading = provider;
    });

    try {
      final loggedIn = await AuthService().loginWithOAuth(provider);
      if (!mounted) return;
      if (loggedIn) {
        final user = await DatabaseService().getUserInformation();
        if (!mounted) return;
        if (user != null && user.flightSchools.isNotEmpty) {
          Navigator.pushReplacementNamed(context, '/main');
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const OnboardingChoiceView(isInitialOnboarding: true),
            ),
            (_) => false,
          );
        }
      }
    } catch (e) {
      debugPrint('Error during OAuth registration: $e');
      if (!mounted) return;
      final label = provider == enums.OAuthProvider.google ? 'Google' : 'Apple';
      setState(() => _errorMessage = '$label-Registrierung fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _oauthLoading = null);
    }
  }

  Widget _buildErrorBanner(ThemeData theme, ColorScheme cs) {
    if (_errorMessage.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          _errorMessage,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onErrorContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildRegistrationForm(ThemeData theme, ColorScheme cs) {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('register_step_form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Konto erstellen',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Erstelle dein Tragegurt-Konto für Season Planner & Inventar Manager.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: firstNameController,
                  focusNode: _firstNameFocus,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Vorname',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => _validateRequired(v, 'Vorname'),
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_lastNameFocus),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: lastNameController,
                  focusNode: _lastNameFocus,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nachname',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => _validateRequired(v, 'Nachname'),
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_emailFocus),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: emailController,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'E-Mail',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: _validateEmail,
            onFieldSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_phoneFocus),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: phoneController,
            focusNode: _phoneFocus,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(
              labelText: 'Telefon (optional)',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: _validatePhoneOptional,
            onFieldSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_passwordFocus),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'Passwort',
              prefixIcon: const Icon(Icons.lock_outline),
              helperText: 'Mindestens 8 Zeichen, keine Leerzeichen.',
              suffixIcon: IconButton(
                tooltip: _obscurePassword
                    ? 'Passwort anzeigen'
                    : 'Passwort verbergen',
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: _validatePassword,
            onFieldSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_confirmPasswordFocus),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: confirmPasswordController,
            focusNode: _confirmPasswordFocus,
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Passwort bestätigen',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscureConfirmPassword
                    ? 'Passwort anzeigen'
                    : 'Passwort verbergen',
                onPressed: () {
                  setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  );
                },
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: _validateConfirmPassword,
            onFieldSubmitted: (_) => handleStartRegistration(),
          ),
          const SizedBox(height: 14),
          LegalConsentCheckbox(
            value: _acceptedLegal,
            showError: _legalError,
            onChanged: (v) {
              setState(() {
                _acceptedLegal = v;
                if (v) {
                  _legalError = false;
                  if (_errorMessage.contains('Datenschutzerklärung')) {
                    _errorMessage = '';
                  }
                }
              });
            },
          ),
          _buildErrorBanner(theme, cs),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: (_isLoading || _oauthLoading != null)
                  ? null
                  : AppTheme.primaryGlow,
            ),
            child: SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: (_isLoading || _oauthLoading != null)
                    ? null
                    : handleStartRegistration,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Bestätigungscode senden'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Wir senden dir zur Bestätigung einen 6-stelligen Code per E-Mail.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SocialAuthButtons(
            disabled: _isLoading,
            loadingProvider: _oauthLoading,
            onProviderSelected: handleOAuthRegister,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Bereits ein Konto?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              TextButton(
                onPressed: (_isLoading || _oauthLoading != null)
                    ? null
                    : () => Navigator.pop(context),
                child: const Text('Anmelden'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOtpVerificationStep(ThemeData theme, ColorScheme cs) {
    final email = emailController.text.trim();
    return Column(
      key: const ValueKey('register_step_otp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              color: AppTheme.primaryColor,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'E-Mail bestätigen',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            children: [
              const TextSpan(
                text: 'Wir haben einen 6-stelligen Bestätigungscode an ',
              ),
              TextSpan(
                text: email,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const TextSpan(
                text: ' gesendet. Bitte prüfe auch deinen Spam-Ordner.',
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        TextField(
          controller: otpController,
          focusNode: _otpFocus,
          enabled: !_isLoading,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 10,
          ),
          decoration: const InputDecoration(
            labelText: '6-stelliger Code',
            hintText: '000000',
            counterText: '',
          ),
          onChanged: (val) {
            if (_errorMessage.isNotEmpty) {
              setState(() => _errorMessage = '');
            }
            if (val.trim().length == 6 && !_isLoading) {
              handleVerifyOtp();
            }
          },
          onSubmitted: (_) => handleVerifyOtp(),
        ),
        _buildErrorBanner(theme, cs),
        const SizedBox(height: 18),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: _isLoading ? null : AppTheme.primaryGlow,
          ),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isLoading ? null : handleVerifyOtp,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Registrierung abschließen'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: _isLoading ? null : _backToFormStep,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('E-Mail ändern'),
            ),
            TextButton(
              onPressed: (_isLoading || _resendingOtp || _resendCooldownSec > 0)
                  ? null
                  : handleResendOtp,
              child: Text(
                _resendingOtp
                    ? 'Wird gesendet…'
                    : _resendCooldownSec > 0
                        ? 'Erneut senden (${_resendCooldownSec}s)'
                        : 'Code erneut senden',
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: !_otpStep,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _otpStep && !_isLoading) {
          _backToFormStep();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_otpStep ? 'Code bestätigen' : 'Registrieren'),
          leading: _otpStep
              ? IconButton(
                  tooltip: 'Zurück zum Formular',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _isLoading ? null : _backToFormStep,
                )
              : null,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SoftCard(
                      radius: 24,
                      padding: const EdgeInsets.all(20),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: _otpStep
                            ? _buildOtpVerificationStep(theme, cs)
                            : _buildRegistrationForm(theme, cs),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const LegalFooterLinks(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _prettyErrorMessage(Object e) {
    if (e is AppwriteException) {
      final type = (e.type ?? '').toLowerCase();
      final code = e.code ?? 0;
      if (type == 'user_already_exists' || code == 409) {
        return 'Ein Konto mit dieser E-Mail existiert bereits. Bitte melde dich an.';
      }
      if (type == 'invalid_email') {
        return 'Bitte gib eine gültige E-Mail-Adresse ein.';
      }
      if (type == 'invalid_password') {
        return 'Das Passwort erfüllt nicht die Anforderungen.';
      }
      if (type == 'general_rate_limit_exceeded' || code == 429) {
        return 'Zu viele Versuche. Bitte warte kurz und versuche es erneut.';
      }
      return AuthService.formatAuthError(e);
    }
    return 'Registrierung fehlgeschlagen: $e';
  }
}
