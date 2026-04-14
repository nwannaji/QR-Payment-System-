import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/backend_api.dart';
import '../../services/qr_parser.dart';
import '../../utils/theme.dart';
import '../../widgets/qr_scanner_overlay.dart';
import 'payment_confirmation_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController cameraController = MobileScannerController();
  final QrParser _qrParser = QrParser();
  bool _isProcessing = false;
  bool _torchEnabled = false;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;

    if (barcodes.isNotEmpty && !_isProcessing) {
      final String? rawQrData = barcodes.first.rawValue;

      if (rawQrData != null) {
        setState(() {
          _isProcessing = true;
        });

        cameraController.stop();

        // Step 1: Parse QR code locally for instant navigation (P0-2)
        final parseResult = _qrParser.parse(rawQrData);

        // Handle Paystack URLs immediately
        if (parseResult.isPaystackUrl && parseResult.paystackUrl != null) {
          await _launchPaystackUrl(parseResult.paystackUrl!);
          if (mounted) setState(() => _isProcessing = false);
          cameraController.start();
          return;
        }

        // Handle expired QR codes instantly
        if (parseResult.isExpired) {
          if (mounted) {
            _showErrorDialog('This QR code has expired. Please ask the merchant to generate a new one.');
          }
          return;
        }

        // If we have merchant info from local parse, navigate immediately
        // and verify with the server in the background
        if (parseResult.isValid &&
            parseResult.merchantId != null &&
            parseResult.merchantName != null) {
          final merchantId = parseResult.merchantId!;
          final merchantName = parseResult.merchantName!;

          // Navigate to payment screen instantly
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PaymentConfirmationScreen(
                  merchantId: merchantId,
                  merchantName: merchantName,
                ),
              ),
            ).then((_) {
              if (mounted) {
                setState(() => _isProcessing = false);
                cameraController.start();
              }
            });
          }

          // Background verification with server for security
          _verifyInBackground(rawQrData, merchantId, merchantName);
          return;
        }

        // Fallback: unrecognized format or incomplete data — verify with server
        await _verifyQRWithBackend(rawQrData);
      }
    }
  }

  /// Verify QR code with server in the background after local navigation.
  /// If server says the QR is invalid, pop the user off the payment screen.
  Future<void> _verifyInBackground(String qrPayload, String localMerchantId, String localMerchantName) async {
    try {
      final api = BackendApi();
      final response = await api.verifyQRCode(qrPayload: qrPayload);

      if (response.success && response.data != null) {
        // Server verified — check if merchant details differ
        final serverMerchantId = response.data!.merchantId;
        final serverMerchantName = response.data!.merchantName;

        if (serverMerchantId != localMerchantId || serverMerchantName != localMerchantName) {
          // Mismatch — warn the user
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('QR verification updated: $serverMerchantName'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
        // Server verified successfully — no action needed since
        // user is already on the correct payment screen
      } else if (mounted) {
        // Server says invalid — pop user off the payment screen and show error
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'QR code verification failed. The code may be invalid.'),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      // Background verification failed silently — user is already on payment screen.
      // The actual payment will validate with the server anyway.
    }
  }

  Future<void> _verifyQRWithBackend(String qrPayload) async {
    debugPrint('[SCANNER] _verifyQRWithBackend started');

    // If Paystack URL, open directly (shouldn't reach here after local parse, but safe fallback)
    if (qrPayload.startsWith('https://checkout.paystack.com/') ||
        qrPayload.startsWith('https://paystack.com/pay/')) {
      debugPrint('[SCANNER] Paystack URL detected, opening...');
      await _launchPaystackUrl(qrPayload);
      if (mounted) setState(() => _isProcessing = false);
      cameraController.start();
      return;
    }

    final api = BackendApi();
    debugPrint('[SCANNER] Calling API...');

    try {
      final response = await api.verifyQRCode(qrPayload: qrPayload);
      debugPrint('[SCANNER] API response received: ${response.success}');

      if (!mounted) {
        debugPrint('[SCANNER] Widget unmounted, aborting');
        return;
      }

      if (response.success && response.data != null) {
        debugPrint('[SCANNER] Success! Navigating...');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentConfirmationScreen(
              merchantId: response.data!.merchantId,
              merchantName: response.data!.merchantName,
            ),
          ),
        ).then((_) {
          debugPrint('[SCANNER] Returned from navigation');
          if (mounted) {
            setState(() => _isProcessing = false);
            cameraController.start();
          }
        });
      } else {
        debugPrint('[SCANNER] API returned error: ${response.message}');
        _showErrorDialog(response.message ?? 'Verification failed');
      }
    } catch (e) {
      debugPrint('[SCANNER] Exception: $e');
      if (mounted) {
        _showErrorDialog('Error: ${e.toString()}');
      }
    }

    debugPrint('[SCANNER] _verifyQRWithBackend done');
  }

  Future<void> _launchPaystackUrl(String url) async {
    final uri = Uri.parse(url);

    try {
      // Try to launch in external browser first (recommended for payment security)
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorDialog(
          'Could not open payment page. Please check your browser.',
        );
      }
    } catch (e) {
      _showErrorDialog('Error opening payment page: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.error_outline, color: AppTheme.errorColor),
                const SizedBox(width: 8),
                const Text('Scan Failed'),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _isProcessing = false;
                  });
                  cameraController.start();
                },
                child: const Text('Try Again'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan to Pay'),
        actions: [
          IconButton(
            icon: Icon(
              _torchEnabled ? Icons.flash_on : Icons.flash_off,
              color: _torchEnabled ? Colors.yellow : null,
            ),
            onPressed: () async {
              setState(() {
                _torchEnabled = !_torchEnabled;
              });
              await cameraController.toggleTorch();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: cameraController, onDetect: _handleBarcode),

          // Scanner Overlay
          Container(
            decoration: ShapeDecoration(
              shape: QrScannerOverlayShape(
                borderColor: AppTheme.primaryColor,
                borderRadius: 16,
                borderLength: 32,
                borderWidth: 4,
                cutOutSize: 280,
              ),
            ),
          ),

          // Instructions
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Point your camera at the merchant\'s QR code',
                style: TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Loading indicator
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}