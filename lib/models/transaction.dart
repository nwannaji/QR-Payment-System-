enum TransactionStatus { pending, completed, failed, cancelled }

enum TransactionType { payment, refund, topup, withdrawal }

class Transaction {
  final String id;
  final String buyerId;
  final String? buyerName;
  final String? merchantId;
  final String? merchantName;
  final double amount;
  final String currency;
  final TransactionStatus status;
  final TransactionType type;
  final String? reference;
  final String? description;
  final DateTime createdAt;
  final DateTime? completedAt;

  Transaction({
    required this.id,
    required this.buyerId,
    this.buyerName,
    this.merchantId,
    this.merchantName,
    required this.amount,
    this.currency = 'NGN',
    required this.status,
    required this.type,
    this.reference,
    this.description,
    required this.createdAt,
    this.completedAt,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final amountValue = json['amount'];
    double amount;
    if (amountValue is double) {
      amount = amountValue;
    } else if (amountValue is int) {
      amount = amountValue.toDouble();
    } else if (amountValue is String) {
      amount = double.tryParse(amountValue) ?? 0.0;
    } else {
      amount = 0.0;
    }
    return Transaction(
      id: json['id'] ?? '',
      buyerId: json['buyer_id'] ?? '',
      buyerName: json['buyer_name'],
      merchantId: json['merchant_id'],
      merchantName: json['merchant_name'],
      amount: amount,
      currency: json['currency'] ?? 'NGN',
      status: _parseStatus(json['status']),
      type: _parseType(json['type']),
      reference: json['reference'],
      description: json['description'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      completedAt:
          json['completed_at'] != null
              ? DateTime.tryParse(json['completed_at'])
              : null,
    );
  }

  static TransactionStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return TransactionStatus.completed;
      case 'failed':
        return TransactionStatus.failed;
      case 'cancelled':
        return TransactionStatus.cancelled;
      default:
        return TransactionStatus.pending;
    }
  }

  static TransactionType _parseType(String? type) {
    switch (type?.toLowerCase()) {
      case 'refund':
        return TransactionType.refund;
      case 'topup':
        return TransactionType.topup;
      case 'withdrawal':
        return TransactionType.withdrawal;
      default:
        return TransactionType.payment;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'buyer_id': buyerId,
      'buyer_name': buyerName,
      'merchant_id': merchantId,
      'merchant_name': merchantName,
      'amount': amount,
      'currency': currency,
      'status': status.name,
      'type': type.name,
      'reference': reference,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  Transaction copyWith({
    String? id,
    String? buyerId,
    String? buyerName,
    String? merchantId,
    String? merchantName,
    double? amount,
    String? currency,
    TransactionStatus? status,
    TransactionType? type,
    String? reference,
    String? description,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      buyerId: buyerId ?? this.buyerId,
      buyerName: buyerName ?? this.buyerName,
      merchantId: merchantId ?? this.merchantId,
      merchantName: merchantName ?? this.merchantName,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      type: type ?? this.type,
      reference: reference ?? this.reference,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
