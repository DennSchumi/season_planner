import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:season_planer/services/auth_service.dart';

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
  final TextEditingController confirmPasswordController = TextEditingController();

  final FocusNode _firstNameFocus = FocusNode();
  final FocusNode _lastNameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();

    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  String? _validateRequired(String? value, String fieldName) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$fieldName is required';
    return null;
  }

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(v)) return 'Please enter a valid email';
    return null;
  }

  String? _validatePhoneOptional(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null; // optional
    // Simple, permissive phone validation (digits, spaces, +, -, parentheses)
    final phoneRegex = RegExp(r'^[0-9+\-\s()]{6,}$');
    if (!phoneRegex.hasMatch(v)) return 'Please enter a valid phone number';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.contains(' ')) return 'Password must not contain spaces';
    if (v.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Please confirm your password';
    if (v != passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> handleRegistration() async {
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = '');

    if (!_formKey.currentState!.validate()) return;

    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text; // keep as is

    final fullName = '$firstName $lastName'.trim();

    setState(() => _isLoading = true);
    setState(() => _isLoading = true);
    try {
      await AuthService().signUp(email, password, fullName);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Account created. Please check your email to verify/sign in.'),
        ),
      );
    } catch (e) {
      debugPrint('Error during registration: $e');

      final msg = _prettyErrorMessage(e);

      if (!mounted) return;

      setState(() {
        _errorMessage = msg;
      });

      FocusScope.of(context).unfocus();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

    @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withOpacity(0.10),
              cs.secondary.withOpacity(0.08),
              cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Register',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Fill in your details to create an account.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.75),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),

                          // Names row
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: firstNameController,
                                  focusNode: _firstNameFocus,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'First name',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                  validator: (v) => _validateRequired(v, 'First name'),
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
                                    labelText: 'Last name',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                  validator: (v) => _validateRequired(v, 'Last name'),
                                  onFieldSubmitted: (_) =>
                                      FocusScope.of(context).requestFocus(_emailFocus),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Email
                          TextFormField(
                            controller: emailController,
                            focusNode: _emailFocus,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: _validateEmail,
                            onFieldSubmitted: (_) =>
                                FocusScope.of(context).requestFocus(_phoneFocus),
                          ),

                          const SizedBox(height: 12),

                          // Phone (optional)
                          TextFormField(
                            controller: phoneController,
                            focusNode: _phoneFocus,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.telephoneNumber],
                            decoration: const InputDecoration(
                              labelText: 'Phone (optional)',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: _validatePhoneOptional,
                            onFieldSubmitted: (_) =>
                                FocusScope.of(context).requestFocus(_passwordFocus),
                          ),

                          const SizedBox(height: 12),

                          // Password
                          TextFormField(
                            controller: passwordController,
                            focusNode: _passwordFocus,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              helperText: 'At least 8 characters, no spaces.',
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
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

                          // Confirm Password
                          TextFormField(
                            controller: confirmPasswordController,
                            focusNode: _confirmPasswordFocus,
                            obscureText: _obscureConfirmPassword,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Confirm password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscureConfirmPassword ? 'Show password' : 'Hide password',
                                onPressed: () {
                                  setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                                },
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: _validateConfirmPassword,
                            onFieldSubmitted: (_) => handleRegistration(),
                          ),

                          if (_errorMessage.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.errorContainer.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _errorMessage,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onErrorContainer,
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 14),

                          SizedBox(
                            height: 50,
                            child: FilledButton(
                              onPressed: _isLoading ? null : handleRegistration,
                              child: _isLoading
                                  ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                                  : const Text('Create account'),
                            ),
                          ),

                          const SizedBox(height: 10),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Already have an account?',
                                style: theme.textTheme.bodyMedium,
                              ),
                              TextButton(
                                onPressed: _isLoading ? null : () => Navigator.pop(context),
                                child: const Text('Log in'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
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
      final type = e.type ?? '';
      final code = e.code ?? 0;

      if (type == 'user_already_exists' || code == 409) {
        return 'An account with this email already exists. Please log in or use a different email.';
      }
      if (type == 'invalid_email') {
        return 'Please enter a valid email address.';
      }
      if (type == 'invalid_password') {
        return 'Your password is not valid. Please choose a stronger password.';
      }
      if (type == 'general_rate_limit_exceeded' || code == 429) {
        return 'Too many attempts. Please wait a moment and try again.';
      }
      if (type == 'network_error') {
        return 'Network error. Please check your internet connection and try again.';
      }

      if ((e.message ?? '').isNotEmpty) {
        return e.message!;
      }
      return 'Registration failed (Appwrite error). Please try again.';
    }

    return 'Registration failed. Please try again. (${e.toString()})';
  }

}
