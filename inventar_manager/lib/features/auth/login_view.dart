import 'package:appwrite/enums.dart' as enums;
import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/core/theme.dart';
import 'package:inventar_manager/core/widgets/legal_links.dart';
import 'package:inventar_manager/core/widgets/ui_primitives.dart';
import 'package:inventar_manager/features/auth/register_view.dart';
import 'package:inventar_manager/features/auth/social_auth_buttons.dart';
import 'package:inventar_manager/features/dashboard/main_scaffold.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _isLoading = false;
  enums.OAuthProvider? _oauthLoading;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _navigateRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterView()),
    );
  }

  Future<void> _navigateForgotPassword() async {
    final resetEmailCtrl = TextEditingController(
      text: _emailController.text.trim(),
    );
    bool sending = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Passwort zurücksetzen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Gib deine E-Mail-Adresse ein. Wir senden dir einen Link zum Zurücksetzen deines Passworts.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: resetEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !sending,
                    decoration: const InputDecoration(
                      labelText: 'E-Mail-Adresse',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.pop(ctx),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: sending
                      ? null
                      : () async {
                          final mail = resetEmailCtrl.text.trim();
                          if (mail.isEmpty || !mail.contains('@')) {
                            setLocal(() {
                              errorText =
                                  'Bitte gib eine gültige E-Mail-Adresse ein.';
                            });
                            return;
                          }
                          setLocal(() {
                            sending = true;
                            errorText = null;
                          });
                          try {
                            await AuthService().resetPassword(mail);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Passwort-Reset-E-Mail an $mail gesendet (bitte auch Spam prüfen).',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            setLocal(() {
                              sending = false;
                              errorText = AuthService.formatAuthError(e);
                            });
                          }
                        },
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Link senden'),
                ),
              ],
            );
          },
        );
      },
    );

    resetEmailCtrl.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final result = await AuthService().login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;

      if (result.isEmpty) {
        Navigator.of(context).pushReplacement(
          fadePageRoute(const MainScaffold()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Anmeldung fehlgeschlagen: $result'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Anmeldung fehlgeschlagen: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOAuthLogin(enums.OAuthProvider provider) async {
    FocusScope.of(context).unfocus();
    setState(() => _oauthLoading = provider);

    try {
      final loggedIn = await AuthService().loginWithOAuth(provider);
      if (!mounted) return;
      if (loggedIn) {
        Navigator.of(context).pushReplacement(
          fadePageRoute(const MainScaffold()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final label = provider == enums.OAuthProvider.google ? 'Google' : 'Apple';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label-Anmeldung fehlgeschlagen: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _oauthLoading = null);
    }
  }

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Bitte E-Mail-Adresse eingeben.';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(v)) {
      return 'Bitte eine gültige E-Mail-Adresse eingeben.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Bitte Passwort eingeben.';
    if (v.length < 6) {
      return 'Das Passwort muss mindestens 6 Zeichen lang sein.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSigningIn = _isLoading || _oauthLoading != null;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: AppTheme.primaryGlow,
                            ),
                            child: const Icon(
                              Icons.inventory_2_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Inventar Manager',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ausrüstung & Wartung im Griff',
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
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _emailController,
                                focusNode: _emailFocus,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'E-Mail',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: _validateEmail,
                                onFieldSubmitted: (_) {
                                  FocusScope.of(
                                    context,
                                  ).requestFocus(_passwordFocus);
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: 'Passwort',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Passwort anzeigen'
                                        : 'Passwort verbergen',
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: _validatePassword,
                                onFieldSubmitted: (_) => _handleLogin(),
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : _navigateForgotPassword,
                                  child: const Text('Passwort vergessen?'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: isSigningIn
                                      ? null
                                      : AppTheme.primaryGlow,
                                ),
                                child: SizedBox(
                                  height: 52,
                                  child: FilledButton(
                                    onPressed:
                                        isSigningIn ? null : _handleLogin,
                                    child: _isLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Anmelden'),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SocialAuthButtons(
                                disabled: _isLoading,
                                loadingProvider: _oauthLoading,
                                onProviderSelected: _handleOAuthLogin,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Noch kein Konto?',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          TextButton(
                            onPressed: isSigningIn ? null : _navigateRegister,
                            child: const Text('Registrieren'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '© ${DateTime.now().year} Tragegurt · Inventar Manager',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      const LegalFooterLinks(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            ignoring: !isSigningIn,
            child: AnimatedOpacity(
              opacity: isSigningIn ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                color: theme.scaffoldBackgroundColor.withValues(alpha: 0.72),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
