import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/transaction.dart';
import '../../providers/merchant_provider.dart';
import '../../utils/theme.dart';

class MerchantTransactionsScreen extends StatelessWidget {
  const MerchantTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Consumer<MerchantProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading && provider.transactions.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.transactions.isEmpty) {
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
              itemCount: provider.transactions.length,
              itemBuilder: (context, index) {
                final transaction = provider.transactions[index];
                return _TransactionTile(transaction: transaction);
              },
            );
          },
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
      return DateFormat('MMM d, y, h:mm a').format(dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);
    final isCompleted = transaction.status == TransactionStatus.completed;
    final buyerName = transaction.buyerName ?? transaction.merchantName ?? 'Payment';
    final buyerInitial = buyerName.isNotEmpty ? buyerName.substring(0, 1).toUpperCase() : 'P';

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: (isCompleted ? AppTheme.successColor : AppTheme.warningColor)
            .withValues(alpha: 0.15),
        child: Text(
          buyerInitial,
          style: TextStyle(
            color: isCompleted ? AppTheme.successColor : AppTheme.warningColor,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      title: Text(buyerName),
      subtitle: Text(_formatDate(transaction.createdAt)),
      trailing: Text(
        currencyFormat.format(transaction.amount),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: isCompleted ? AppTheme.successColor : AppTheme.warningColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
