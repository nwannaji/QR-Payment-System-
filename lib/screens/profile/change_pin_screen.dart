import 'package:flutter/material.dart';
import '../../api/backend_api.dart';
import '../../utils/theme.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/custom_input.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _currentPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _api = BackendApi();

  bool _isLoading = false;
  bool _isFirstTimeSetup = false;

  @override
  void initState() {
    super.initState();
    _checkPinStatus();
  }

  Future<void> _checkPinStatus() async {
    // Try to verify with dummy PIN to check if PIN is set
    // If response says "PIN not set", it's first time setup
    try {
      final response = await _api.verifyPin('0000');
      if (!response.success && response.message?.contains('not set') == true) {
        setState(() => _isFirstTimeSetup = true);
      }
    } catch (_) {
      // Ignore - they'll see error when submitting
    }
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  String? _validatePin(String? value, {String? otherValue, bool isConfirm = false}) {
    if (value == null || value.isEmpty) {
      return 'PIN is required';
    }
    if (value.length != 4) {
      return 'PIN must be 4 digits';
    }
    if (!RegExp(r'^\d{4}$').hasMatch(value)) {
      return 'PIN must contain only digits';
    }
    if (isConfirm && otherValue != null && value != otherValue) {
      return 'PINs do not match';
    }
    return null;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
      ),
    );
  }

  Future<void> _changePin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = _isFirstTimeSetup
          ? await _api.setPin(newPin: _newPinController.text)
          : await _api.changePin(
              currentPin: _currentPinController.text,
              newPin: _newPinController.text,
            );

      if (response.success) {
        _showSnackBar(_isFirstTimeSetup ? 'PIN set successfully' : 'PIN changed successfully');
        if (mounted) Navigator.pop(context);
      } else {
        _showSnackBar(response.message ?? 'Failed to change PIN', isError: true);
      }
    } catch (e) {
      _showSnackBar('An unexpected error occurred', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change PIN'),
        backgroundColor: AppTheme.surfaceColor,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(height: 24),
                Text(
                  _isFirstTimeSetup ? 'Set Your PIN' : 'Change Your PIN',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _isFirstTimeSetup
                      ? 'Create a 4-digit PIN to secure your account'
                      : 'Enter your current PIN and choose a new one',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),

                // Current PIN (only if has existing PIN)
                if (!_isFirstTimeSetup) ...[
                  Text(
                    'Current PIN',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CustomInput(
                    controller: _currentPinController,
                    hint: 'Enter current PIN',
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    validator: (value) => _validatePin(value),
                  ),
                  const SizedBox(height: 24),
                ],

                // New PIN
                Text(
                  'New PIN',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                CustomInput(
                  controller: _newPinController,
                  hint: 'Enter new PIN',
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  validator: (value) => _validatePin(value),
                ),
                const SizedBox(height: 24),

                // Confirm new PIN
                Text(
                  'Confirm New PIN',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                CustomInput(
                  controller: _confirmPinController,
                  hint: 'Confirm new PIN',
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  validator: (value) => _validatePin(
                    value,
                    otherValue: _newPinController.text,
                    isConfirm: true,
                  ),
                ),
                const SizedBox(height: 32),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: CustomButton(
                    text: _isFirstTimeSetup ? 'Set PIN' : 'Change PIN',
                    type: ButtonType.primary,
                    isLoading: _isLoading,
                    onPressed: _changePin,
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
