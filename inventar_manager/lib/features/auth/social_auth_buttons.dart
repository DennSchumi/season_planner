import 'package:appwrite/enums.dart' as enums;
import 'package:flutter/material.dart';

/// Kompakte nebeneinanderliegende Buttons für die Anmeldung / Registrierung
/// per Google- oder Apple-Account (Appwrite OAuth2).
class SocialAuthButtons extends StatelessWidget {
  final bool disabled;
  final enums.OAuthProvider? loadingProvider;
  final ValueChanged<enums.OAuthProvider> onProviderSelected;

  const SocialAuthButtons({
    super.key,
    this.disabled = false,
    this.loadingProvider,
    required this.onProviderSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAnyLoading = disabled || loadingProvider != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: cs.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'oder weiter mit',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(child: Divider(color: cs.outlineVariant)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: cs.outlineVariant),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: isAnyLoading
                      ? null
                      : () => onProviderSelected(enums.OAuthProvider.google),
                  child: loadingProvider == enums.OAuthProvider.google
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CustomPaint(painter: _GoogleLogoPainter()),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Google',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: cs.outlineVariant),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: isAnyLoading
                      ? null
                      : () => onProviderSelected(enums.OAuthProvider.apple),
                  child: loadingProvider == enums.OAuthProvider.apple
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.apple,
                              size: 20,
                              color: cs.onSurface,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Apple',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Mehrfarbiges Google-„G“-Logo als gestochen scharfer Vektor-Painter.
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = (w < h ? w : h) * 0.44;
    final strokeW = radius * 0.36;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.butt;

    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.15, 1.05, false, paint);

    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.90, 1.45, false, paint);

    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 2.35, 1.15, false, paint);

    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 3.50, 2.05, false, paint);

    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - strokeW * 0.05,
        center.dy - strokeW * 0.45,
        radius + strokeW * 0.48,
        strokeW * 0.90,
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
