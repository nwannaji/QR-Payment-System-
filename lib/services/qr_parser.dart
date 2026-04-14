import 'dart:convert';
import '../models/qr_code.dart';

/// Result of local QR parsing.
class QrParseResult {
  /// Whether the QR code could be parsed locally.
  final bool isValid;

  /// The parsed QR data, if available.
  final QRCodeData? qrData;

  /// Whether this is a Paystack URL that should be opened in browser.
  final bool isPaystackUrl;

  /// The Paystack URL, if applicable.
  final String? paystackUrl;

  /// Whether the QR code has expired (based on embedded expiry).
  final bool isExpired;

  /// Whether the QR code needs server-side verification.
  /// True for custom QR payloads that have a signature to validate server-side.
  final bool needsServerVerification;

  /// Error message if parsing failed.
  final String? errorMessage;

  /// The merchant ID extracted from the QR code (available without server call).
  final String? merchantId;

  /// The merchant name extracted from the QR code (available without server call).
  final String? merchantName;

  QrParseResult({
    this.isValid = false,
    this.qrData,
    this.isPaystackUrl = false,
    this.paystackUrl,
    this.isExpired = false,
    this.needsServerVerification = false,
    this.errorMessage,
    this.merchantId,
    this.merchantName,
  });
}

/// Service for parsing and validating QR codes locally before
/// making a server round-trip. This eliminates the 200-800ms server
/// verify delay by navigating to the payment screen immediately
/// based on locally-parsed data, then verifying with the server
/// in the background.
class QrParser {
  QrParser._();
  static final QrParser _instance = QrParser._();
  factory QrParser() => _instance;

  /// Parse a raw QR string locally.
  ///
  /// Returns a [QrParseResult] indicating what kind of QR code it is
  /// and whether it can be processed without a server call.
  QrParseResult parse(String qrString) {
    if (qrString.isEmpty) {
      return QrParseResult(
        isValid: false,
        errorMessage: 'Empty QR code',
      );
    }

    // 1. Check if it's a Paystack URL — these are opened in browser directly
    if (qrString.startsWith('https://checkout.paystack.com/') ||
        qrString.startsWith('https://paystack.com/pay/')) {
      return QrParseResult(
        isValid: true,
        isPaystackUrl: true,
        paystackUrl: qrString,
      );
    }

    // 2. Try parsing using the existing QRCodeData.fromQRString
    final qrData = QRCodeData.fromQRString(qrString);
    if (qrData == null) {
      // Unrecognized format — needs server verification
      return QrParseResult(
        isValid: false,
        needsServerVerification: true,
        errorMessage: 'Unrecognized QR code format',
      );
    }

    // 3. Check if it's a Paystack URL QR (parsed from JSON format)
    if (qrData.isPaystackURL && qrData.paymentUrl != null) {
      return QrParseResult(
        isValid: true,
        isPaystackUrl: true,
        paystackUrl: qrData.paymentUrl,
      );
    }

    // 4. Extract merchant info from locally-parsed data
    String? merchantId = qrData.merchantId;
    String? merchantName = qrData.merchantName;

    // For compact base64 format, extract from the payload
    if (qrData.qrPayloadCompact != null) {
      try {
        final decoded = utf8.decode(base64Decode(qrData.qrPayloadCompact!));
        final parts = decoded.split('|');
        if (parts.isNotEmpty) {
          merchantId = parts[0];
        }
      } catch (_) {
        // Invalid base64 — fall through
      }
    }

    // Try to get merchant info from qrPayload map
    if (qrData.qrPayload != null) {
      merchantId ??= qrData.qrPayload!['merchant_id'] as String?;
      merchantName = qrData.qrPayload!['merchant_name'] as String?;
    }

    // 5. Check for expiry in the payload
    bool isExpired = false;
    if (qrData.qrPayload != null) {
      final expiryStr = qrData.qrPayload?['expiry'] as String?;
      if (expiryStr != null) {
        final expiry = DateTime.tryParse(expiryStr);
        if (expiry != null && expiry.isBefore(DateTime.now())) {
          isExpired = true;
        }
      }
    }
    if (qrData.qrPayloadCompact != null) {
      try {
        final decoded = utf8.decode(base64Decode(qrData.qrPayloadCompact!));
        final parts = decoded.split('|');
        if (parts.length >= 2) {
          final expiry = DateTime.tryParse(parts[1]);
          if (expiry != null && expiry.isBefore(DateTime.now())) {
            isExpired = true;
          }
        }
      } catch (_) {
        // Can't check expiry — proceed optimistically
      }
    }

    // 6. If we have merchant ID and name, we can navigate immediately
    if (merchantId != null && merchantId.isNotEmpty && merchantName != null && merchantName.isNotEmpty) {
      return QrParseResult(
        isValid: true,
        qrData: qrData,
        isExpired: isExpired,
        needsServerVerification: true, // Always verify with server for security
        merchantId: merchantId,
        merchantName: merchantName,
      );
    }

    // 7. Partial parse — needs server verification to get merchant details
    return QrParseResult(
      isValid: false,
      qrData: qrData,
      needsServerVerification: true,
      merchantId: merchantId,
      errorMessage: 'QR code requires server verification',
    );
  }
}