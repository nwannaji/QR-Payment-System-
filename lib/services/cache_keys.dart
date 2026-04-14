/// Cache key constants for the SWR cache service.
///
/// Each key corresponds to a cached data type with a recommended TTL.
class CacheKeys {
  CacheKeys._();

  // Wallet data - short TTL since balance changes frequently
  static const String wallet = 'cache_wallet';
  static const Duration walletTtl = Duration(seconds: 30);

  // Wallet ledger entries - moderate TTL
  static const String walletLedger = 'cache_wallet_ledger';
  static const Duration walletLedgerTtl = Duration(minutes: 1);

  // User profile - rarely changes, longer TTL
  static const String userProfile = 'cache_user_profile';
  static const Duration userProfileTtl = Duration(minutes: 5);

  // Merchant stats - changes with each transaction
  static const String merchantStats = 'cache_merchant_stats';
  static const Duration merchantStatsTtl = Duration(seconds: 30);

  // Merchant transactions - moderate TTL
  static const String merchantTransactions = 'cache_merchant_transactions';
  static const Duration merchantTransactionsTtl = Duration(minutes: 1);

  // Buyer transactions - moderate TTL
  static const String buyerTransactions = 'cache_buyer_transactions';
  static const Duration buyerTransactionsTtl = Duration(minutes: 1);

  // Banks list - rarely changes, long TTL
  static const String banksList = 'cache_banks_list';
  static const Duration banksListTtl = Duration(hours: 24);

  // QR code data - short TTL since it can be regenerated
  static const String qrCodeData = 'cache_qr_code_data';
  static const Duration qrCodeTtl = Duration(minutes: 5);

  // Auth status - moderate TTL
  static const String authStatus = 'cache_auth_status';
  static const Duration authStatusTtl = Duration(minutes: 10);
}