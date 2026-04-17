import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';
import '../models/user.dart';
import '../models/bank_account.dart';
import '../models/wallet.dart';
import '../models/transaction.dart';
import '../models/qr_code.dart';
import '../models/notification_settings.dart';
import '../services/deduplication_service.dart';
import 'auth_interceptor.dart';

/// Backend API Service for QR Payment System
/// Handles all communication with the backend server
class BackendApi {
  // Configuration - uses AppConfig.current.baseUrl
  static String get baseUrl => AppConfig.current.baseUrl;
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  final Dio _dio;
  final FlutterSecureStorage _secureStorage;
  final DeduplicationService _dedup = DeduplicationService();

  // Singleton pattern
  static final BackendApi _instance = BackendApi._internal();
  factory BackendApi() => _instance;

  BackendApi._internal()
    : _secureStorage = const FlutterSecureStorage(),
      _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: connectionTimeout,
          receiveTimeout: receiveTimeout,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      ) {
    _setupInterceptors();
  }

  /// Setup interceptors for authentication and error handling.
  /// Uses AuthInterceptor with token refresh support (P0-1).
  void _setupInterceptors() {
    _dio.interceptors.add(
      AuthInterceptor(
        dio: _dio,
        secureStorage: _secureStorage,
        onForceLogout: () {
          // Force logout is handled by AuthProvider.forceLogout()
          // which is called from the widget tree.
          // The interceptor triggers this callback but doesn't
          // directly navigate — it just clears auth state.
        },
      ),
    );
  }

  // ==================== Authentication ====================

  /// Store authentication token securely
  Future<void> saveAuthToken(String token) async {
    await _secureStorage.write(key: 'auth_token', value: token);
  }

  /// Retrieve stored authentication token
  Future<String?> getAuthToken() async {
    return await _secureStorage.read(key: 'auth_token');
  }

  /// Store refresh token securely
  Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: 'refresh_token', value: token);
  }

  /// Retrieve stored refresh token
  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: 'refresh_token');
  }

  /// Store user ID
  Future<void> saveUserId(String userId) async {
    await _secureStorage.write(key: 'user_id', value: userId);
  }

  /// Get stored user ID
  Future<String?> getUserId() async {
    return await _secureStorage.read(key: 'user_id');
  }

  /// Clear all authentication data
  Future<void> clearAuthData() async {
    await _secureStorage.deleteAll();
  }

  /// Login with email and password
  Future<ApiResponse<LoginResponse>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      final data = response.data;
      final accessToken = data['accessToken'] as String;
      final refreshToken = data['refreshToken'] as String?;
      final user = User.fromJson(data['user']);

      // Save auth data
      await saveAuthToken(accessToken);
      if (refreshToken != null) {
        await saveRefreshToken(refreshToken);
      }
      await saveUserId(user.id);

      return ApiResponse.success(data: LoginResponse(accessToken: accessToken, refreshToken: refreshToken, user: user));
    } on DioException catch (e) {
      // Check if this is a password reset required response (403)
      if (e.response?.statusCode == 403 &&
          e.response?.data?['requiresPasswordReset'] == true) {
        return ApiResponse.error(
          message: 'Password reset required',
          statusCode: 403,
          requiresPasswordReset: true,
          userId: e.response?.data?['userId'],
        );
      }
      return ApiResponse.error(
        message:
            e.response?.data['message'] ?? 'Login failed. Please try again.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Register new user
  Future<ApiResponse<LoginResponse>> register({
    required String email,
    required String password,
    required String name,
    required String phone,
    required UserRole role,
    String? businessName,
    String? businessAddress,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'name': name,
          'phone': phone,
          'role': role.name,
          'business_name': businessName,
          'business_address': businessAddress,
        },
      );

      final data = response.data;

      // Validate response data before casting
      if (data == null) {
        return ApiResponse.error(message: 'Invalid response from server.');
      }

      // Check for backend error response
      if (data['success'] == false) {
        return ApiResponse.error(
          message: data['message'] ?? 'Registration failed.',
          statusCode: response.statusCode,
        );
      }

      final accessToken = data['accessToken'] as String?;
      final refreshToken = data['refreshToken'] as String?;
      final userData = data['user'];

      if (accessToken == null || accessToken.isEmpty) {
        return ApiResponse.error(
          message: 'Authentication token missing from response.',
        );
      }

      if (userData == null) {
        return ApiResponse.error(message: 'User data missing from response.');
      }

      final user = User.fromJson(userData);

      await saveAuthToken(accessToken);
      if (refreshToken != null) {
        await saveRefreshToken(refreshToken);
      }
      await saveUserId(user.id);

      return ApiResponse.success(data: LoginResponse(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
      ));
    } on DioException catch (e) {
      // Handle validation errors (422)
      if (e.response?.statusCode == 422) {
        final errors = e.response?.data['errors'];
        if (errors != null && errors is Map) {
          final errorMessages = errors.values
              .expand((e) => e is List ? e : [e])
              .join(', ');
          return ApiResponse.error(
            message: 'Validation failed: $errorMessages',
            statusCode: 422,
          );
        }
      }

      return ApiResponse.error(
        message:
            e.response?.data['message'] ??
            'Registration failed. Please try again.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred: $e');
    }
  }

  /// Logout user
  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {
      // Ignore errors on logout
    } finally {
      await clearAuthData();
    }
  }

  /// Send password reset link to email
  Future<ApiResponse<bool>> sendPasswordResetLink({required String email}) async {
    try {
      await _dio.post(
        '/auth/forgot-password',
        data: {'email': email},
      );

      return ApiResponse.success(data: true);
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to send reset link.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Reset password (for password migration or regular reset)
  Future<ApiResponse<LoginResponse>> resetPassword({
    required String userId,
    String? currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/reset-password',
        data: {
          'userId': userId,
          if (currentPassword != null) 'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );

      final data = response.data;

      if (data['success'] != true) {
        return ApiResponse.error(
          message: data['message'] ?? 'Password reset failed.',
          statusCode: response.statusCode,
        );
      }

      final accessToken = data['accessToken'] as String?;
      final refreshToken = data['refreshToken'] as String?;
      final userData = data['user'];

      if (accessToken == null || userData == null) {
        return ApiResponse.error(message: 'Invalid response from server.');
      }

      final user = User.fromJson(userData);

      await saveAuthToken(accessToken);
      if (refreshToken != null) {
        await saveRefreshToken(refreshToken);
      }
      await saveUserId(user.id);

      return ApiResponse.success(data: LoginResponse(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
      ));
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Password reset failed.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Verify if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getAuthToken();
    if (token == null) return false;

    try {
      await _dio.get('/auth/verify');
      return true;
    } catch (_) {
      await clearAuthData();
      return false;
    }
  }

  // ==================== User Profile ====================

  /// Get current user profile
  Future<ApiResponse<User>> getCurrentUser() async {
    return _dedup.dedup('GET:/user/profile', () async {
    try {
      final response = await _dio.get('/user/profile');
      return ApiResponse.success(data: User.fromJson(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to fetch profile.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
    });
  }

  /// Update user profile
  Future<ApiResponse<User>> updateProfile({
    String? name,
    String? phone,
    String? businessName,
    String? businessAddress,
  }) async {
    try {
      final response = await _dio.put(
        '/user/profile',
        data: {
          'name': name,
          'phone': phone,
          'business_name': businessName,
          'business_address': businessAddress,
        },
      );

      return ApiResponse.success(data: User.fromJson(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to update profile.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Change PIN
  /// PINs are hashed before transmission (P2-1).
  Future<ApiResponse<bool>> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final userId = await getUserId();
    final currentPinHash = userId != null ? _hashPin(currentPin, userId) : null;
    final newPinHash = userId != null ? _hashPin(newPin, userId) : null;

    try {
      await _dio.put(
        '/user/pin',
        data: {
          if (currentPinHash != null) 'current_pin_hash': currentPinHash,
          if (newPinHash != null) 'new_pin_hash': newPinHash,
        },
      );

      return ApiResponse.success(data: true);
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to change PIN.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Set new PIN (first time setup, no current PIN required)
  Future<ApiResponse<bool>> setPin({required String newPin}) async {
    try {
      await _dio.put(
        '/user/pin',
        data: {'new_pin': newPin},
      );

      return ApiResponse.success(data: true);
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to set PIN.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Verify PIN for payment
  /// PIN is hashed before transmission (P2-1).
  Future<ApiResponse<bool>> verifyPin(String pin) async {
    final userId = await getUserId();
    final pinHash = userId != null ? _hashPin(pin, userId) : null;

    try {
      final response = await _dio.post(
        '/user/pin/verify',
        data: {
          if (pinHash != null) 'pin_hash': pinHash,
        },
      );
      return ApiResponse.success(data: response.data['valid'] == true);
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'PIN verification failed.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Upload profile picture
  Future<ApiResponse<String>> uploadAvatar(File imageFile) async {
    try {
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(
          imageFile.path,
          filename: 'avatar${imageFile.path.substring(imageFile.path.lastIndexOf('.'))}',
        ),
      });

      final response = await _dio.put(
        '/user/avatar',
        data: formData,
      );

      return ApiResponse.success(data: response.data['avatar_url'] as String);
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to upload avatar.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Get notification settings
  Future<ApiResponse<NotificationSettings>> getNotificationSettings() async {
    try {
      final response = await _dio.get('/user/notifications');
      return ApiResponse.success(
        data: NotificationSettings.fromJson(response.data['settings']),
      );
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to fetch settings.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Update notification settings
  Future<ApiResponse<NotificationSettings>> updateNotificationSettings({
    bool? smsMoneyIn,
    bool? smsMoneyOut,
  }) async {
    try {
      final response = await _dio.put(
        '/user/notifications',
        data: {
          if (smsMoneyIn != null) 'sms_money_in': smsMoneyIn,
          if (smsMoneyOut != null) 'sms_money_out': smsMoneyOut,
        },
      );
      return ApiResponse.success(
        data: NotificationSettings.fromJson(response.data['settings']),
      );
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to update settings.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Get bank account
  Future<ApiResponse<BankAccount?>> getBankAccount() async {
    try {
      final response = await _dio.get('/user/bank-account');
      if (response.data['bank_account'] == null) {
        return ApiResponse.success(data: null);
      }
      return ApiResponse.success(
        data: BankAccount.fromJson(response.data['bank_account']),
      );
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to fetch bank account.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Save bank account
  Future<ApiResponse<BankAccount>> saveBankAccount({
    required String bankName,
    required String accountNumber,
    required String accountName,
  }) async {
    try {
      final response = await _dio.put(
        '/user/bank-account',
        data: {
          'bank_name': bankName,
          'account_number': accountNumber,
          'account_name': accountName,
        },
      );
      return ApiResponse.success(
        data: BankAccount.fromJson(response.data['bank_account']),
      );
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to save bank account.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Delete bank account
  Future<ApiResponse<bool>> deleteBankAccount() async {
    try {
      await _dio.delete('/user/bank-account');
      return ApiResponse.success(data: true);
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to delete bank account.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  // ==================== Wallet ====================

  /// Get user wallet
  Future<ApiResponse<Wallet>> getWallet() async {
    return _dedup.dedup('GET:/wallet', () async {
    try {
      final response = await _dio.get('/wallet');
      return ApiResponse.success(data: Wallet.fromJson(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to fetch wallet.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
    });
  }

  /// Top up wallet (mock - instant credit for testing)
  Future<ApiResponse<TopUpResponse>> topUpWallet({
    required double amount,
    String? paymentMethod,
  }) async {
    try {
      final response = await _dio.post(
        '/wallet/topup',
        data: {'amount': amount, 'payment_method': paymentMethod ?? 'card'},
      );

      return ApiResponse.success(data: TopUpResponse.fromJson(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data?['message'] ?? 'Top-up failed.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Initialize Paystack payment for wallet topup
  Future<ApiResponse<PaystackInitResponse>> initializeWalletTopup({
    required double amount,
  }) async {
    try {
      final response = await _dio.post(
        '/wallet/topup/paystack-initialize',
        data: {'amount': amount},
      );

      if (response.data['success'] != true) {
        return ApiResponse.error(
          message: response.data['message'] ?? 'Failed to initialize payment',
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.success(data: PaystackInitResponse.fromJson(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data?['message'] ?? 'Failed to initialize payment',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Manual wallet funding (testing only)
  Future<ApiResponse<TopUpResponse>> manualFundWallet({
    required double amount,
    String? reason,
  }) async {
    try {
      final response = await _dio.post(
        '/wallet/manual-fund',
        data: {'amount': amount, 'reason': reason ?? 'Testing'},
      );

      return ApiResponse.success(data: TopUpResponse.fromJson(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data?['message'] ?? 'Failed to fund wallet',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Verify top-up payment
  Future<ApiResponse<Wallet>> verifyTopUp({required String reference}) async {
    try {
      final response = await _dio.post(
        '/wallet/topup/verify',
        data: {'reference': reference},
      );

      return ApiResponse.success(
        data: Wallet.fromJson(response.data['wallet']),
      );
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Payment verification failed.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Get wallet ledger entries
  Future<ApiResponse<List<WalletLedgerEntry>>> getWalletLedger({int page = 1, int limit = 20}) async {
    try {
      final response = await _dio.get(
        '/wallet/ledger',
        queryParameters: {'page': page, 'limit': limit},
      );

      final List<dynamic> ledgerList = response.data['ledger'] ?? [];
      return ApiResponse.success(
        data: ledgerList.map((e) => WalletLedgerEntry.fromJson(e)).toList(),
      );
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data?['message'] ?? 'Failed to fetch wallet history',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  // ==================== QR Code ====================

  /// Generate QR code for merchant
  Future<ApiResponse<QRCodeData>> generateQRCode() async {
    try {
      final response = await _dio.post('/qr/generate');

      final data = response.data;
      if (data == null) {
        return ApiResponse.error(message: 'Invalid response from server.');
      }

      if (data['success'] != true) {
        return ApiResponse.error(
          message: data['message'] ?? 'Failed to generate QR code.',
          statusCode: response.statusCode,
        );
      }

      final qrData = data['qr_data'];
      if (qrData == null) {
        return ApiResponse.error(message: 'QR data missing from response.');
      }

      return ApiResponse.success(
        data: QRCodeData.fromJson(qrData as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data?['message'] ?? 'Failed to generate QR code.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred: $e');
    }
  }

  /// Verify scanned QR code
  Future<ApiResponse<QRVerificationResponse>> verifyQRCode({
    required String qrPayload,
  }) async {
    try {
      final response = await _dio.post(
        '/qr/verify',
        data: {'qr_payload': qrPayload},
      );

      // Check if response indicates failure
      if (response.data is Map) {
        if (response.data['success'] == false) {
          return ApiResponse.error(
            message: response.data['message']?.toString() ?? 'Invalid QR code.',
          );
        }
        return ApiResponse.success(
          data: QRVerificationResponse.fromJson(response.data),
        );
      }

      // Response is not JSON or unexpected format
      return ApiResponse.error(message: 'Invalid QR code.');
    } on DioException catch (e) {
      String errorMessage = 'Invalid QR code.';
      if (e.response?.statusCode == 404) {
        errorMessage = 'Merchant not found. Please ask for a new QR code.';
      } else if (e.response?.statusCode == 400) {
        errorMessage = 'This QR code is not valid for payments.';
      } else if (e.response?.data is Map) {
        final msg = e.response?.data['message'];
        if (msg != null) {
          errorMessage = msg.toString();
        }
      }
      return ApiResponse.error(
        message: errorMessage,
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'Invalid QR code.');
    }
  }

  // ==================== Transactions ====================

  /// Initiate payment to merchant
  ///
  /// PIN is hashed with the user ID as salt before transmission (P2-1).
  /// The backend must accept `pin_hash` as an alternative to `pin`.
  /// If the backend doesn't support `pin_hash`, it falls back to `pin`.
  ///
  /// [idempotencyKey] prevents duplicate charges on retry — if the server
  /// already processed a payment with this key, it returns the original
  /// transaction instead of creating a new one.
  Future<ApiResponse<Transaction>> initiatePayment({
    required String merchantId,
    required double amount,
    required String pin,
    String? description,
    String? idempotencyKey,
  }) async {
    // Hash PIN with user ID as salt for secure transmission
    final userId = await getUserId();
    final pinHash = userId != null ? _hashPin(pin, userId) : null;

    try {
      final response = await _dio.post(
        '/transactions/payment',
        data: {
          'merchant_id': merchantId,
          'amount': amount,
          if (pinHash != null) 'pin_hash': pinHash,
          if (description != null) 'description': description,
          if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
        },
      );

      // If the server indicates this was a duplicate (idempotency hit),
      // the transaction data is still valid — treat it as success.
      return ApiResponse.success(
        data: Transaction.fromJson(response.data['transaction']),
      );
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Payment failed.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Get transaction history
  Future<ApiResponse<List<Transaction>>> getTransactions({
    int page = 1,
    int limit = 20,
    TransactionType? type,
    TransactionStatus? status,
  }) async {
    try {
      final response = await _dio.get(
        '/transactions',
        queryParameters: {
          'page': page,
          'limit': limit,
          'type': type?.name,
          'status': status?.name,
        },
      );

      final List<dynamic> transactions = response.data['transactions'];
      return ApiResponse.success(
        data: transactions.map((t) => Transaction.fromJson(t)).toList(),
      );
    } on DioException catch (e) {
      String errorMessage = 'Failed to fetch transactions.';
      if (e.response?.data is Map) {
        errorMessage = e.response?.data['message'] ?? errorMessage;
      }
      return ApiResponse.error(
        message: errorMessage,
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  /// Get single transaction details
  Future<ApiResponse<Transaction>> getTransactionDetails({
    required String transactionId,
  }) async {
    try {
      final response = await _dio.get('/transactions/$transactionId');
      return ApiResponse.success(data: Transaction.fromJson(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to fetch transaction.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
  }

  // ==================== Merchant Specific ====================

  /// Get merchant statistics
  Future<ApiResponse<MerchantStats>> getMerchantStats() async {
    return _dedup.dedup('GET:/merchant/stats', () async {
    try {
      final response = await _dio.get('/merchant/stats');
      return ApiResponse.success(data: MerchantStats.fromJson(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to fetch statistics.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
    });
  }

  /// Get merchant transactions
  Future<ApiResponse<List<Transaction>>> getMerchantTransactions({
    int page = 1,
    int limit = 20,
  }) async {
    return _dedup.dedup('GET:/merchant/transactions?page=$page', () async {
    try {
      final response = await _dio.get(
        '/merchant/transactions',
        queryParameters: {'page': page, 'limit': limit},
      );

      final List<dynamic> transactions = response.data['transactions'];
      return ApiResponse.success(
        data: transactions.map((t) => Transaction.fromJson(t)).toList(),
      );
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to fetch transactions.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
    });
  }

  // ==================== Paystack Payments ====================

  /// Initialize Paystack payment
  Future<PaystackPaymentResponse> initializePaystackPayment({
    required double amount,
    required String merchantId,
    required String merchantName,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/paystack/initialize',
        data: {
          'amount': amount,
          'merchant_id': merchantId,
          'merchant_name': merchantName,
        },
      );

      return PaystackPaymentResponse.fromJson(response.data);
    } on DioException catch (e) {
      return PaystackPaymentResponse(
        success: false,
        message: e.response?.data['message'] ?? 'Failed to initialize payment',
      );
    } catch (e) {
      return PaystackPaymentResponse(
        success: false,
        message: 'An unexpected error occurred',
      );
    }
  }

  /// Verify Paystack payment status after returning from Paystack
  Future<Map<String, dynamic>> verifyPayment({required String reference}) async {
    try {
      final response = await _dio.get('/payments/paystack/verify/$reference');
      return {
        'success': response.data['success'] ?? false,
        'status': response.data['status'] ?? 'unknown',
        'amount': (response.data['amount'] as num?)?.toDouble(),
        'merchant_id': response.data['merchant_id'],
        'merchant_name': response.data['merchant_name'],
        'reference': response.data['reference'],
        'completed_at': response.data['completed_at'],
        'message': response.data['message'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'status': 'error',
        'message': e.response?.data['message'] ?? 'Failed to verify payment',
      };
    } catch (e) {
      return {
        'success': false,
        'status': 'error',
        'message': 'An unexpected error occurred',
      };
    }
  }

  /// Get list of banks that support Pay with Bank
  Future<ApiResponse<List<PaystackBank>>> getBanks() async {
    return _dedup.dedup('GET:/payments/paystack/banks', () async {
    try {
      final response = await _dio.get('/payments/paystack/banks');
      final List<dynamic> banks = response.data['banks'] ?? [];
      return ApiResponse.success(
        data: banks.map((b) => PaystackBank.fromJson(b)).toList(),
      );
    } on DioException catch (e) {
      return ApiResponse.error(
        message: e.response?.data['message'] ?? 'Failed to fetch banks.',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: 'An unexpected error occurred.');
    }
    });
  }

  /// Initialize bank charge (direct redirect to bank's login page)
  Future<BankChargeResponse> initializeBankCharge({
    required double amount,
    required String merchantId,
    required String merchantName,
    required String bankCode,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/paystack/bank-charge',
        data: {
          'amount': amount,
          'merchant_id': merchantId,
          'merchant_name': merchantName,
          'bank_code': bankCode,
        },
      );

      return BankChargeResponse.fromJson(response.data);
    } on DioException catch (e) {
      return BankChargeResponse(
        success: false,
        message: e.response?.data['message'] ?? 'Failed to initiate bank charge',
      );
    } catch (e) {
      return BankChargeResponse(
        success: false,
        message: 'An unexpected error occurred',
      );
    }
  }

  // ==================== Utility Methods ====================

  /// Hash a PIN with the user ID as salt for secure transmission.
  /// The backend must accept `pin_hash` as an alternative to `pin`.
  /// Uses SHA-256 for one-way hashing — the original PIN is never sent.
  String _hashPin(String pin, String userId) {
    final saltedPin = '$pin:$userId';
    final bytes = utf8.encode(saltedPin);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Set base URL (for different environments)
  void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }

  /// Get current base URL
  String getBaseUrl() {
    return _dio.options.baseUrl;
  }

  /// Enable/disable debug logging
  void enableDebugLogging(bool enabled) {
    if (enabled) {
      _dio.interceptors.add(
        LogInterceptor(requestBody: true, responseBody: true, error: true),
      );
    }
  }

  /// Get the full URL for an avatar image path
  String getAvatarUrl(String? avatarPath) {
    if (avatarPath == null || avatarPath.isEmpty) return '';
    if (avatarPath.startsWith('http')) return avatarPath;
    return '$baseUrl$avatarPath'.replaceAll('/api/v1', '');
  }
}

// ==================== Response Models ====================

/// Generic API Response wrapper
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final int? statusCode;
  final bool requiresPasswordReset;
  final String? userId;

  ApiResponse._({
    required this.success,
    this.data,
    this.message,
    this.statusCode,
    this.requiresPasswordReset = false,
    this.userId,
  });

  factory ApiResponse.success({T? data}) {
    return ApiResponse._(success: true, data: data);
  }

  factory ApiResponse.error({
    String? message,
    int? statusCode,
    bool requiresPasswordReset = false,
    String? userId,
  }) {
    return ApiResponse._(
      success: false,
      message: message,
      statusCode: statusCode,
      requiresPasswordReset: requiresPasswordReset,
      userId: userId,
    );
  }
}

/// Login response data
class LoginResponse {
  final String accessToken;
  final String? refreshToken;
  final User user;

  LoginResponse({required this.accessToken, this.refreshToken, required this.user});
}

/// Top-up response data
class TopUpResponse {
  final String reference;
  final String? paymentUrl;
  final Wallet wallet;

  TopUpResponse({
    required this.reference,
    this.paymentUrl,
    required this.wallet,
  });

  factory TopUpResponse.fromJson(Map<String, dynamic> json) {
    return TopUpResponse(
      reference: json['reference'] ?? '',
      paymentUrl: json['payment_url'],
      wallet: Wallet.fromJson(json['wallet']),
    );
  }
}

/// Paystack initialization response
class PaystackInitResponse {
  final String paymentUrl;
  final String reference;
  final String? accessCode;

  PaystackInitResponse({
    required this.paymentUrl,
    required this.reference,
    this.accessCode,
  });

  factory PaystackInitResponse.fromJson(Map<String, dynamic> json) {
    return PaystackInitResponse(
      paymentUrl: json['payment_url'] ?? '',
      reference: json['reference'] ?? '',
      accessCode: json['access_code'],
    );
  }
}

/// Wallet ledger entry (for wallet history)
class WalletLedgerEntry {
  final String id;
  final String walletId;
  final String type;
  final double amount;
  final double balanceBefore;
  final double balanceAfter;
  final String reference;
  final String? description;
  final DateTime createdAt;

  WalletLedgerEntry({
    required this.id,
    required this.walletId,
    required this.type,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.reference,
    this.description,
    required this.createdAt,
  });

  factory WalletLedgerEntry.fromJson(Map<String, dynamic> json) {
    final amountValue = json['amount'];
    final balanceBeforeValue = json['balance_before'];
    final balanceAfterValue = json['balance_after'];

    double parseAmount(dynamic val) {
      if (val is double) return val;
      if (val is int) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    return WalletLedgerEntry(
      id: json['id'] ?? '',
      walletId: json['wallet_id'] ?? '',
      type: json['type'] ?? '',
      amount: parseAmount(amountValue),
      balanceBefore: parseAmount(balanceBeforeValue),
      balanceAfter: parseAmount(balanceAfterValue),
      reference: json['reference'] ?? '',
      description: json['description'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

/// QR verification response
class QRVerificationResponse {
  final String merchantId;
  final String merchantName;
  final String? merchantAddress;

  QRVerificationResponse({
    required this.merchantId,
    required this.merchantName,
    this.merchantAddress,
  });

  factory QRVerificationResponse.fromJson(Map<String, dynamic> json) {
    return QRVerificationResponse(
      merchantId: json['merchant_id'] ?? '',
      merchantName: json['merchant_name'] ?? '',
      merchantAddress: json['merchant_address'],
    );
  }
}

/// Merchant statistics
class MerchantStats {
  final int totalTransactions;
  final double totalRevenue;
  final double todayRevenue;
  final double weekRevenue;
  final double monthRevenue;

  MerchantStats({
    required this.totalTransactions,
    required this.totalRevenue,
    required this.todayRevenue,
    required this.weekRevenue,
    required this.monthRevenue,
  });

  factory MerchantStats.fromJson(Map<String, dynamic> json) {
    return MerchantStats(
      totalTransactions: json['total_transactions'] ?? 0,
      totalRevenue: (json['total_revenue'] ?? 0).toDouble(),
      todayRevenue: (json['today_revenue'] ?? 0).toDouble(),
      weekRevenue: (json['week_revenue'] ?? 0).toDouble(),
      monthRevenue: (json['month_revenue'] ?? 0).toDouble(),
    );
  }
}

/// Paystack payment response
class PaystackPaymentResponse {
  final bool success;
  final String? paymentUrl;
  final String? reference;
  final String? message;

  PaystackPaymentResponse({
    required this.success,
    this.paymentUrl,
    this.reference,
    this.message,
  });

  factory PaystackPaymentResponse.fromJson(Map<String, dynamic> json) {
    return PaystackPaymentResponse(
      success: json['success'] == true,
      paymentUrl: json['payment_url'],
      reference: json['reference'],
      message: json['message'],
    );
  }
}

/// Paystack bank that supports "Pay with Bank"
class PaystackBank {
  final String name;
  final String code;
  final String slug;

  PaystackBank({required this.name, required this.code, required this.slug});

  factory PaystackBank.fromJson(Map<String, dynamic> json) {
    return PaystackBank(
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      slug: json['slug'] ?? '',
    );
  }
}

/// Response from bank charge initialization
class BankChargeResponse {
  final bool success;
  final String? authUrl;
  final String? reference;
  final String? message;

  BankChargeResponse({
    required this.success,
    this.authUrl,
    this.reference,
    this.message,
  });

  factory BankChargeResponse.fromJson(Map<String, dynamic> json) {
    return BankChargeResponse(
      success: json['success'] == true,
      authUrl: json['auth_url'],
      reference: json['reference'],
      message: json['message'],
    );
  }
}

// ==================== Exception Classes ====================

/// Custom exception for API errors
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException({required this.message, this.statusCode});

  @override
  String toString() => 'ApiException: $message';
}

/// Network exception
class NetworkException extends ApiException {
  NetworkException()
    : super(message: 'Network error. Please check your connection.');
}

/// Unauthorized exception
class UnauthorizedException extends ApiException {
  UnauthorizedException()
    : super(message: 'Session expired. Please login again.', statusCode: 401);
}

/// Validation exception
class ValidationException extends ApiException {
  final Map<String, String>? errors;

  ValidationException({String? message, this.errors})
    : super(message: message ?? 'Validation failed');
}
