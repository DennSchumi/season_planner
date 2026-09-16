import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerView extends StatefulWidget {
  const QRScannerView({Key? key}) : super(key: key);

  @override
  _QRScannerViewState createState() => _QRScannerViewState();
}

class _QRScannerViewState extends State<QRScannerView> {
  final MobileScannerController cameraController = MobileScannerController();

  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String code = barcodes.first.rawValue ?? "";
      if (code.isNotEmpty) {
        cameraController.stop();
        Navigator.pop(context, code);
      }
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Code scannen'),
      ),
      body: MobileScanner(
        controller: cameraController,
        onDetect: _onDetect,
      ),
    );
  }
}
