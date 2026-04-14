import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../api/backend_api.dart';
import '../../providers/wallet_provider.dart';
import '../../utils/theme.dart';

class BuyerTransactionsScreen extends StatelessWidget {
  const BuyerTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet History'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Consumer<WalletProvider>(
          builder: (context, provider, _) {
            if (provider.walletHistory.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 64,
                      color: AppTheme.textHint,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No transactions yet',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: provider.walletHistory.length,
              itemBuilder: (context, index) {
                final entry = provider.walletHistory[index];
                return _TransactionTile(entry: entry);
              },
            );
          },
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
