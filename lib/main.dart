import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/merchant_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/buyer/buyer_home_screen.dart';
import 'screens/buyer/buyer_transactions_screen.dart';
import 'screens/buyer/scanner_screen.dart';
import 'screens/buyer/payment_confirmation_screen.dart';
import 'screens/buyer/payment_screen.dart';
import 'screens/merchant/merchant_home_screen.dart';
import 'screens/merchant/merchant_qr_screen.dart';
import 'screens/merchant/merchant_transactions_screen.dart';
import 'screens/profile/edit_profile_screen.dart';
import 'screens/profile/change_pin_screen.dart';
import 'screens/profile/notifications_screen.dart';
import 'screens/profile/bank_account_screen.dart';
import 'screens/profile/help_support_screen.dart';
import 'screens/profile/about_screen.dart';
import 'services/cache_service.dart';
import 'services/offline_queue_service.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CacheService().init();
  await OfflineQueueService().init();
  runApp(const QRPaymentApp());
}

class QRPaymentApp extends StatefulWidget {
  const QRPaymentApp({super.key});

  @override
  State<QRPaymentApp> createState() => _QRPaymentAppState();
}

class _QRPaymentAppState extends State<QRPaymentApp> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => MerchantProvider()),
      ],
      child: MaterialApp(
        title: 'QR Pay',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        initialRoute: '/login',
        routes: {
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/forgot-password': (context) => const ForgotPasswordScreen(),
          '/buyer/home': (context) => const BuyerHomeScreen(),
          '/buyer/transactions': (context) => const BuyerTransactionsScreen(),
          '/buyer/scanner': (context) => const ScannerScreen(),
          '/buyer/payment-confirmation': (context) => const PaymentConfirmationScreen(
            merchantId: '',
            merchantName: '',
          ),
          '/buyer/payment': (context) => const PaymentScreen(
            merchantId: '',
            merchantName: '',
          ),
          '/merchant/home': (context) => const MerchantHomeScreen(),
          '/merchant/qr': (context) => const MerchantQRScreen(),
          '/merchant/transactions':
              (context) => const MerchantTransactionsScreen(),
          // Profile routes
          '/buyer/profile/edit': (context) => const EditProfileScreen(),
          '/buyer/profile/change-pin': (context) => const ChangePinScreen(),
          '/buyer/profile/notifications': (context) => const NotificationsScreen(),
          '/buyer/profile/help': (context) => const HelpSupportScreen(),
          '/buyer/profile/about': (context) => const AboutScreen(),
          '/merchant/profile/edit': (context) => const EditProfileScreen(),
          '/merchant/profile/change-pin': (context) => const ChangePinScreen(),
          '/merchant/profile/notifications': (context) => const NotificationsScreen(),
          '/merchant/profile/help': (context) => const HelpSupportScreen(),
          '/merchant/profile/about': (context) => const AboutScreen(),
          '/merchant/bank-account': (context) => const BankAccountScreen(),
        },
      ),
    );
  }
}
