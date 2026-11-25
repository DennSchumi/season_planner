import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:season_planner/core/services/file_download_helper.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';

Widget buildEmbeddedPdfView({
  required BuildContext context,
  required Uint8List bytes,
  required String fileName,
  VoidCallback? onOpenExternal,
}) {
  return _NativeEmbeddedPdfView(
    bytes: bytes,
    fileName: fileName,
    onOpenExternal: onOpenExternal,
  );
}

class _NativeEmbeddedPdfView extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final VoidCallback? onOpenExternal;

  const _NativeEmbeddedPdfView({
    required this.bytes,
    required this.fileName,
    this.onOpenExternal,
  });

  @override
  State<_NativeEmbeddedPdfView> createState() => _NativeEmbeddedPdfViewState();
}

class _NativeEmbeddedPdfViewState extends State<_NativeEmbeddedPdfView> {
  final PdfViewerController _controller = PdfViewerController();
  int _currentPage = 1;
  int _pageCount = 0;
  bool _saving = false;

  Future<void> _saveFile() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final safeName = widget.fileName.toLowerCase().endsWith('.pdf')
          ? widget.fileName
          : '${widget.fileName}.pdf';
      await downloadBytesFile(
        bytes: widget.bytes,
        filename: safeName,
        mimeType: 'application/pdf',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildFallbackCard(BuildContext context, {String? errorText}) {
    final cs = Theme.of(context).colorScheme;
    final sizeLabel = widget.bytes.length < 1024 * 1024
        ? '${(widget.bytes.length / 1024).toStringAsFixed(0)} KB'
        : '${(widget.bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TintedIconBadge(
              icon: Icons.picture_as_pdf_rounded,
              iconColor: AppTheme.primaryColor,
              backgroundColor: AppTheme.primaryTint,
              size: 64,
              iconSize: 32,
              radius: 20,
            ),
            const SizedBox(height: 14),
            Text(
              widget.fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              errorText ?? 'PDF-Dokument · $sizeLabel',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (widget.onOpenExternal != null)
                  FilledButton.icon(
                    onPressed: widget.onOpenExternal,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('PDF öffnen'),
                  ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _saveFile,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF12131A) : const Color(0xFFF4F4F2);
    final barBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.borderSubtle;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: bg,
        child: Column(
          children: [
            // Kompakte PDF-Toolbar (Seitenanzeige, Zoom, Speichern)
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: barBg,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Text(
                    _pageCount > 0
                        ? 'Seite $_currentPage / $_pageCount'
                        : 'PDF wird geladen…',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Verkleinern',
                    visualDensity: VisualDensity.compact,
                    iconSize: 19,
                    onPressed: _controller.isReady
                        ? () => _controller.zoomDown()
                        : null,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  IconButton(
                    tooltip: 'Vergrößern',
                    visualDensity: VisualDensity.compact,
                    iconSize: 19,
                    onPressed: _controller.isReady
                        ? () => _controller.zoomUp()
                        : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                  IconButton(
                    tooltip: 'Speichern',
                    visualDensity: VisualDensity.compact,
                    iconSize: 19,
                    onPressed: _saving ? null : _saveFile,
                    icon: const Icon(Icons.download_outlined),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PdfViewer.data(
                widget.bytes,
                sourceName: widget.fileName.isNotEmpty
                    ? widget.fileName
                    : 'document.pdf',
                controller: _controller,
                params: PdfViewerParams(
                  backgroundColor: bg,
                  margin: 10,
                  onViewerReady: (document, controller) {
                    if (!mounted) return;
                    setState(() {
                      _pageCount = document.pages.length;
                      _currentPage = controller.pageNumber ?? 1;
                    });
                  },
                  onPageChanged: (pageNumber) {
                    if (!mounted || pageNumber == null) return;
                    setState(() => _currentPage = pageNumber);
                  },
                  loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    );
                  },
                  errorBannerBuilder: (context, error, stackTrace, ref) {
                    return _buildFallbackCard(
                      context,
                      errorText:
                          'Dieses PDF konnte nicht in der Vorschau gerendert werden.',
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
