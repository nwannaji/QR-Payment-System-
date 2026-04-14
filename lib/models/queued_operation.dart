/// Data model for a queued offline operation.
///
/// Represents a payment or top-up that failed due to network issues
/// and is waiting to be retried when connectivity is restored.
class QueuedOperation {
  final String id;
  final String type; // 'payment', 'topup', 'manual_fund'
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final String? idempotencyKey;
  final String status; // 'pending', 'processing', 'failed'

  QueuedOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.idempotencyKey,
    this.status = 'pending',
  });

  QueuedOperation copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    int? retryCount,
    String? idempotencyKey,
    String? status,
  }) {
    return QueuedOperation(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'payload': payload,
    'created_at': createdAt.toIso8601String(),
    'retry_count': retryCount,
    'idempotency_key': idempotencyKey,
    'status': status,
  };

  factory QueuedOperation.fromJson(Map<String, dynamic> json) => QueuedOperation(
    id: json['id'] as String,
    type: json['type'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    createdAt: DateTime.parse(json['created_at'] as String),
    retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
    idempotencyKey: json['idempotency_key'] as String?,
    status: json['status'] as String? ?? 'pending',
  );
}