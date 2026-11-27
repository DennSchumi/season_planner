import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget buildEmbeddedPdfView({
  required BuildContext context,
  required Uint8List bytes,
  required String fileName,
  VoidCallback? onOpenExternal,
  bool pointerEventsEnabled = true,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return _WebEmbeddedPdfView(
    bytes: bytes,
    fileName: fileName,
    isDark: isDark,
    pointerEventsEnabled: pointerEventsEnabled,
  );
}

class _WebEmbeddedPdfView extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final bool isDark;
  final bool pointerEventsEnabled;

  const _WebEmbeddedPdfView({
    required this.bytes,
    required this.fileName,
    required this.isDark,
    required this.pointerEventsEnabled,
  });

  @override
  State<_WebEmbeddedPdfView> createState() => _WebEmbeddedPdfViewState();
}

class _WebEmbeddedPdfViewState extends State<_WebEmbeddedPdfView> {
  static int _viewCounter = 0;
  late final String _viewType;
  late final String _blobUrl;
  web.HTMLIFrameElement? _iframe;
  bool _effectivePointerEvents = true;

  @override
  void initState() {
    super.initState();
    _effectivePointerEvents = widget.pointerEventsEnabled;
    _viewCounter++;
    _viewType = 'sp_embedded_pdf_$_viewCounter';

    final blob = web.Blob(
      <JSAny>[widget.bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    _blobUrl = web.URL.createObjectURL(blob);

    // Lokal mitgehosteter PDF.js-Canvas-Renderer (web/pdfjs/viewer.html):
    // funktioniert zuverlässig inline auf Android-Chrome, iOS Safari & Desktop
    // und bleibt 100 % lokal im Browser (kein externes CDN, keine Drittserver).
    final safeName = widget.fileName.trim().isEmpty
        ? 'dokument.pdf'
        : (widget.fileName.toLowerCase().endsWith('.pdf')
            ? widget.fileName.trim()
            : '${widget.fileName.trim()}.pdf');
    final viewerUri = Uri.base.resolve('pdfjs/viewer.html').replace(
      queryParameters: <String, String>{
        'file': _blobUrl,
        'name': safeName,
        'dark': widget.isDark ? '1' : '0',
      },
    );

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = viewerUri.toString()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.pointerEvents = _effectivePointerEvents ? 'auto' : 'none'
        ..style.backgroundColor = widget.isDark ? '#12131A' : '#F4F4F2';
      _iframe = iframe;
      return iframe;
    });
  }

  void _syncPointerEvents() {
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    _effectivePointerEvents = widget.pointerEventsEnabled && isCurrentRoute;
    _applyPointerEvents();
  }

  void _applyPointerEvents() {
    final iframe = _iframe;
    if (iframe == null) return;
    final value = _effectivePointerEvents ? 'auto' : 'none';
    iframe.style.pointerEvents = value;
    final parent = iframe.parentElement;
    if (parent != null && parent.isA<web.HTMLElement>()) {
      (parent as web.HTMLElement).style.pointerEvents = value;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPointerEvents();
  }

  @override
  void didUpdateWidget(covariant _WebEmbeddedPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPointerEvents();
  }

  @override
  void dispose() {
    _iframe = null;
    try {
      web.URL.revokeObjectURL(_blobUrl);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncPointerEvents();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: HtmlElementView(
        viewType: _viewType,
        onPlatformViewCreated: (_) => _applyPointerEvents(),
      ),
    );
  }
}
