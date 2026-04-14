import 'package:flutter/material.dart';
import '../models/user.dart';
import '../api/backend_api.dart';
import '../services/cache_service.dart';
import '../services/cache_keys.dart';
import '../services/prefetch_service.dart';

class AuthProvider with ChangeNotifier {
  final BackendApi _api = BackendApi();
  final CacheService _cache = CacheService();

  User? _user;
  bool _isLoading = false;
  String? _error;
  bool _isAuthenticated = false;
  bool _requiresPasswordReset = false;
  String? _pendingUserId;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _isAuthenticated;
  bool get isMerchant => _user?.role == UserRole.merchant;
  bool get isBuyer => _user?.role == UserRole.buyer;
  bool get requiresPasswordReset => _requiresPasswordReset;
  String? get pendingUserId => _pendingUserId;

  void setPendingUserId(String userId) {
    _pendingUserId = userId;
    notifyListeners();
  }

  /// Check auth status using SWR — show cached user instantly, verify in background.
  Future<void> checkAuthStatus() async {
    final token = await _api.getAuthToken();
    if (token != null) {
      _isLoading = true;
      notifyListeners();

      // Try cached user profile first
      final cachedUser = _cache.readJson(CacheKeys.userProfile);
      if (cachedUser != null) {
        try {
          _user = User.fromJson(cachedUser);
          _isAuthenticated = true;
          _isLoading = false;
          notifyListeners();
        } catch (_) {
          // Invalid cache, ignore
        }
      }

      // Verify with server
      final response = await _api.getCurrentUser();
      if (response.success && response.data != null) {
        _user = response.data;
        _isAuthenticated = true;
        // Cache user profile
        await _cache.writeJson(CacheKeys.userProfile, _user!.toJson(), ttl: CacheKeys.userProfileTtl);
      } else {
        // Server says not authenticated — clear cache and state
        if (cachedUser == null) {
          // No cache existed, only now set unauthenticated
          _isAuthenticated = false;
          _user = null;
        }
        // If cache existed but server says invalid, keep showing cached data
        // until the token refresh interceptor (P0-1) handles it
      }

      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    _requiresPasswordReset = false;
    _pendingUserId = null;
    notifyListeners();

    final response = await _api.login(email: email, password: password);

    if (response.success && response.data != null) {
      _user = response.data!.user;
      _isAuthenticated = true;
      // Cache user profile on login
      await _cache.writeJson(CacheKeys.userProfile, _user!.toJson(), ttl: CacheKeys.userProfileTtl);
      _isLoading = false;
      notifyListeners();
      // Pre-fetch data for the user's role (P1-3)
      PrefetchService().prefetchForRole(_user!.role);
      return true;
    } else {
      // Check if password reset is required
      if (response.statusCode == 403 && response.requiresPasswordReset) {
        _requiresPasswordReset = true;
        _pendingUserId = response.userId;
        _error = 'Password reset required. Please set a new password.';
      } else {
        _error = response.message ?? 'Login failed';
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(String newPassword) async {
    if (_pendingUserId == null) {
      _error = 'No pending password reset';
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    final response = await _api.resetPassword(
      userId: _pendingUserId!,
      newPassword: newPassword,
    );

    if (response.success && response.data != null) {
      _user = response.data!.user;
      _isAuthenticated = true;
      _requiresPasswordReset = false;
      _pendingUserId = null;
      await _cache.writeJson(CacheKeys.userProfile, _user!.toJson(), ttl: CacheKeys.userProfileTtl);
      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _error = response.message ?? 'Password reset failed';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String name,
    required String phone,
    required UserRole role,
    String? businessName,
    String? businessAddress,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final response = await _api.register(
      email: email,
      password: password,
      name: name,
      phone: phone,
      role: role,
      businessName: businessName,
      businessAddress: businessAddress,
    );

    if (response.success && response.data != null) {
      _user = response.data!.user;
      _isAuthenticated = true;
      await _cache.writeJson(CacheKeys.userProfile, _user!.toJson(), ttl: CacheKeys.userProfileTtl);
      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _error = response.message ?? 'Registration failed';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _api.logout();
    _user = null;
    _isAuthenticated = false;
    _requiresPasswordReset = false;
    _pendingUserId = null;
    // Clear user-specific cache
    await _cache.remove(CacheKeys.userProfile);
    notifyListeners();
  }

  /// Force logout — called by the token refresh interceptor when
  /// both access and refresh tokens are expired.
  Future<void> forceLogout() async {
    await _api.clearAuthData();
    _user = null;
    _isAuthenticated = false;
    _requiresPasswordReset = false;
    _pendingUserId = null;
    await _cache.clear();
    notifyListeners();
  }

  Future<void> refreshUser() async {
    final response = await _api.getCurrentUser();
    if (response.success && response.data != null) {
      _user = response.data;
      await _cache.writeJson(CacheKeys.userProfile, _user!.toJson(), ttl: CacheKeys.userProfileTtl);
      notifyListeners();
    }
  }

  Future<bool> updateProfile({
    String? name,
    String? phone,
    String? businessName,
    String? businessAddress,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final response = await _api.updateProfile(
      name: name,
      phone: phone,
      businessName: businessName,
      businessAddress: businessAddress,
    );

    if (response.success && response.data != null) {
      _user = response.data;
      await _cache.writeJson(CacheKeys.userProfile, _user!.toJson(), ttl: CacheKeys.userProfileTtl);
      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _error = response.message ?? 'Failed to update profile';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<bool> sendPasswordResetLink(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final response = await _api.sendPasswordResetLink(email: email);

    _isLoading = false;
    notifyListeners();

    if (response.success) {
      return true;
    } else {
      _error = response.message ?? 'Failed to send reset link';
      return false;
    }
  }
}