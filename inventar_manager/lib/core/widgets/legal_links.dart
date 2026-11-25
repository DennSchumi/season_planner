import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:inventar_manager/core/appwrite_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// Öffnet eine zentrale Rechtsseite (Impressum, Datenschutz, AGB) im Browser.
Future<void> openLegalUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seite konnte nicht geöffnet werden: $url')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seite konnte nicht geöffnet werden: $url')),
      );
    }
  }
}

/// Kompakter Footer mit klickbaren Links zu Impressum, Datenschutz & AGB.
class LegalFooterLinks extends StatelessWidget {
  const LegalFooterLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final linkStyle = TextStyle(
      fontSize: 12,
      color: cs.onSurfaceVariant,
      decoration: TextDecoration.underline,
      decorationColor: cs.onSurfaceVariant.withValues(alpha: 0.5),
    );
    final dotStyle = TextStyle(
      fontSize: 12,
      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
    );

    Widget buildLink(String label, String url) {
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => openLegalUrl(context, url),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Text(label, style: linkStyle),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 2,
      children: [
        buildLink('Impressum', AppwriteConfig.legalImprintUrl),
        Text('·', style: dotStyle),
        buildLink('Datenschutz', AppwriteConfig.legalPrivacyUrl),
        Text('·', style: dotStyle),
        buildLink('AGB', AppwriteConfig.legalTermsUrl),
      ],
    );
  }
}

/// Pflicht-Checkbox für die Registrierung mit direkt klickbaren Links zu AGB &
/// Datenschutzerklärung (DSGVO-saubere Trennung: AGB akzeptieren, Datenschutz
/// zur Kenntnis nehmen).
class LegalConsentCheckbox extends StatefulWidget {
  final bool value;
  final bool showError;
  final ValueChanged<bool> onChanged;

  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.showError = false,
  });

  @override
  State<LegalConsentCheckbox> createState() => _LegalConsentCheckboxState();
}

class _LegalConsentCheckboxState extends State<LegalConsentCheckbox> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => openLegalUrl(context, AppwriteConfig.legalTermsUrl);
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => openLegalUrl(context, AppwriteConfig.legalPrivacyUrl);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasErr = widget.showError && !widget.value;

    final linkStyle = TextStyle(
      color: cs.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: cs.primary.withValues(alpha: 0.6),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hasErr
            ? cs.errorContainer.withValues(alpha: 0.35)
            : cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasErr ? cs.error : cs.outlineVariant,
          width: hasErr ? 1.3 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: widget.value,
              onChanged: (v) => widget.onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onChanged(!widget.value),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: hasErr ? cs.error : cs.onSurface,
                  ),
                  children: [
                    const TextSpan(text: 'Ich akzeptiere die '),
                    TextSpan(
                      text: 'AGB',
                      style: linkStyle,
                      recognizer: _termsTap,
                    ),
                    const TextSpan(text: ' und habe die '),
                    TextSpan(
                      text: 'Datenschutzerklärung',
                      style: linkStyle,
                      recognizer: _privacyTap,
                    ),
                    const TextSpan(text: ' zur Kenntnis genommen.'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
