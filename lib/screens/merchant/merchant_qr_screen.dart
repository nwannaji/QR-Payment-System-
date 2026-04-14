import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/merchant_provider.dart';
import '../../services/qr_share_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common/custom_button.dart';

class MerchantQRScreen extends StatefulWidget {
  const MerchantQRScreen({super.key});

  @override
  State<MerchantQRScreen> createState() => _MerchantQRScreenState();
}

class _MerchantQRScreenState extends State<MerchantQRScreen> {
  final _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MerchantProvider>().generateQRCode();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment QR Code'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'Your Payment QR Code',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Customers can scan this code to pay you',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Consumer<MerchantProvider>(
                builder: (context, provider, _) {
                  final qrData = provider.activeQRCode;

                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (qrData == null) {
                    return Column(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: AppTheme.errorColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to generate QR code',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        CustomButton(
                          text: 'Try Again',
                          onPressed: () => provider.generateQRCode(),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      RepaintBoundary(
                        key: _qrKey,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: qrData.toQRString(),
                            version: QrVersions.auto,
                            size: 250,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: AppTheme.primaryColor,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Scan to pay',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 32),
                      CustomButton(
                        text: 'Refresh QR Code',
                        icon: Icons.refresh,
                        type: ButtonType.outline,
                        isFullWidth: true,
                        onPressed: () => provider.generateQRCode(),
                      ),
                      const SizedBox(height: 16),
                      CustomButton(
                        text: 'Share QR Code',
                        icon: Icons.share,
                        isFullWidth: true,
                        onPressed: () {
                          final user = context.read<MerchantProvider>().activeQRCode;
                          QrShareService.shareQrCode(
                            globalKey: _qrKey,
                            merchantName: user?.merchantName ?? 'merchant',
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
