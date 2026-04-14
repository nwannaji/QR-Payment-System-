import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/theme.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Frequently Asked Questions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _FaqTile(
                question: 'How do I make a payment?',
                answer:
                    'Tap the scan icon on the home screen, point your camera at the merchant\'s QR code, enter the amount and your PIN to confirm.',
              ),
              _FaqTile(
                question: 'How do I top up my wallet?',
                answer:
                    'Go to the Home tab and tap "Top Up Wallet". Choose an amount or enter a custom amount, then complete the payment via Paystack.',
              ),
              _FaqTile(
                question: 'How do I generate a QR code as a merchant?',
                answer:
                    'Navigate to the QR Code tab on your merchant dashboard. Your payment QR code is generated automatically and can be shared via the Share button.',
              ),
              _FaqTile(
                question: 'What happens if a payment fails?',
                answer:
                    'Failed payments are automatically retried if there\'s a network issue. If the payment was debited but not received, it will be reversed within 24 hours.',
              ),
              _FaqTile(
                question: 'How do I change my PIN?',
                answer:
                    'Go to Profile > Change PIN. You\'ll need to enter your current PIN and then set a new one.',
              ),
              _FaqTile(
                question: 'Is my money safe?',
                answer:
                    'Yes. All transactions are secured with bank-grade encryption. Your PIN is hashed before transmission and never stored in plaintext.',
              ),
              const SizedBox(height: 32),
              Text(
                'Contact Us',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _ContactTile(
                icon: Icons.email_outlined,
                title: 'Email Support',
                subtitle: 'support@qrpay.ng',
                onTap: () => _launchUrl('mailto:support@qrpay.ng'),
              ),
              _ContactTile(
                icon: Icons.phone_outlined,
                title: 'Call Us',
                subtitle: '+234 800 QR PAY NG',
                onTap: () => _launchUrl('tel:+2348007772964'),
              ),
              _ContactTile(
                icon: Icons.chat_outlined,
                title: 'WhatsApp',
                subtitle: '+234 800 QR PAY NG',
                onTap: () => _launchUrl('https://wa.me/2348007772964'),
              ),
              const SizedBox(height: 32),
              Text(
                'Report a Problem',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _launchUrl('mailto:bugs@qrpay.ng?subject=Bug%20Report'),
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('Email Bug Report'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.15),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        iconColor: AppTheme.primaryColor,
        collapsedIconColor: AppTheme.textSecondary,
        title: Text(
          widget.question,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        children: [
          Text(
            widget.answer,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppTheme.primaryColor, size: 22),
      ),
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textHint),
      onTap: onTap,
    );
  }
}