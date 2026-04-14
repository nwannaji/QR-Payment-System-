import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token refresh interceptor for Dio.
///
/// Catches 401 responses, attempts to refresh the access token using the stored
/// refresh token, and replays all queued requests with the new token.
/// If refresh fails, forces logout via the provided callback.
///
/// Uses [QueuedInterceptorsWrapper] so that during token refresh,
/// all other requests queue and wait rather than all hitting 401 at once.
class AuthInterceptor extends QueuedInterceptorsWrapper {
  final Dio dio;
  final FlutterSecureStorage secureStorage;
  final void Function() onForceLogout;

  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;

  AuthInterceptor({
    required this.dio,
    required this.secureStorage,
    required this.onForceLogout,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await secureStorage.read(key: 'auth_token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      // Not an auth error — pass through
      handler.next(err);
      return;
    }

    // Don't try to refresh if this is already a refresh request
    if (err.requestOptions.path == '/auth/refresh' ||
        err.requestOptions.path == '/auth/login') {
      handler.next(err);
      return;
    }

    // Attempt token refresh
    final newToken = await _refreshToken();
    if (newToken != null) {
      // Retry the original request with the new token
      final options = err.requestOptions;
      options.headers['Authorization'] = 'Bearer $newToken';

      try {
        final response = await dio.fetch(options);
        handler.resolve(response);
      } on DioException catch (e) {
        handler.next(e);
      }
    } else {
      // Refresh failed — force logout
      onForceLogout();
      handler.next(err);
    }
  }

  /// Refresh the access token. Coalesces multiple concurrent refresh attempts
  /// into a single request.
  Future<String?> _refreshToken() async {
    // If already refreshing, wait for the existing refresh to complete
    if (_isRefreshing) {
      _refreshCompleter ??= Completer<String?>();
      return _refreshCompleter!.future;
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<String?>();

    try {
      final refreshToken = await secureStorage.read(key: 'refresh_token');
      if (refreshToken == null) {
        // No refresh token available
        _refreshCompleter!.complete(null);
        return null;
      }

      // Create a separate Dio instance for the refresh request to avoid interceptors
      final refreshDio = Dio(BaseOptions(
        baseUrl: dio.options.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      ));

      final response = await refreshDio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        final newAccessToken = data['accessToken'] as String?;
        final newRefreshToken = data['refreshToken'] as String?;

        if (newAccessToken != null) {
          // Save the new tokens
          await secureStorage.write(key: 'auth_token', value: newAccessToken);
          if (newRefreshToken != null) {
            await secureStorage.write(key: 'refresh_token', value: newRefreshToken);
          }

          _refreshCompleter!.complete(newAccessToken);
          return newAccessToken;
        }
      }

      // Refresh failed
      _refreshCompleter!.complete(null);
      return null;
    } catch (e) {
      _refreshCompleter!.complete(null);
      return null;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }
}