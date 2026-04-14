import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api/backend_api.dart';
import '../../models/bank_account.dart';
import '../../utils/theme.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/custom_input.dart';

class BankAccountScreen extends StatefulWidget {
  const BankAccountScreen({super.key});

  @override
  State<BankAccountScreen> createState() => _BankAccountScreenState();
}

class _BankAccountScreenState extends State<BankAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bankNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _api = BackendApi();

  BankAccount? _existingAccount;
  bool _isLoading = true;
  bool _isSaving = false;

  // Common Nigerian banks
  static const _nigerianBanks = [
    'Access Bank',
    'Zenith Bank',
    'GTBank',
    'UBA',
    'First Bank',
    'Fidelity Bank',
    'Sterling Bank',
    'Ecobank',
    'Union Bank',
    'NIBSS',
    'Palmpay',
    'Moniepoint',
    'Kuda Bank',
    'Opay',
    'PalmPay',
  ];

  String? _selectedBank;

  @override
  void initState() {
    super.initState();
    _loadBankAccount();
  }

  @override
  void dispose() {
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _accountNameController.dispose();
    super.dispose();
  }

  Future<void> _loadBankAccount() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _api.getBankAccount();
      if (response.success && response.data != null) {
        _existingAccount = response.data;
        _bankNameController.text = response.data!.bankName;
        _accountNumberController.text = response.data!.accountNumber;
        _accountNameController.text = response.data!.accountName;
        _selectedBank = response.data!.bankName;
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveBankAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final response = await _api.saveBankAccount(
        bankName: _bankNameController.text.trim(),
        accountNumber: _accountNumberController.text.trim(),
        accountName: _accountNameController.text.trim(),
      );

      if (response.success && response.data != null) {
        _existingAccount = response.data;
        _showSnackBar('Bank account saved');
        if (mounted) Navigator.pop(context);
      } else {
        _showSnackBar(response.message ?? 'Failed to save bank account', isError: true);
      }
    } catch (e) {
      _showSnackBar('An unexpected error occurred', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteBankAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Bank Account'),
        content: const Text('Are you sure you want to remove your bank account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final response = await _api.deleteBankAccount();
      if (response.success) {
        _existingAccount = null;
        _bankNameController.clear();
        _accountNumberController.clear();
        _accountNameController.clear();
        _showSnackBar('Bank account removed');
      } else {
        _showSnackBar(response.message ?? 'Failed to remove bank account', isError: true);
      }
    } catch (e) {
      _showSnackBar('An unexpected error occurred', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting = _existingAccount != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bank Account'),
        backgroundColor: AppTheme.surfaceColor,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          if (hasExisting)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
              onPressed: _deleteBankAccount,
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: AppTheme.primaryColor,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Add your bank account details to receive withdrawals from your wallet balance.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Bank Name
                      Text(
                        'Bank Name',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedBank,
                        decoration: InputDecoration(
                          hintText: 'Select your bank',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: _nigerianBanks.map((bank) {
                          return DropdownMenuItem(
                            value: bank,
                            child: Text(bank),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedBank = value;
                            _bankNameController.text = value ?? '';
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select your bank';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Account Number
                      Text(
                        'Account Number',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      CustomInput(
                        controller: _accountNumberController,
                        hint: '10-digit account number',
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Account number is required';
                          }
                          if (value.length != 10) {
                            return 'Account number must be 10 digits';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Account Name
                      Text(
                        'Account Name',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      CustomInput(
                        controller: _accountNameController,
                        hint: 'Name on your bank account',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Account name is required';
                          }
                          if (value.trim().length < 3) {
                            return 'Please enter a valid account name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        child: CustomButton(
                          text: hasExisting ? 'Update Bank Account' : 'Save Bank Account',
                          type: ButtonType.primary,
                          isLoading: _isSaving,
                          onPressed: _saveBankAccount,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}