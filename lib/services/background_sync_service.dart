import 'dart:async';
import 'package:flutter/foundation.dart';
import '../providers/wallet_provider.dart';
import '../providers/merchant_provider.dart';

/// Background sync service that periodically refreshes wallet balance,
/// merchant stats, and transactions when the app is in the foreground.
///
/// Merchants see new payments within 30 seconds without manual refresh.
/// Uses a conservative 30-second interval to avoid battery drain.
class BackgroundSyncService {
  BackgroundSyncService._();
  static final BackgroundSyncService _instance = BackgroundSyncService._();
  factory BackgroundSyncService() => _instance;

  Timer? _syncTimer;

  /// Callback fired when a new payment is detected for the merchant.
  void Function(int newCount)? onNewPayment;

  /// Whether the sync service is currently active.
  bool get isActive => _syncTimer?.isActive ?? false;

  /// Start the background sync service.
  /// Refreshes wallet, merchant stats, and transactions every 30 seconds.
  void start({
    required WalletProvider walletProvider,
    MerchantProvider? merchantProvider,
  }) {
    if (isActive) return; // Already running

    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        // Refresh wallet balance
        await walletProvider.loadWallet();

        // Refresh merchant stats and transactions if available
        if (merchantProvider != null) {
          await merchantProvider.loadStats();

          // Track transactions before refresh
          final previousCount = merchantProvider.transactions.length;
          final previousFirstId = merchantProvider.transactions.isNotEmpty
              ? merchantProvider.transactions.first.id
              : null;

          // Refresh transactions to detect new payments
          await merchantProvider.loadTransactions(refresh: true);

          // Detect new payments: new transaction at the top of the list
          final newCount = merchantProvider.transactions.length;
          final newFirstId = merchantProvider.transactions.isNotEmpty
              ? merchantProvider.transactions.first.id
              : null;

          if (newCount > previousCount ||
              (newFirstId != null && newFirstId != previousFirstId && previousCount > 0)) {
            onNewPayment?.call(newCount - previousCount);
          }
        }
      } catch (e) {
        debugPrint('[BackgroundSync] Sync error: $e');
      }
    });

    debugPrint('[BackgroundSync] Started with 30s interval');
  }

  /// Stop the background sync service.
  void stop() {
    _syncTimer?.cancel();
    _syncTimer = null;
    onNewPayment = null;
    debugPrint('[BackgroundSync] Stopped');
  }

  /// Perform a single sync immediately.
  Future<void> syncNow({
    required WalletProvider walletProvider,
    MerchantProvider? merchantProvider,
  }) async {
    try {
      await walletProvider.loadWallet();
      if (merchantProvider != null) {
        await merchantProvider.loadStats();
        await merchantProvider.loadTransactions(refresh: true);
      }
    } catch (e) {
      debugPrint('[BackgroundSync] Manual sync error: $e');
    }
  }
}