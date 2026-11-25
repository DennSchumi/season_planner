import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:season_planner/core/theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Zeigt die persönliche oder Flugschul-Kalender-Abo-URL (ICS-Feed) mit
/// 1-Klick-Buttons für Apple Kalender, Google Kalender, Outlook.com & Microsoft 365
/// sowie manuellem Kopieren.
Future<void> showIcsSubscriptionDialog({
  required BuildContext context,
  required String title,
  required String subtitle,
  required Future<String> Function() loadUrl,
  Future<String> Function()? onRegenerateUrl,
  String? calendarName,
}) async {
  Future<String> future = loadUrl();
  final resolvedName = (calendarName != null && calendarName.trim().isNotEmpty)
      ? calendarName.trim()
      : title;

  String toWebcal(String rawUrl) {
    if (rawUrl.startsWith('https://')) {
      return 'webcal://${rawUrl.substring('https://'.length)}';
    }
    if (rawUrl.startsWith('http://')) {
      return 'webcal://${rawUrl.substring('http://'.length)}';
    }
    return rawUrl;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      bool copied = false;
      bool regenerating = false;
      String? statusMessage;
      bool statusIsError = false;

      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final cs = Theme.of(ctx).colorScheme;

          Future<void> openService({
            required String label,
            required Uri uri,
            required String fallbackCopyUrl,
          }) async {
            try {
              final launched = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
              if (!ctx.mounted) return;
              if (launched) {
                setLocal(() {
                  statusMessage = '$label wurde geöffnet.';
                  statusIsError = false;
                });
              } else {
                await Clipboard.setData(ClipboardData(text: fallbackCopyUrl));
                if (!ctx.mounted) return;
                setLocal(() {
                  copied = true;
                  statusMessage =
                      '$label konnte nicht direkt geöffnet werden – Abo-Link wurde stattdessen kopiert.';
                  statusIsError = true;
                });
              }
            } catch (_) {
              await Clipboard.setData(ClipboardData(text: fallbackCopyUrl));
              if (!ctx.mounted) return;
              setLocal(() {
                copied = true;
                statusMessage =
                    '$label wird auf diesem Gerät nicht direkt unterstützt – Abo-Link wurde kopiert.';
                statusIsError = true;
              });
            }
          }

          return FutureBuilder<String>(
            future: future,
            builder: (ctx, snapshot) {
              final feedUrl = snapshot.data ?? '';

              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.rss_feed, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(title)),
                  ],
                ),
                content: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (snapshot.hasError)
                          Text(
                            'Link konnte nicht erzeugt werden: ${snapshot.error}',
                            style: TextStyle(color: cs.error),
                          )
                        else ...[
                          Text(
                            'Direkt abonnieren',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _CalendarProviderButton(
                                  icon: Icons.apple,
                                  iconColor: cs.onSurface,
                                  label: 'Apple Kalender',
                                  onPressed: () => openService(
                                    label: 'Apple Kalender',
                                    uri: Uri.parse(toWebcal(feedUrl)),
                                    fallbackCopyUrl: feedUrl,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _CalendarProviderButton(
                                  icon: Icons.calendar_month_outlined,
                                  iconColor: const Color(0xFF4285F4),
                                  label: 'Google Kalender',
                                  onPressed: () {
                                    final googleUri = Uri.parse(
                                      'https://calendar.google.com/calendar/r?cid=${Uri.encodeComponent(toWebcal(feedUrl))}',
                                    );
                                    openService(
                                      label: 'Google Kalender',
                                      uri: googleUri,
                                      fallbackCopyUrl: feedUrl,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _CalendarProviderButton(
                                  icon: Icons.mail_outline,
                                  iconColor: const Color(0xFF0078D4),
                                  label: 'Outlook.com',
                                  onPressed: () {
                                    final outlookUri = Uri.parse(
                                      'https://outlook.live.com/calendar/0/addfromweb'
                                      '?url=${Uri.encodeComponent(feedUrl)}'
                                      '&name=${Uri.encodeComponent(resolvedName)}',
                                    );
                                    openService(
                                      label: 'Outlook.com',
                                      uri: outlookUri,
                                      fallbackCopyUrl: feedUrl,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _CalendarProviderButton(
                                  icon: Icons.business_outlined,
                                  iconColor: const Color(0xFFD83B01),
                                  label: 'Microsoft 365',
                                  onPressed: () {
                                    final m365Uri = Uri.parse(
                                      'https://outlook.office.com/calendar/0/addfromweb'
                                      '?url=${Uri.encodeComponent(feedUrl)}'
                                      '&name=${Uri.encodeComponent(resolvedName)}',
                                    );
                                    openService(
                                      label: 'Microsoft 365',
                                      uri: m365Uri,
                                      fallbackCopyUrl: feedUrl,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Hinweis: Google Kalender aktualisiert abonnierte ICS-Feeds nur ca. alle 12–24 Stunden.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const Divider(height: 22),
                          Text(
                            'Oder Link manuell kopieren (ICS-Feed)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: SelectableText(
                              feedUrl,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 14,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Dieser private Abo-Link enthält einen persönlichen Zugangstoken – bitte vertraulich behandeln.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (onRegenerateUrl != null) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                ),
                                onPressed: regenerating
                                    ? null
                                    : () async {
                                        final confirm = await showDialog<bool>(
                                          context: ctx,
                                          builder: (c2) => AlertDialog(
                                            title: const Text(
                                              'Abo-Link zurücksetzen?',
                                            ),
                                            content: const Text(
                                              'Der bisherige Kalender-Link wird sofort gesperrt und durch einen neuen ersetzt. Bestehende Kalender-Abos müssen danach mit dem neuen Link verbunden werden.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(c2, false),
                                                child: const Text('Abbrechen'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(c2, true),
                                                child: const Text(
                                                  'Neu generieren',
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm != true || !ctx.mounted) {
                                          return;
                                        }
                                        setLocal(() {
                                          regenerating = true;
                                          copied = false;
                                          statusMessage = null;
                                          future = onRegenerateUrl();
                                        });
                                        try {
                                          await future;
                                          if (!ctx.mounted) return;
                                          setLocal(() {
                                            regenerating = false;
                                            statusMessage =
                                                'Neuer Abo-Link erstellt – der alte Link ist jetzt ungültig.';
                                            statusIsError = false;
                                          });
                                        } catch (e) {
                                          if (!ctx.mounted) return;
                                          setLocal(() {
                                            regenerating = false;
                                            statusMessage =
                                                'Zurücksetzen fehlgeschlagen: $e';
                                            statusIsError = true;
                                          });
                                        }
                                      },
                                icon: const Icon(Icons.refresh, size: 16),
                                label: Text(
                                  regenerating
                                      ? 'Wird neu generiert…'
                                      : 'Link neu generieren (alten sperren)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                          if (statusMessage != null) ...[
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  statusIsError
                                      ? Icons.info_outline
                                      : Icons.check_circle,
                                  size: 16,
                                  color: statusIsError
                                      ? AppTheme.warningColor
                                      : AppTheme.successColor,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    statusMessage!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: statusIsError
                                          ? AppTheme.warningColor
                                          : AppTheme.successColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else if (copied) ...[
                            const SizedBox(height: 10),
                            const Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: AppTheme.successColor,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Abo-Link in die Zwischenablage kopiert.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.successColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Schließen'),
                  ),
                  if (snapshot.hasData)
                    FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: feedUrl));
                        if (ctx.mounted) {
                          setLocal(() {
                            copied = true;
                            statusMessage = null;
                          });
                        }
                      },
                      icon: Icon(copied ? Icons.check : Icons.copy, size: 18),
                      label: Text(copied ? 'Kopiert' : 'Link kopieren'),
                    ),
                ],
              );
            },
          );
        },
      );
    },
  );
}

class _CalendarProviderButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onPressed;

  const _CalendarProviderButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: cs.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
