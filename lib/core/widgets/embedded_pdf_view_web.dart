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
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return _WebEmbeddedPdfView(
    bytes: bytes,
    isDark: isDark,
  );
}

class _WebEmbeddedPdfView extends StatefulWidget {
  final Uint8List bytes;
  final bool isDark;

  const _WebEmbeddedPdfView({
    required this.bytes,
    required this.isDark,
  });

  @override
  State<_WebEmbeddedPdfView> createState() => _WebEmbeddedPdfViewState();
}

class _WebEmbeddedPdfViewState extends State<_WebEmbeddedPdfView> {
  static int _viewCounter = 0;
  late final String _viewType;
  late final String _blobUrl;

  @override
  void initState() {
    super.initState();
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
    final viewerUri = Uri.base.resolve('pdfjs/viewer.html').replace(
      queryParameters: <String, String>{
        'file': _blobUrl,
        'dark': widget.isDark ? '1' : '0',
      },
    );

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = viewerUri.toString()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = widget.isDark ? '#12131A' : '#F4F4F2';
      return iframe;
    });
  }

  @override
  void dispose() {
    try {
      web.URL.revokeObjectURL(_blobUrl);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
