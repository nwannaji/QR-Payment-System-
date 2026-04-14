import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../api/backend_api.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/background_sync_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common/custom_button.dart';

class BuyerHomeScreen extends StatefulWidget {
  const BuyerHomeScreen({super.key});

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().refresh();
      // Start background sync for wallet balance
      BackgroundSyncService().start(
        walletProvider: context.read<WalletProvider>(),
      );
    });
  }

  @override
  void dispose() {
    BackgroundSyncService().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _HomeContent(),
          _TransactionList(),
          _WalletScreen(),
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
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Wallet',
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

class _HomeContent extends StatelessWidget {
  const _HomeContent();

  void _showTopUpBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Up Amount',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [500, 1000, 2000, 5000, 10000].map((amount) {
                return ChoiceChip(
                  label: Text('₦$amount'),
                  selected: false,
                  onSelected: (selected) async {
                    final walletProvider = context.read<WalletProvider>();
                    Navigator.pop(context);
                    final result = await walletProvider.topUp(amount.toDouble());
                    if (!result && walletProvider.error != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(walletProvider.error!)),
                      );
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            // Testing option - manual fund (for dev only)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Testing Only - Instant Fund',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.amber.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [500, 1000, 5000, 10000].map((amount) {
                      return ElevatedButton(
                        onPressed: () async {
                          final walletProvider = context.read<WalletProvider>();
                          final result = await walletProvider.manualFund(
                            amount.toDouble(),
                            reason: 'Testing',
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                            if (result) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('₦$amount added to wallet')),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: Text('₦$amount'),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final wallet = context.watch<WalletProvider>().wallet;
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);

    return SafeArea(
      child: SingleChildScrollView(
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
                              (user?.name ?? 'U').substring(0, 1).toUpperCase(),
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
                          'Hello,',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          user?.name ?? 'User',
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

            // Balance Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryColor, AppTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available Balance',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currencyFormat.format(wallet?.balance ?? 0),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _showTopUpBottomSheet(context);
                          },
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text(
                            'Top Up',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Scan QR',
                    onTap: () {
                      Navigator.of(context).pushNamed('/buyer/scanner');
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.history_rounded,
                    title: 'History',
                    onTap: () {
                      Navigator.of(context).pushNamed('/buyer/transactions');
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.help_outline_rounded,
                    title: 'Help',
                    onTap: () => Navigator.of(context).pushNamed('/buyer/profile/help'),
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
                  'Recent Transactions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/buyer/transactions');
                  },
                  child: const Text('See All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Consumer<WalletProvider>(
              builder: (context, walletProvider, _) {
                final history =
                    walletProvider.walletHistory.take(5).toList();
                if (history.isEmpty) {
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
                            'No transactions yet',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children:
                      history
                          .map((entry) => _TransactionTile(entry: entry))
                          .toList(),
                );
              },
            ),
          ],
        ),
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
  final WalletLedgerEntry entry;
  const _TransactionTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);

    // Determine if credit or debit based on type
    final isCredit = entry.type.contains('topup') || entry.type.contains('refund');
    final icon = isCredit ? Icons.arrow_downward : Icons.arrow_upward;
    final iconColor = isCredit ? Colors.green : AppTheme.primaryColor;
    final iconBg = isCredit ? Colors.green.withValues(alpha: 0.1) : AppTheme.primaryColor.withValues(alpha: 0.1);
    final amountColor = isCredit ? Colors.green : AppTheme.primaryColor;
    final amountPrefix = isCredit ? '+' : '-';

    // Get description based on type
    String title;
    switch (entry.type) {
      case 'topup':
        title = 'Wallet Topup';
        break;
      case 'manual_fund':
        title = entry.description ?? 'Manual Fund';
        break;
      case 'paystack_topup':
        title = 'Paystack Topup';
        break;
      case 'payment':
        title = entry.description ?? 'Payment';
        break;
      case 'refund':
        title = 'Refund';
        break;
      case 'withdrawal':
        title = 'Withdrawal';
        break;
      default:
        title = entry.description ?? entry.type;
    }

    // Format the date
    final now = DateTime.now();
    final diff = now.difference(entry.createdAt);
    String timeStr;
    if (diff.inDays == 0) {
      timeStr = 'Today, ${entry.createdAt.hour.toString().padLeft(2, '0')}:${entry.createdAt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      timeStr = 'Yesterday';
    } else {
      timeStr = '${entry.createdAt.day}/${entry.createdAt.month}/${entry.createdAt.year}';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: iconBg,
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(timeStr),
        trailing: Text(
          '$amountPrefix${currencyFormat.format(entry.amount)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: amountColor,
            fontWeight: FontWeight.bold,
          ),
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
              'Wallet History',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          Expanded(
            child: Consumer<WalletProvider>(
              builder: (context, provider, _) {
                if (provider.walletHistory.isEmpty) {
                  return const Center(child: Text('No transactions yet'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: provider.walletHistory.length,
                  itemBuilder: (context, index) {
                    return _TransactionTile(
                      entry: provider.walletHistory[index],
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

class _WalletScreen extends StatelessWidget {
  const _WalletScreen();

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>().wallet;
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Wallet',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.secondaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Balance',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currencyFormat.format(wallet?.balance ?? 0),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            CustomButton(
              text: 'Top Up Wallet',
              icon: Icons.add,
              isFullWidth: true,
              onPressed: () {
                _showTopUpBottomSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTopUpBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Up Amount',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children:
                      [500, 1000, 2000, 5000, 10000].map((amount) {
                        return ChoiceChip(
                          label: Text('₦$amount'),
                          selected: false,
                          onSelected: (selected) async {
                            final walletProvider = context.read<WalletProvider>();
                            Navigator.pop(context);
                            await walletProvider.topUp(
                              amount.toDouble(),
                            );
                          },
                        );
                      }).toList(),
                ),
                const SizedBox(height: 24),
                // Testing option - manual fund (for dev only)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Testing Only - Instant Fund',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.amber.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [500, 1000, 5000, 10000].map((amount) {
                          return ElevatedButton(
                            onPressed: () async {
                              final walletProvider = context.read<WalletProvider>();
                              final result = await walletProvider.manualFund(
                                amount.toDouble(),
                                reason: 'Testing',
                              );
                              if (context.mounted) {
                                Navigator.pop(context);
                                if (result) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('₦$amount added to wallet')),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            child: Text('₦$amount'),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
                            user?.name.substring(0, 1).toUpperCase() ?? 'U',
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
                    user?.name ?? 'User',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    user?.email ?? '',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _ProfileTile(
              icon: Icons.person_outline,
              title: 'Edit Profile',
              onTap: () => Navigator.of(context).pushNamed('/buyer/profile/edit'),
            ),
            _ProfileTile(
              icon: Icons.lock_outline,
              title: 'Change PIN',
              onTap: () => Navigator.of(context).pushNamed('/buyer/profile/change-pin'),
            ),
            _ProfileTile(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              onTap: () => Navigator.of(context).pushNamed('/buyer/profile/notifications'),
            ),
            _ProfileTile(
              icon: Icons.help_outline,
              title: 'Help & Support',
              onTap: () => Navigator.of(context).pushNamed('/buyer/profile/help'),
            ),
            _ProfileTile(
              icon: Icons.info_outline,
              title: 'About',
              onTap: () => Navigator.of(context).pushNamed('/buyer/profile/about'),
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
