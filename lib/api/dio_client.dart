import 'package:dio/dio.dart';
import '../config/app_config.dart';

/// Factory for creating configured Dio instances with optimized settings.
///
/// Creates separate Dio instances for different timeout profiles:
/// - Standard: For normal reads (wallet, profile, transactions)
/// - Fast: For quick reads that should fail fast (auth verify, QR verify)
/// - Long: For operations that may take longer (avatar upload, file operations)
///
/// Also configures HTTP/2 support (automatic via dart:io when server supports it).
class DioClient {
  DioClient._();

  /// Create a standard Dio instance with optimized settings.
  static Dio createDio({
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.current.baseUrl,
        connectTimeout: connectTimeout ?? const Duration(seconds: 10),
        receiveTimeout: receiveTimeout ?? const Duration(seconds: 15),
        sendTimeout: sendTimeout ?? const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        responseType: ResponseType.json,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    return dio;
  }

  /// Create a fast-fail Dio instance for quick reads.
  /// Shorter timeouts to fail fast on poor connections.
  static Dio createFastDio() {
    return createDio(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
    );
  }

  /// Create a long-timeout Dio instance for file uploads and heavy operations.
  static Dio createLongDio() {
    return createDio(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    );
  }
}