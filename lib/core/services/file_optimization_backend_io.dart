import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:season_planner/core/services/file_optimization_backend_stub.dart';

export 'package:season_planner/core/services/file_optimization_backend_stub.dart'
    show RenderedPdfPage;

class _ImageOptimizeArgs {
  final Uint8List bytes;
  final int maxDimension;
  final int quality;
  final bool outputPng;

  const _ImageOptimizeArgs({
    required this.bytes,
    required this.maxDimension,
    required this.quality,
    required this.outputPng,
  });
}

Uint8List? _optimizeImageIsolate(_ImageOptimizeArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return null;

  var work = img.bakeOrientation(decoded);
  final maxSide = math.max(work.width, work.height);
  if (maxSide > args.maxDimension) {
    final resizeWidth = work.width >= work.height ? args.maxDimension : null;
    final resizeHeight = work.height > work.width ? args.maxDimension : null;
    work = img.copyResize(
      work,
      width: resizeWidth,
      height: resizeHeight,
      interpolation: img.Interpolation.linear,
    );
  }

  if (args.outputPng) {
    return Uint8List.fromList(img.encodePng(work, level: 6));
  }

  // Transparente Bereiche auf Weiß setzen, damit JPEG keinen schwarzen Hintergrund bekommt
  if (work.hasAlpha) {
    final flat = img.Image(width: work.width, height: work.height);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, work);
    work = flat;
  }

  return Uint8List.fromList(img.encodeJpg(work, quality: args.quality));
}

class _BgraToJpegArgs {
  final Uint8List bgraBytes;
  final int width;
  final int height;
  final int quality;

  const _BgraToJpegArgs({
    required this.bgraBytes,
    required this.width,
    required this.height,
    required this.quality,
  });
}

Uint8List _encodeBgraToJpegIsolate(_BgraToJpegArgs args) {
  final image = img.Image.fromBytes(
    width: args.width,
    height: args.height,
    bytes: args.bgraBytes.buffer,
    bytesOffset: args.bgraBytes.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: args.quality));
}

Future<Uint8List?> platformOptimizeImage({
  required Uint8List bytes,
  required String mimeType,
  required int maxDimension,
  required int quality,
  bool outputPng = false,
}) async {
  try {
    return await compute(
      _optimizeImageIsolate,
      _ImageOptimizeArgs(
        bytes: bytes,
        maxDimension: maxDimension,
        quality: quality,
        outputPng: outputPng,
      ),
    );
  } catch (e) {
    debugPrint('platformOptimizeImage (IO) error: $e');
    return null;
  }
}

Future<List<RenderedPdfPage>?> platformRenderPdfPages({
  required Uint8List bytes,
  required int maxDimension,
  required int quality,
  int maxPages = 40,
}) async {
  PdfDocument? doc;
  try {
    doc = await PdfDocument.openData(bytes);
    final pageCount = math.min(doc.pages.length, maxPages);
    if (pageCount == 0) return null;

    final renderedPages = <RenderedPdfPage>[];
    for (int i = 0; i < pageCount; i++) {
      final page = doc.pages[i];
      final widthPt = page.width;
      final heightPt = page.height;
      final maxPt = math.max(widthPt, heightPt);
      final scale = (maxDimension / maxPt).clamp(0.5, 2.2);
      final targetW = math.max(1, (widthPt * scale).round());
      final targetH = math.max(1, (heightPt * scale).round());

      final pdfImg = await page.render(
        fullWidth: targetW.toDouble(),
        fullHeight: targetH.toDouble(),
        width: targetW,
        height: targetH,
        backgroundColor: 0xFFFFFFFF,
      );
      if (pdfImg == null) continue;

      try {
        // Eigene Kopie erzeugen, bevor der native Pdfium-Buffer sofort freigegeben wird
        final bgraCopy = Uint8List.fromList(pdfImg.pixels);
        final w = pdfImg.width;
        final h = pdfImg.height;
        pdfImg.dispose();

        final jpeg = await compute(
          _encodeBgraToJpegIsolate,
          _BgraToJpegArgs(
            bgraBytes: bgraCopy,
            width: w,
            height: h,
            quality: quality,
          ),
        );
        renderedPages.add(
          RenderedPdfPage(
            widthPt: widthPt,
            heightPt: heightPt,
            jpegBytes: jpeg,
          ),
        );
      } catch (e) {
        try {
          pdfImg.dispose();
        } catch (_) {}
        rethrow;
      }
    }
    return renderedPages.isEmpty ? null : renderedPages;
  } catch (e) {
    debugPrint('platformRenderPdfPages (IO) error: $e');
    return null;
  } finally {
    await doc?.dispose();
  }
}
