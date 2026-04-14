import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../api/backend_api.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/custom_input.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _businessAddressController = TextEditingController();
  final _api = BackendApi();
  final _picker = ImagePicker();

  File? _selectedImage;
  bool _isUploading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    if (user != null) {
      _nameController.text = user.name;
      _phoneController.text = user.phone;
      _businessNameController.text = user.businessName ?? '';
      _businessAddressController.text = user.businessAddress ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _businessNameController.dispose();
    _businessAddressController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _isUploading = true;
        });
        await _uploadAvatar();
      }
    } catch (e) {
      _showSnackBar('Failed to pick image', isError: true);
    }
  }

  Future<void> _uploadAvatar() async {
    final selectedImage = _selectedImage;
    if (selectedImage == null) return;

    final authProvider = context.read<AuthProvider>();

    try {
      final response = await _api.uploadAvatar(selectedImage);
      if (response.success && response.data != null) {
        await authProvider.refreshUser();
        if (mounted) _showSnackBar('Profile picture updated');
      } else if (mounted) {
        _showSnackBar(response.message ?? 'Failed to upload avatar', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('Failed to upload avatar', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _showImageSourcePicker() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppTheme.primaryColor),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppTheme.primaryColor),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final authProvider = context.read<AuthProvider>();
    final user = authProvider.user;
    final success = await authProvider.updateProfile(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      businessName: user?.role == UserRole.merchant ? _businessNameController.text.trim() : null,
      businessAddress: user?.role == UserRole.merchant ? _businessAddressController.text.trim() : null,
    );

    setState(() => _isSaving = false);

    if (success) {
      _showSnackBar('Profile updated successfully');
      if (mounted) Navigator.pop(context);
    } else {
      _showSnackBar(authProvider.error ?? 'Failed to update profile', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isMerchant = user?.role == UserRole.merchant;

    return Scaffold(
      appBar: AppBar(
        title: Text(isMerchant ? 'Business Details' : 'Edit Profile'),
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
              children: [
                // Avatar
                Stack(
                  children: [
                    Builder(builder: (context) {
                      final selectedImage = _selectedImage;
                      final avatarUrl = user?.avatarUrl;
                      return CircleAvatar(
                        radius: 56,
                        backgroundColor: AppTheme.primaryColor,
                        backgroundImage: selectedImage != null
                            ? FileImage(selectedImage)
                            : avatarUrl != null
                                ? NetworkImage(_api.getAvatarUrl(avatarUrl))
                                : null,
                        child: selectedImage == null && avatarUrl == null
                            ? Text(
                                (user?.name ?? 'U').substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      );
                    }),
                    if (_isUploading)
                      Positioned.fill(
                        child: CircleAvatar(
                          backgroundColor: Colors.black45,
                          child: const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _showImageSourcePicker,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Name
                CustomInput(
                  label: 'Full Name',
                  controller: _nameController,
                  hint: 'Enter your full name',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone
                CustomInput(
                  label: 'Phone Number',
                  controller: _phoneController,
                  hint: 'e.g. 08012345678',
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Phone number is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email (read-only)
                CustomInput(
                  label: 'Email',
                  controller: TextEditingController(text: user?.email ?? ''),
                  hint: 'Email address',
                  enabled: false,
                ),
                const SizedBox(height: 16),

                // Business name (merchant only)
                if (isMerchant) ...[
                  CustomInput(
                    label: 'Business Name',
                    controller: _businessNameController,
                    hint: 'Enter your business name',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Business name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  CustomInput(
                    label: 'Business Address',
                    controller: _businessAddressController,
                    hint: 'Enter your business address',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                ],

                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: CustomButton(
                    text: 'Save Changes',
                    type: ButtonType.primary,
                    isLoading: _isSaving,
                    onPressed: _saveProfile,
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
