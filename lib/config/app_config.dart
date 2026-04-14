/// Application configuration for different environments
class AppConfig {
  final String baseUrl;
  final String environment;
  final bool enableDebugLogging;
  final bool allowCleartext;
  final bool enableCertificatePinning;
  final List<String> certificatePins;

  const AppConfig({
    required this.baseUrl,
    required this.environment,
    this.enableDebugLogging = false,
    this.allowCleartext = false,
    this.enableCertificatePinning = false,
    this.certificatePins = const [],
  });

  /// Development configuration (use 10.0.2.2 for Android emulator to access host localhost)
  static const development = AppConfig(
    baseUrl: 'http://172.16.2.90:3000/api/v1',
    // baseUrl: 'http://192.168.115.53:3000/api/v1',
    environment: 'development',
    enableDebugLogging: true,
    allowCleartext: true,
    enableCertificatePinning: false,
  );

  /// Staging configuration
  static const staging = AppConfig(
    baseUrl: 'https://staging-api.qrpay.com/api/v1',
    environment: 'staging',
    enableDebugLogging: true,
    allowCleartext: false,
    enableCertificatePinning: true,
    certificatePins: [
      // Add staging certificate SHA-256 hashes here
    ],
  );

  /// Production configuration
  static const production = AppConfig(
    baseUrl: 'https://api.qrpay.com/api/v1',
    environment: 'production',
    enableDebugLogging: false,
    allowCleartext: false,
    enableCertificatePinning: true,
    certificatePins: [
      // Add production certificate SHA-256 hashes here
      // Pin to CA intermediate certificate to reduce rotation impact
    ],
  );

  /// Current active configuration
  /// Change this to switch environments
  static const current = development;
}

/// Usage in your code:
///
/// import 'package:qr_payment_system/config/app_config.dart';
///
/// final api = BackendApi();
/// api.setBaseUrl(AppConfig.current.baseUrl);
///
/// // Or directly in BackendApi:
/// static const String baseUrl = AppConfig.current.baseUrl;