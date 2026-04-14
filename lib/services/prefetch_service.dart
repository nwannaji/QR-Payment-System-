import '../api/backend_api.dart';
import '../models/user.dart';
import '../services/cache_service.dart';
import '../services/cache_keys.dart';

/// Service that pre-fetches data after login or on app resume
/// so that screens load instantly from cache when the user navigates.
///
/// Pre-fetches run in parallel using Future.wait and store results
/// in the SWR cache. Screen transitions then read from cache first
/// (instant) and refresh in background.
class PrefetchService {
  PrefetchService._();
  static final PrefetchService _instance = PrefetchService._();
  factory PrefetchService() => _instance;

  final BackendApi _api = BackendApi();
  final CacheService _cache = CacheService();
  bool _isPrefetching = false;

  /// Whether a prefetch is currently in progress.
  bool get isPrefetching => _isPrefetching;

  /// Pre-fetch all data for the current user's role.
  /// Call this after successful login or on app resume.
  Future<void> prefetchForRole(UserRole role) async {
    if (_isPrefetching) return; // Don't stack prefetches
    _isPrefetching = true;

    try {
      // Common data: wallet, profile (already cached by auth, but refresh)
      final futures = <Future<void>>[
        _prefetchWallet(),
        _prefetchProfile(),
      ];

      // Role-specific data
      if (role == UserRole.merchant) {
        futures.add(_prefetchMerchantStats());
      }

      await Future.wait(futures);
    } catch (_) {
      // Prefetch failures are non-critical — screens will fetch on demand
    } finally {
      _isPrefetching = false;
    }
  }

  /// Pre-fetch wallet data.
  Future<void> _prefetchWallet() async {
    try {
      final response = await _api.getWallet();
      if (response.success && response.data != null) {
        await _cache.writeJson(
          CacheKeys.wallet,
          response.data!.toJson(),
          ttl: CacheKeys.walletTtl,
        );
      }
    } catch (_) {
      // Non-critical
    }
  }

  /// Pre-fetch user profile.
  Future<void> _prefetchProfile() async {
    try {
      final response = await _api.getCurrentUser();
      if (response.success && response.data != null) {
        await _cache.writeJson(
          CacheKeys.userProfile,
          response.data!.toJson(),
          ttl: CacheKeys.userProfileTtl,
        );
      }
    } catch (_) {
      // Non-critical
    }
  }

  /// Pre-fetch merchant statistics.
  Future<void> _prefetchMerchantStats() async {
    try {
      final response = await _api.getMerchantStats();
      if (response.success && response.data != null) {
        final stats = response.data!;
        await _cache.writeJson(
          CacheKeys.merchantStats,
          {
            'total_transactions': stats.totalTransactions,
            'total_revenue': stats.totalRevenue,
            'today_revenue': stats.todayRevenue,
            'week_revenue': stats.weekRevenue,
            'month_revenue': stats.monthRevenue,
          },
          ttl: CacheKeys.merchantStatsTtl,
        );
      }
    } catch (_) {
      // Non-critical
    }
  }

  /// Pre-fetch banks list for payment screen.
  Future<void> prefetchBanks() async {
    try {
      final response = await _api.getBanks();
      if (response.success && response.data != null) {
        await _cache.writeJsonList(
          CacheKeys.banksList,
          response.data!.map((b) => {'name': b.name, 'code': b.code, 'slug': b.slug}).toList(),
          ttl: CacheKeys.banksListTtl,
        );
      }
    } catch (_) {
      // Non-critical
    }
  }

  /// Pre-fetch transactions for the given role.
  Future<void> prefetchTransactions({required bool isMerchant}) async {
    try {
      final cacheKey = isMerchant ? CacheKeys.merchantTransactions : CacheKeys.buyerTransactions;
      final response = isMerchant
          ? await _api.getMerchantTransactions(page: 1, limit: 20)
          : await _api.getTransactions(page: 1, limit: 20);

      if (response.success && response.data != null) {
        await _cache.writeJsonList(
          cacheKey,
          response.data!.map((t) => t.toJson()).toList(),
          ttl: CacheKeys.merchantTransactionsTtl,
        );
      }
    } catch (_) {
      // Non-critical
    }
  }
}