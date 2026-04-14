import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../api/backend_api.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/merchant_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/background_sync_service.dart';
import '../../services/qr_share_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common/custom_button.dart';

class MerchantHomeScreen extends StatefulWidget {
  const MerchantHomeScreen({super.key});

  @override
  State<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantHomeScreenState extends State<MerchantHomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MerchantProvider>().refresh();
      context.read<WalletProvider>().loadWallet();
      // Start background sync for wallet balance and merchant stats
      BackgroundSyncService().start(
        walletProvider: context.read<WalletProvider>(),
        merchantProvider: context.read<MerchantProvider>(),
      );
      // Listen for new payments and show a toast notification
      BackgroundSyncService().onNewPayment = (count) {
        if (!mounted) return;
        final transactions = context.read<MerchantProvider>().transactions;
        final latest = transactions.isNotEmpty ? transactions.first : null;
        final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);
        final message = latest != null
            ? 'Payment of ${currencyFormat.format(latest.amount)} received from ${latest.buyerName ?? 'a customer'}'
            : 'New payment received!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      };
    });
  }

  @override
  void dispose() {
    BackgroundSyncService().stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh dashboard when merchant returns to the app
    // so new payments are reflected immediately
    if (state == AppLifecycleState.resumed) {
      context.read<MerchantProvider>().refresh();
      context.read<WalletProvider>().loadWallet();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _DashboardContent(),
          _QRGeneratorScreen(),
          _TransactionList(),
          _ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_outlined),
            selectedIcon: Icon(Icons.qr_code),
            label: 'QR Code',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final merchantProvider = context.watch<MerchantProvider>();
    final walletProvider = context.watch<WalletProvider>();
    final stats = merchantProvider.stats;
    final transactions = merchantProvider.transactions;
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);

    // Filter today's transactions
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayTransactions = transactions.where((tx) {
      return tx.createdAt.isAfter(todayStart) ||
          (tx.createdAt.year == todayStart.year &&
              tx.createdAt.month == todayStart.month &&
              tx.createdAt.day == todayStart.day);
    }).toList();

    final todayRevenue = todayTransactions.fold<double>(
      0,
      (sum, tx) => sum + tx.amount,
    );

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            context.read<MerchantProvider>().refresh(),
            context.read<WalletProvider>().loadWallet(),
          ]);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppTheme.primaryColor,
                      backgroundImage: user?.avatarUrl != null
                          ? NetworkImage(BackendApi().getAvatarUrl(user!.avatarUrl))
                          : null,
                      child: user?.avatarUrl == null
                          ? Text(
                              (user?.businessName ?? user?.name ?? 'M')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          user?.businessName ?? user?.name ?? 'Merchant',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ],
                ),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                  child: Icon(
                    Icons.notifications_outlined,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Stats Tiles
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    title: 'Total Balance',
                    value: currencyFormat.format(walletProvider.balance),
                    icon: Icons.account_balance,
                    color: AppTheme.secondaryColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatTile(
                    title: 'Total Transactions',
                    value: '${stats['total_transactions'] ?? 0}',
                    icon: Icons.receipt_long,
                    color: AppTheme.accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Today's Transactions Card
            Text(
              'Today',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${todayTransactions.length} transaction${todayTransactions.length == 1 ? '' : 's'} • ${currencyFormat.format(todayRevenue)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            if (todayTransactions.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 40,
                      color: AppTheme.textHint,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No transactions today',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: todayTransactions.take(5).map((tx) {
                    return _TodayTransactionTile(transaction: tx);
                  }).toList(),
                ),
              ),
            const SizedBox(height: 32),

            // Quick Actions
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.qr_code_2_rounded,
                    title: 'Show QR',
                    onTap: () {
                      Navigator.of(context).pushNamed('/merchant/qr');
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.history_rounded,
                    title: 'History',
                    onTap: () {
                      Navigator.of(context).pushNamed('/merchant/transactions');
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.account_balance,
                    title: 'Bank Account',
                    onTap: () => Navigator.of(context).pushNamed('/merchant/bank-account'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Recent Transactions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Payments',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/merchant/transactions');
                  },
                  child: const Text('See All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Consumer<MerchantProvider>(
              builder: (context, provider, _) {
                final transactions = provider.transactions.take(5).toList();
                if (transactions.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 64,
                            color: AppTheme.textHint,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No payments yet',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children:
                      transactions
                          .map((tx) => _TransactionTile(transaction: tx))
                          .toList(),
                );
              },
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: AppTheme.primaryColor),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction transaction;
  const _TransactionTile({required this.transaction});

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final txDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (txDate == today) {
      return 'Today, ${DateFormat('h:mm a').format(dateTime)}';
    } else if (txDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, ${DateFormat('h:mm a').format(dateTime)}';
    } else {
      return DateFormat('MMM d, h:mm a').format(dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);
    final buyerName = transaction.buyerName ?? 'Payment received';
    final buyerInitial = buyerName.isNotEmpty ? buyerName.substring(0, 1).toUpperCase() : 'P';

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.successColor.withValues(alpha: 0.15),
        child: Text(
          buyerInitial,
          style: TextStyle(
            color: AppTheme.successColor,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      title: Text(buyerName),
      subtitle: Text(_formatDate(transaction.createdAt)),
      trailing: Text(
        currencyFormat.format(transaction.amount),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: AppTheme.successColor),
      ),
    );
  }
}

class _TodayTransactionTile extends StatelessWidget {
  final Transaction transaction;
  const _TodayTransactionTile({required this.transaction});

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final txDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (txDate == today) {
      return 'Today, ${DateFormat('h:mm a').format(dateTime)}';
    } else if (txDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, ${DateFormat('h:mm a').format(dateTime)}';
    } else {
      return DateFormat('MMM d, h:mm a').format(dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);
    final buyerName = transaction.buyerName ?? transaction.description ?? 'Payment received';
    final buyerInitial = buyerName.isNotEmpty ? buyerName.substring(0, 1).toUpperCase() : 'P';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.textHint.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.successColor.withValues(alpha: 0.15),
            child: Text(
              buyerInitial,
              style: TextStyle(
                color: AppTheme.successColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description ?? 'Payment received',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(transaction.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            currencyFormat.format(transaction.amount),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.successColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QRGeneratorScreen extends StatefulWidget {
  const _QRGeneratorScreen();

  @override
  State<_QRGeneratorScreen> createState() => _QRGeneratorScreenState();
}

class _QRGeneratorScreenState extends State<_QRGeneratorScreen> {
  final _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MerchantProvider>().generateQRCode();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'Your Payment QR Code',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Customers can scan this code to pay you',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Consumer<MerchantProvider>(
              builder: (context, provider, _) {
                final qrData = provider.activeQRCode;

                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (qrData == null) {
                  return Column(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: AppTheme.errorColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to generate QR code',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      CustomButton(
                        text: 'Try Again',
                        onPressed: () => provider.generateQRCode(),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    // QR Code Container
                    RepaintBoundary(
                      key: _qrKey,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: qrData.toQRString(),
                          version: QrVersions.auto,
                          size: 250,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: AppTheme.primaryColor,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Scan to pay',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 32),
                    CustomButton(
                      text: 'Refresh QR Code',
                      icon: Icons.refresh,
                      type: ButtonType.outline,
                      isFullWidth: true,
                      onPressed: () => provider.generateQRCode(),
                    ),
                    const SizedBox(height: 16),
                    CustomButton(
                      text: 'Share QR Code',
                      icon: Icons.share,
                      isFullWidth: true,
                      onPressed: () {
                        final user = context.read<AuthProvider>().user;
                        QrShareService.shareQrCode(
                          globalKey: _qrKey,
                          merchantName: user?.businessName ?? user?.name ?? 'merchant',
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Payment History',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          Expanded(
            child: Consumer<MerchantProvider>(
              builder: (context, provider, _) {
                if (provider.transactions.isEmpty) {
                  return const Center(child: Text('No payments yet'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: provider.transactions.length,
                  itemBuilder: (context, index) {
                    return _TransactionTile(
                      transaction: provider.transactions[index],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profile', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppTheme.primaryColor,
                    backgroundImage: user?.avatarUrl != null
                        ? NetworkImage(BackendApi().getAvatarUrl(user!.avatarUrl))
                        : null,
                    child: user?.avatarUrl == null
                        ? Text(
                            (user?.businessName ?? user?.name ?? 'M')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user?.businessName ?? user?.name ?? 'Merchant',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    user?.businessAddress ?? '',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _ProfileTile(
              icon: Icons.store_outlined,
              title: 'Business Details',
              onTap: () => Navigator.of(context).pushNamed('/merchant/profile/edit'),
            ),
            _ProfileTile(
              icon: Icons.lock_outline,
              title: 'Change PIN',
              onTap: () => Navigator.of(context).pushNamed('/merchant/profile/change-pin'),
            ),
            _ProfileTile(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              onTap: () => Navigator.of(context).pushNamed('/merchant/profile/notifications'),
            ),
            _ProfileTile(
              icon: Icons.help_outline,
              title: 'Help & Support',
              onTap: () => Navigator.of(context).pushNamed('/merchant/profile/help'),
            ),
            _ProfileTile(
              icon: Icons.info_outline,
              title: 'About',
              onTap: () => Navigator.of(context).pushNamed('/merchant/profile/about'),
            ),
            const SizedBox(height: 24),
            CustomButton(
              text: 'Sign Out',
              type: ButtonType.primary,
              isFullWidth: true,
              onPressed: () {
                context.read<AuthProvider>().logout();
                Navigator.of(context).pushReplacementNamed('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryColor),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
