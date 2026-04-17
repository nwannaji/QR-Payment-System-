import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../../api/backend_api.dart';
import '../../providers/merchant_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/cache_service.dart';
import '../../services/cache_keys.dart';
import 'payment_screen.dart';
import '../../utils/theme.dart';
import '../../widgets/common/custom_button.dart';

class PaymentConfirmationScreen extends StatefulWidget {
  final String merchantId;
  final String merchantName;

  const PaymentConfirmationScreen({
    super.key,
    required this.merchantId,
    required this.merchantName,
  });

  @override
  State<PaymentConfirmationScreen> createState() => _PaymentConfirmationScreenState();
}

class _PaymentConfirmationScreenState extends State<PaymentConfirmationScreen> with WidgetsBindingObserver {
  final _amountController = TextEditingController();
  final _api = BackendApi();
  final _cache = CacheService();
  bool _isLoading = false;
  bool _isBanksLoading = true;
  String? _error;
  String? _lastPaymentReference;
  String? _lastPaymentUrl;
  double? _lastPaymentAmount;
  bool _isVerifying = false;

  List<PaystackBank> _banks = [];
  PaystackBank? _selectedBank;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBanks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-verify payment when user returns from the Paystack browser
    if (state == AppLifecycleState.resumed && _lastPaymentReference != null && !_isVerifying && !_isLoading) {
      _verifyPayment();
    }
  }

  Future<void> _loadBanks() async {
    // Try loading from cache first (P2-3: banks list caching)
    final cachedBanks = _cache.readJsonList(CacheKeys.banksList);
    if (cachedBanks != null && cachedBanks.isNotEmpty) {
      if (mounted) {
        setState(() {
          _banks = cachedBanks.map((json) => PaystackBank.fromJson(json)).toList();
          _isBanksLoading = false;
        });
      }
      // If cache is fresh, no need to re-fetch
      if (_cache.isFresh(CacheKeys.banksList)) {
        return;
      }
    }

    // Fetch from API (background refresh if cache existed, foreground if not)
    final response = await _api.getBanks();
    if (mounted) {
      if (response.success && response.data != null) {
        // Cache the banks list with 24-hour TTL
        await _cache.writeJsonList(
          CacheKeys.banksList,
          response.data!.map((b) => {'name': b.name, 'code': b.code, 'slug': b.slug}).toList(),
          ttl: CacheKeys.banksListTtl,
        );
        setState(() {
          _banks = response.data!;
          _isBanksLoading = false;
        });
      } else {
        setState(() {
          _isBanksLoading = false;
          _error = response.message ?? 'Failed to load banks';
        });
      }
    }
  }

  Future<bool> _openPaystackCheckout(String url) async {
    final uri = Uri.parse(url);
    try {
      // Try external browser first
      bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) return true;

      // Fallback to platform default
      launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (launched) return true;

      debugPrint('launchUrl returned false for: $url');
      setState(() => _error = 'Could not open browser. Tap "Re-open Page" to retry.');
      return false;
    } catch (e) {
      debugPrint('launchUrl exception: $e');
      setState(() => _error = 'Failed to open payment page: $e');
      return false;
    }
  }

  Future<void> _initiatePayment() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Please enter a valid amount');
      return;
    }

    if (_selectedBank == null) {
      setState(() => _error = 'Please select your bank');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _api.initializeBankCharge(
        amount: amount,
        merchantId: widget.merchantId,
        merchantName: widget.merchantName,
        bankCode: _selectedBank!.code,
      );

      debugPrint('Bank charge response: success=${response.success}, authUrl=${response.authUrl}, ref=${response.reference}, msg=${response.message}');

      if (response.success && response.authUrl != null && mounted) {
        _lastPaymentReference = response.reference;
        _lastPaymentUrl = response.authUrl;
        _lastPaymentAmount = amount;

        final opened = await _openPaystackCheckout(response.authUrl!);
        if (mounted) {
          if (opened) {
            _showProcessingDialog(amount);
          } else {
            setState(() => _error = 'Could not open browser. Please try again.');
          }
        }
      } else if (mounted) {
        setState(() => _error = response.message ?? 'Failed to initialize payment');
      }
    } catch (e) {
      debugPrint('Payment init error: $e');
      if (mounted) {
        setState(() => _error = 'Network error. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showProcessingDialog(double amount) {
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance, color: AppTheme.primaryColor),
              SizedBox(width: 12),
              Flexible(child: Text('Complete Payment')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      currencyFormat.format(amount),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      widget.merchantName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Steps to complete:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _buildStep(1, 'A payment page opened in your browser. Switch to it.'),
              const SizedBox(height: 4),
              _buildStep(2, 'Select "Pay with Bank" and choose ${_selectedBank?.name ?? "your bank"}, then authorize the payment.'),
              const SizedBox(height: 4),
              _buildStep(3, 'Come back here and tap "I\'ve Completed Payment".'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            if (_lastPaymentUrl != null)
              TextButton(
                onPressed: () => _openPaystackCheckout(_lastPaymentUrl!),
                child: const Text('Re-open Page'),
              ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _verifyPayment();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("I've Completed Payment"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(
            child: Text(
              '$number',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  Future<void> _verifyPayment() async {
    if (_lastPaymentReference == null) {
      setState(() => _error = 'No payment reference found. Please try again.');
      return;
    }

    if (_isVerifying) return;
    _isVerifying = true;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _api.verifyPayment(reference: _lastPaymentReference!);

      if (!mounted) return;

      if (result['success'] == true && result['status'] == 'completed') {
        final amount = result['amount'] as double?;
        final merchantName = result['merchant_name'] as String? ?? widget.merchantName;

        // Refresh merchant data so balance and transactions update
        try {
          final merchantProvider = context.read<MerchantProvider>();
          final walletProvider = context.read<WalletProvider>();
          await merchantProvider.refresh();
          await walletProvider.loadWallet();
        } catch (_) {
          // Non-critical: refresh best-effort
        }

        if (mounted) {
          _showSuccessDialog(amount ?? 0, merchantName);
        }
      } else {
        // Payment not completed yet — show retry dialog
        setState(() => _isLoading = false);
        if (mounted) {
          _showRetryDialog(
            result['message'] ?? 'Payment not completed yet.',
            (result['status'] ?? 'unknown').toString(),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showRetryDialog('Could not verify payment. Please try again.', 'error');
      }
    } finally {
      _isVerifying = false;
    }
  }

  void _showRetryDialog(String message, String status) {
    final isAbandoned = status == 'abandoned';
    final isFailed = status == 'failed';
    final isProcessing = status == 'processing';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAbandoned ? Icons.browser_updated_outlined
                  : isFailed ? Icons.error_outline
                  : isProcessing ? Icons.hourglass_top
                  : Icons.info_outline,
              color: isAbandoned || isFailed ? AppTheme.warningColor
                  : isProcessing ? AppTheme.primaryColor
                  : AppTheme.warningColor,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              isAbandoned ? 'Payment Not Completed'
                  : isFailed ? 'Payment Failed'
                  : isProcessing ? 'Payment Processing'
                  : 'Verification Pending',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            if (isAbandoned) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, color: AppTheme.primaryColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can re-open the payment page or start a new payment.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
            },
            child: const Text('Go Back'),
          ),
          if (isAbandoned && _lastPaymentUrl != null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _openPaystackCheckout(_lastPaymentUrl!);
                _showProcessingDialog(_lastPaymentAmount ?? 0);
              },
              child: const Text('Re-open Page'),
            ),
          if (isAbandoned || isFailed)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _lastPaymentReference = null;
                _initiatePayment();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Try Again'),
            )
          else
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _verifyPayment();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Check Again'),
            ),
        ],
      ),
    );
  }

  void _showSuccessDialog(double amount, String merchantName) {
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);
    setState(() => _isLoading = false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(Icons.check_circle, color: AppTheme.successColor, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              'Payment Successful!',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppTheme.successColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              currencyFormat.format(amount),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Paid to $merchantName',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Payment'),
        backgroundColor: AppTheme.surfaceColor,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Merchant info card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: AppTheme.primaryColor,
                              child: Text(
                                widget.merchantName.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.merchantName,
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'QR Payment',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Amount input
                      Text(
                        'Enter Amount',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        style: Theme.of(context).textTheme.headlineMedium,
                        decoration: InputDecoration(
                          prefixText: '₦ ',
                          prefixStyle: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: AppTheme.textPrimary,
                          ),
                          hintText: '0.00',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Bank selection dropdown
                      Text(
                        'Select Your Bank',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _isBanksLoading
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.textHint.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Loading banks...'),
                                ],
                              ),
                            )
                          : DropdownButtonFormField<PaystackBank>(
                              value: _selectedBank,
                              decoration: InputDecoration(
                                hintText: 'Choose your bank',
                                prefixIcon: const Icon(Icons.account_balance, color: AppTheme.primaryColor),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                                ),
                              ),
                              items: _banks.map((bank) {
                                return DropdownMenuItem<PaystackBank>(
                                  value: bank,
                                  child: Text(
                                    bank.name,
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (bank) {
                                setState(() {
                                  _selectedBank = bank;
                                  _error = null;
                                });
                              },
                              validator: (_) => _selectedBank == null ? 'Please select a bank' : null,
                            ),
                      const SizedBox(height: 16),

                      // Error message
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.errorColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppTheme.errorColor, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(color: AppTheme.errorColor, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.primaryColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You\'ll be redirected to your bank\'s login page to authorize the payment securely.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Pay button (Bank charge)
              SizedBox(
                width: double.infinity,
                child: CustomButton(
                  text: 'Continue to Payment',
                  type: ButtonType.primary,
                  isLoading: _isLoading,
                  onPressed: _initiatePayment,
                ),
              ),
              const SizedBox(height: 12),

              // Pay with wallet (in-app PIN payment)
              SizedBox(
                width: double.infinity,
                child: CustomButton(
                  text: 'Pay with Wallet',
                  icon: Icons.account_balance_wallet,
                  type: ButtonType.outline,
                  isLoading: _isLoading,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PaymentScreen(
                          merchantId: widget.merchantId,
                          merchantName: widget.merchantName,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}