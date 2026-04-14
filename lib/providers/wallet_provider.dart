import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../api/backend_api.dart';
import '../services/cache_service.dart';
import '../services/cache_keys.dart';
import '../utils/constants.dart';

class WalletProvider with ChangeNotifier {
  final BackendApi _api = BackendApi();
  final CacheService _cache = CacheService();

  Wallet? _wallet;
  final List<WalletLedgerEntry> _walletHistory = [];
  bool _isLoading = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMore = true;

  /// When true, [loadWallet] will skip network fetches to avoid
  /// overwriting an optimistic local deduction with stale server data.
  bool _isOptimisticPaymentPending = false;

  Wallet? get wallet => _wallet;
  List<WalletLedgerEntry> get walletHistory => _walletHistory;
  bool get isLoading => _isLoading;
  String? get error => _error;
  double get balance => _wallet?.balance ?? 0.0;

  /// Lock wallet refreshes during an optimistic payment to prevent
  /// the balance from bouncing back to the stale server value.
  void lockOptimisticRefresh() {
    _isOptimisticPaymentPending = true;
  }

  /// Unlock wallet refreshes after the optimistic payment is confirmed
  /// or rejected. Immediately refreshes to get the authoritative balance.
  Future<void> unlockOptimisticRefresh() async {
    _isOptimisticPaymentPending = false;
    await loadWallet();
    await loadWalletHistory(refresh: true);
  }

  /// Load wallet using Stale-While-Revalidate pattern.
  /// Shows cached data instantly, refreshes in background.
  /// Skips network fetch when an optimistic payment is pending.
  Future<void> loadWallet() async {
    // Skip network fetch when an optimistic payment is pending
    // to prevent the balance from bouncing back to the stale server value.
    if (_isOptimisticPaymentPending) {
      debugPrint('[WalletProvider] Skipping loadWallet — optimistic payment pending');
      return;
    }

    _error = null;

    try {
      await _cache.swrModel<Wallet>(
        cacheKey: CacheKeys.wallet,
        ttl: CacheKeys.walletTtl,
        fetcher: () async {
          final response = await _api.getWallet();
          if (response.success && response.data != null) {
            return response.data!;
          }
          throw Exception(response.message ?? 'Failed to load wallet');
        },
        toJson: (wallet) => wallet.toJson(),
        fromJson: (json) => Wallet.fromJson(json),
        onCached: (cached) {
          _wallet = cached;
          _isLoading = false;
          notifyListeners();
        },
        onFresh: (fresh) {
          _wallet = fresh;
          _isLoading = false;
          notifyListeners();
        },
        onError: (error) {
          _error = error;
          _isLoading = false;
          notifyListeners();
        },
      );
    } catch (e) {
      // If cache exists but network fails, keep showing cached data
      if (_wallet == null) {
        _error = e.toString();
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Load wallet history using SWR pattern.
  Future<void> loadWalletHistory({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _walletHistory.clear();
    }

    if (!_hasMore) return;

    _error = null;

    try {
      // For paginated data, only use SWR for the first page
      if (_currentPage == 1) {
        final response = await _api.getWalletLedger(
          page: _currentPage,
          limit: AppConstants.defaultPageSize,
        );

        if (response.success && response.data != null) {
          final entries = response.data!;
          if (entries.length < AppConstants.defaultPageSize) {
            _hasMore = false;
          }
          _walletHistory.clear();
          _walletHistory.addAll(entries);
          _currentPage++;

          // Cache the first page
          await _cache.writeJsonList(
            CacheKeys.walletLedger,
            entries.map((e) => {
              'id': e.id,
              'wallet_id': e.walletId,
              'type': e.type,
              'amount': e.amount,
              'balance_before': e.balanceBefore,
              'balance_after': e.balanceAfter,
              'reference': e.reference,
              'description': e.description,
              'created_at': e.createdAt.toIso8601String(),
            }).toList(),
            ttl: CacheKeys.walletLedgerTtl,
          );
        } else {
          _error = response.message ?? 'Failed to load wallet history';
          _hasMore = false;
        }
      } else {
        // Subsequent pages always fetch from network
        _isLoading = true;
        notifyListeners();

        final response = await _api.getWalletLedger(
          page: _currentPage,
          limit: AppConstants.defaultPageSize,
        );

        if (response.success && response.data != null) {
          final entries = response.data!;
          if (entries.length < AppConstants.defaultPageSize) {
            _hasMore = false;
          }
          _walletHistory.addAll(entries);
          _currentPage++;
        } else {
          _error = response.message ?? 'Failed to load wallet history';
          _hasMore = false;
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      // Try loading from cache for first page
      if (_currentPage == 1) {
        final cachedList = _cache.readJsonList(CacheKeys.walletLedger);
        if (cachedList != null && cachedList.isNotEmpty) {
          _walletHistory.clear();
          _walletHistory.addAll(cachedList.map((json) => WalletLedgerEntry.fromJson(json)));
        }
      }
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Deduct from local wallet balance immediately (for optimistic payments).
  /// Call [reverseLocalDeduction] if the server rejects the payment.
  void deductLocally(double amount) {
    if (_wallet != null) {
      _wallet = _wallet!.copyWith(
        balance: _wallet!.balance - amount,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  /// Reverse a local deduction (when server rejects an optimistic payment).
  void reverseLocalDeduction(double amount) {
    if (_wallet != null) {
      _wallet = _wallet!.copyWith(
        balance: _wallet!.balance + amount,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  Future<bool> topUp(double amount) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final response = await _api.topUpWallet(amount: amount);

    if (response.success && response.data != null) {
      final walletResponse = await _api.getWallet();
      if (walletResponse.success && walletResponse.data != null) {
        _wallet = walletResponse.data;
        // Update cache
        await _cache.writeJson(CacheKeys.wallet, _wallet!.toJson(), ttl: CacheKeys.walletTtl);
      }
      await loadWalletHistory(refresh: true);
      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _error = response.message ?? 'Top-up failed';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Manual wallet funding for testing (bypasses payment)
  Future<bool> manualFund(double amount, {String? reason}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final response = await _api.manualFundWallet(amount: amount, reason: reason);

    if (response.success && response.data != null) {
      _wallet = response.data!.wallet;
      await _cache.writeJson(CacheKeys.wallet, _wallet!.toJson(), ttl: CacheKeys.walletTtl);
      await loadWalletHistory(refresh: true);
      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _error = response.message ?? 'Manual fund failed';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> refresh() async {
    await Future.wait([loadWallet(), loadWalletHistory(refresh: true)]);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}