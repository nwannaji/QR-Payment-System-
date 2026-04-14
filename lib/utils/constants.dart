class AppConstants {
  // API
  static const String apiBaseUrl = 'https://your-api.com/api/v1';
  
  // App Info
  static const String appName = 'QR Pay';
  static const String appVersion = '1.0.0';
  
  // Currency
  static const String defaultCurrency = 'NGN';
  static const String currencySymbol = '₦';
  
  // Transaction
  static const double minTransactionAmount = 100;
  static const double maxTransactionAmount = 1000000;
  static const int otpLength = 6;
  static const int pinLength = 4;
  
  // QR Code
  static const int qrCodeExpiryMinutes = 5;
  
  // Pagination
  static const int defaultPageSize = 20;
  
  // Validation
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 32;
  
  // Storage Keys
  static const String authTokenKey = 'auth_token';
  static const String userIdKey = 'user_id';
  static const String userRoleKey = 'user_role';
  static const String onboardingCompleteKey = 'onboarding_complete';
}

class RouteNames {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String roleSelection = '/role-selection';
  
  // Buyer Routes
  static const String buyerHome = '/buyer/home';
  static const String buyerScanner = '/buyer/scanner';
  static const String buyerPayment = '/buyer/payment';
  static const String buyerTransactions = '/buyer/transactions';
  static const String buyerWallet = '/buyer/wallet';
  static const String buyerProfile = '/buyer/profile';
  
  // Merchant Routes
  static const String merchantHome = '/merchant/home';
  static const String merchantQR = '/merchant/qr';
  static const String merchantTransactions = '/merchant/transactions';
  static const String merchantProfile = '/merchant/profile';
}
