import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:season_planner/core/data/models/role_document_model.dart';
import 'package:url_launcher/url_launcher.dart';

/// Rendert Markdown-Dokumente nativ im Design der App – inkl. externer URLs,
/// Appwrite-Storage-Bilder und eingebetteter Base64-Bilder (`data:image/...`).
class MarkdownDocumentBody extends StatelessWidget {
  final String contentMd;
  final bool scrollable;
  final EdgeInsets padding;

  const MarkdownDocumentBody({
    super.key,
    required this.contentMd,
    this.scrollable = true,
    this.padding = const EdgeInsets.all(16),
  });

  Widget _buildImage(BuildContext context, Uri uri, String? alt) {
    final raw = uri.toString();
    final cs = Theme.of(context).colorScheme;

    if (raw.startsWith('data:image/')) {
      try {
        final commaIdx = raw.indexOf(',');
        if (commaIdx > 0) {
          final bytes = base64Decode(raw.substring(commaIdx + 1));
          return _framedImage(
            context,
            Image.memory(bytes, fit: BoxFit.contain),
            alt,
          );
        }
      } catch (_) {}
    }

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return _framedImage(
        context,
        Image.network(
          raw,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const SizedBox(
              height: 140,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
          errorBuilder: (_, __, ___) => _missingImageBox(
            cs,
            alt?.isNotEmpty == true ? alt! : 'Bild konnte nicht geladen werden',
          ),
        ),
        alt,
      );
    }

    return _missingImageBox(
      cs,
      'Lokales Bild nicht hochgeladen: ${alt?.isNotEmpty == true ? alt : raw}',
    );
  }

  Widget _framedImage(BuildContext context, Widget image, String? alt) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 420),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: image,
            ),
          ),
          if (alt != null && alt.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              alt.trim(),
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _missingImageBox(ColorScheme cs, String label) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _styleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: cs.onSurface,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: cs.primary,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
      p: theme.textTheme.bodyMedium?.copyWith(
        height: 1.5,
        color: cs.onSurface,
      ),
      blockquoteDecoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: cs.primary, width: 4),
        ),
      ),
      blockquotePadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      tableBorder: TableBorder.all(color: cs.outlineVariant, width: 1),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _styleSheet(context);
    Future<void> handleLink(String text, String? href, String title) async {
      if (href == null || href.trim().isEmpty) return;
      final uri = Uri.tryParse(href.trim());
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

    if (scrollable) {
      return Markdown(
        data: contentMd,
        padding: padding,
        selectable: true,
        styleSheet: sheet,
        onTapLink: handleLink,
        imageBuilder: (uri, title, alt) => _buildImage(context, uri, alt),
      );
    }

    return Padding(
      padding: padding,
      child: MarkdownBody(
        data: contentMd,
        selectable: true,
        styleSheet: sheet,
        onTapLink: handleLink,
        imageBuilder: (uri, title, alt) => _buildImage(context, uri, alt),
      ),
    );
  }
}

/// Vollbild-Ansicht einer Arbeitsanweisung im App-Design.
class MarkdownDocumentView extends StatelessWidget {
  final RoleDocument document;

  const MarkdownDocumentView({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          document.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'v${document.version}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: MarkdownDocumentBody(
              contentMd: document.contentMd,
              scrollable: true,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hilfsfunktion zum Anzeigen einer geladenen PNG-Unterschrift.
class SignaturePreviewBox extends StatelessWidget {
  final Future<Uint8List?> bytesFuture;

  const SignaturePreviewBox({super.key, required this.bytesFuture});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 110,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return Text(
            'Unterschriftsbild nicht verfügbar.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
          );
        }
        return Container(
          width: double.infinity,
          height: 130,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Image.memory(bytes, fit: BoxFit.contain),
        );
      },
    );
  }
}
