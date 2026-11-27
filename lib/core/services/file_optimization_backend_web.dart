import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:season_planner/core/services/file_optimization_backend_stub.dart';

export 'package:season_planner/core/services/file_optimization_backend_stub.dart'
    show RenderedPdfPage;

@JS('spOptimizeImage')
external JSPromise<JSUint8Array> _spOptimizeImage(
  JSUint8Array bytes,
  JSString mimeType,
  JSNumber maxDimension,
  JSNumber quality,
  JSBoolean outputPng,
);

@JS('spRenderPdfPagesToJpeg')
external JSPromise<JSArray<JSObject>> _spRenderPdfPagesToJpeg(
  JSUint8Array bytes,
  JSNumber maxDimension,
  JSNumber quality,
  JSNumber maxPages,
);

extension type _JsRenderedPage(JSObject _) implements JSObject {
  external JSNumber get widthPt;
  external JSNumber get heightPt;
  external JSUint8Array get bytes;
}

Future<Uint8List?> platformOptimizeImage({
  required Uint8List bytes,
  required String mimeType,
  required int maxDimension,
  required int quality,
  bool outputPng = false,
}) async {
  try {
    final jsOut = await _spOptimizeImage(
      bytes.toJS,
      mimeType.toJS,
      maxDimension.toJS,
      (quality / 100.0).toJS,
      outputPng.toJS,
    ).toDart;
    return jsOut.toDart;
  } catch (e) {
    debugPrint('platformOptimizeImage (Web) error: $e');
    return null;
  }
}

Future<List<RenderedPdfPage>?> platformRenderPdfPages({
  required Uint8List bytes,
  required int maxDimension,
  required int quality,
  int maxPages = 40,
}) async {
  try {
    final jsArr = await _spRenderPdfPagesToJpeg(
      bytes.toJS,
      maxDimension.toJS,
      (quality / 100.0).toJS,
      maxPages.toJS,
    ).toDart;
    final list = jsArr.toDart;
    if (list.isEmpty) return null;

    final pages = <RenderedPdfPage>[];
    for (final raw in list) {
      final item = _JsRenderedPage(raw);
      pages.add(
        RenderedPdfPage(
          widthPt: item.widthPt.toDartDouble,
          heightPt: item.heightPt.toDartDouble,
          jpegBytes: item.bytes.toDart,
        ),
      );
    }
    return pages;
  } catch (e) {
    debugPrint('platformRenderPdfPages (Web) error: $e');
    return null;
  }
}
