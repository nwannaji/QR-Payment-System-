import 'dart:convert';

class QRCodeData {
  final String merchantId;
  final String merchantName;
  final String? merchantAddress;
  /// Custom QR payload (JSON object) - used instead of Paystack URL
  final Map<String, dynamic>? qrPayload;
  /// Base64 compact QR payload for smaller QR codes
  final String? qrPayloadCompact;
  /// Legacy: Paystack URL (for backward compat with old QR codes)
  final String? paymentUrl;
  final String? reference;

  QRCodeData({
    required this.merchantId,
    required this.merchantName,
    this.merchantAddress,
    this.qrPayload,
    this.qrPayloadCompact,
    this.paymentUrl,
    this.reference,
  });

  factory QRCodeData.fromJson(Map<String, dynamic> json) {
    return QRCodeData(
      merchantId: json['merchant_id'] ?? '',
      merchantName: json['merchant_name'] ?? '',
      merchantAddress: json['merchant_address'],
      qrPayload: json['qr_payload'],
      qrPayloadCompact: json['qr_payload_compact'],
      paymentUrl: json['payment_url'],
      reference: json['reference'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'merchant_id': merchantId,
      'merchant_name': merchantName,
      'merchant_address': merchantAddress,
      'qr_payload': qrPayload,
      'qr_payload_compact': qrPayloadCompact,
      'payment_url': paymentUrl,
      'reference': reference,
    };
  }

  /// Encode what goes into the QR code itself.
  /// Priority: custom qr_payload > qr_payload_compact > paymentUrl (legacy)
  String toQRString() {
    // New format: custom QR payload as compact base64
    if (qrPayloadCompact != null && qrPayloadCompact!.isNotEmpty) {
      return qrPayloadCompact!;
    }
    // Alternative: custom QR payload as JSON
    if (qrPayload != null && qrPayload!.isNotEmpty) {
      return jsonEncode(qrPayload);
    }
    // Legacy: old Paystack URL QR codes
    if (paymentUrl != null && paymentUrl!.isNotEmpty) {
      return paymentUrl!;
    }
    return jsonEncode(toJson());
  }

  /// Parse a scanned QR string back into QRCodeData
  static QRCodeData? fromQRString(String qrString) {
    try {
      // Legacy: Paystack hosted checkout URL
      if (qrString.startsWith('https://checkout.paystack.com/') ||
          qrString.startsWith('https://paystack.com/pay/')) {
        return QRCodeData(
          merchantId: '',
          merchantName: '',
          paymentUrl: qrString,
        );
      }

      // Try JSON format: {"merchant_id": ..., "signature": ..., "expiry": ...}
      if (qrString.startsWith('{')) {
        final json = jsonDecode(qrString) as Map<String, dynamic>;
        return QRCodeData.fromJson({
          'merchant_id': json['merchant_id'] ?? '',
          'merchant_name': json['merchant_name'] ?? '',
          'merchant_address': json['merchant_address'],
          'qr_payload': json,
        });
      }

      // Compact base64: merchantId|expiry|signature
      final decoded = utf8.decode(base64Decode(qrString));
      final parts = decoded.split('|');
      if (parts.length >= 3) {
        return QRCodeData.fromJson({
          'merchant_id': parts[0],
          'expiry': parts[1],
          'signature': parts[2],
          'qr_payload': {
            'merchant_id': parts[0],
            'expiry': parts[1],
            'signature': parts[2],
          },
          'qr_payload_compact': qrString,
        });
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Check if this QR is a custom app QR (not a Paystack URL)
  bool get isCustomQR {
    return qrPayload != null || qrPayloadCompact != null;
  }

  /// Check if this QR is a legacy Paystack URL
  bool get isPaystackURL {
    return paymentUrl != null && paymentUrl!.isNotEmpty;
  }
}