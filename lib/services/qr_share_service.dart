import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Service for sharing QR codes as images via the system share sheet.
class QrShareService {
  QrShareService._();

  /// Capture a widget (the QR code) as an image and share it.
  ///
  /// [globalKey] must be attached to a `RepaintBoundary` widget
  /// that wraps the QR code.
  static Future<void> shareQrCode({
    required GlobalKey globalKey,
    String merchantName = 'merchant',
  }) async {
    try {
      // Find the RenderRepaintBoundary
      final boundary = globalKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        return;
      }

      // Capture the widget as an image
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();

      // Save to a temporary file
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/qr_code_$merchantName.png');
      await file.writeAsBytes(pngBytes);

      // Share via system share sheet
      await SharePlus.instance.share(
        ShareParams(
          text: 'Pay $merchantName via QR Pay',
          files: [XFile(file.path)],
        ),
      );
    } catch (e) {
      debugPrint('[QrShareService] Error sharing QR code: $e');
    }
  }
}