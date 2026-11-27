import 'dart:typed_data';

class RenderedPdfPage {
  final double widthPt;
  final double heightPt;
  final Uint8List jpegBytes;

  const RenderedPdfPage({
    required this.widthPt,
    required this.heightPt,
    required this.jpegBytes,
  });
}

Future<Uint8List?> platformOptimizeImage({
  required Uint8List bytes,
  required String mimeType,
  required int maxDimension,
  required int quality,
  bool outputPng = false,
}) async => null;

Future<List<RenderedPdfPage>?> platformRenderPdfPages({
  required Uint8List bytes,
  required int maxDimension,
  required int quality,
  int maxPages = 40,
}) async => null;
