import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../models/qr_code.dart';
import '../api/backend_api.dart';
import '../services/cache_service.dart';
import '../services/cache_keys.dart';
import '../utils/constants.dart';

class MerchantProvider with ChangeNotifier {
  final BackendApi _api = BackendApi();
  final CacheService _cache = CacheService();

  QRCodeData? _activeQRCode;
  final List<Transaction> _transactions = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMore = true;

  QRCodeData? get activeQRCode => _activeQRCode;
  List<Transaction> get transactions => _transactions;
  Map<String, dynamic> get stats => _stats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> generateQRCode() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Retry once after 1.5s delay in case backend was still starting
    ApiResponse<QRCodeData> response;
    try {
      response = await _api.generateQRCode();
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 1500));
      response = await _api.generateQRCode();
    }

    if (response.success && response.data != null) {
      _activeQRCode = response.data;
      // Cache QR code data
      await _cache.writeJson(CacheKeys.qrCodeData, response.data!.toJson(), ttl: CacheKeys.qrCodeTtl);
      _isLoading = false;
      notifyListeners();
    } else {
      _error = response.message ?? 'Failed to generate QR code';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load merchant stats using SWR pattern.
  Future<void> loadStats() async {
    _error = null;

    // Try cached stats first
    final cachedStats = _cache.readJson(CacheKeys.merchantStats);
    if (cachedStats != null) {
      _stats = cachedStats;
      notifyListeners();
    }

    // Always fetch fresh stats
    final response = await _api.getMerchantStats();
    if (response.success && response.data != null) {
      final stats = response.data!;
      _stats = {
        'total_transactions': stats.totalTransactions,
        'total_revenue': stats.totalRevenue,
        'today_revenue': stats.todayRevenue,
        'week_revenue': stats.weekRevenue,
        'month_revenue': stats.monthRevenue,
      };
      // Cache the stats
      await _cache.writeJson(CacheKeys.merchantStats, _stats, ttl: CacheKeys.merchantStatsTtl);
    } else if (cachedStats == null) {
      _error = response.message ?? 'Failed to load statistics';
    }
    notifyListeners();
  }

  /// Load merchant transactions using SWR pattern.
  Future<void> loadTransactions({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _transactions.clear();
    }

    if (!_hasMore) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    // Try cached transactions for first page
    if (_currentPage == 1 && _transactions.isEmpty) {
      final cachedList = _cache.readJsonList(CacheKeys.merchantTransactions);
      if (cachedList != null && cachedList.isNotEmpty) {
        _transactions.clear();
        _transactions.addAll(cachedList.map((json) => Transaction.fromJson(json)));
        notifyListeners();
      }
    }

    final response = await _api.getMerchantTransactions(
      page: _currentPage,
      limit: AppConstants.defaultPageSize,
    );

    if (response.success && response.data != null) {
      final transactions = response.data!;
      if (transactions.length < AppConstants.defaultPageSize) {
        _hasMore = false;
      }
      if (_currentPage == 1) {
        _transactions.clear();
        // Cache first page
        await _cache.writeJsonList(
          CacheKeys.merchantTransactions,
          transactions.map((t) => t.toJson()).toList(),
          ttl: CacheKeys.merchantTransactionsTtl,
        );
      }
      _transactions.addAll(transactions);
      _currentPage++;
    } else {
      _error = response.message ?? 'Failed to load transactions';
      _hasMore = false;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    await Future.wait([
      loadStats(),
      loadTransactions(refresh: true),
    ]);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}