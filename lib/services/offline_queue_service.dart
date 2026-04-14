import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../api/backend_api.dart';
import '../models/queued_operation.dart';

/// Service for queuing operations when the network is unavailable
/// and retrying them when connectivity is restored.
///
/// Design decision: Idempotency keys are included in queued operations,
/// but payment retries require backend support for X-Idempotency-Key.
/// If the backend doesn't support idempotency keys, payments are NOT
/// auto-retried — instead, the user must manually retry to avoid
/// duplicate charges. Read operations (top-ups, etc.) are auto-retried.
class OfflineQueueService {
  OfflineQueueService._();
  static final OfflineQueueService _instance = OfflineQueueService._();
  factory OfflineQueueService() => _instance;

  static const String _boxName = 'qrpay_offline_queue';
  Box<String>? _box;
  final Uuid _uuid = const Uuid();

  /// Operations that are safe to auto-retry (no risk of duplication).
  static const _autoRetryableTypes = {'topup', 'manual_fund'};

  /// Maximum number of auto-retries per operation.
  static const int maxRetries = 3;

  /// Initialize the offline queue. Call once at app startup.
  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  Box<String> get _queueBox {
    if (_box == null || !_box!.isOpen) {
      throw StateError('OfflineQueueService not initialized. Call init() first.');
    }
    return _box!;
  }

  /// Enqueue a failed operation for later retry.
  ///
  /// Returns the queued operation's ID for tracking.
  Future<String> enqueue({
    required String type,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  }) async {
    final operation = QueuedOperation(
      id: _uuid.v4(),
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
      idempotencyKey: idempotencyKey ?? _uuid.v4(),
    );

    await _queueBox.put(operation.id, jsonEncode(operation.toJson()));
    debugPrint('[OfflineQueue] Enqueued ${operation.type} operation: ${operation.id}');
    return operation.id;
  }

  /// Get all pending operations.
  List<QueuedOperation> getPendingOperations() {
    return _queueBox.values
        .map((json) {
          try {
            return QueuedOperation.fromJson(
              jsonDecode(json) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<QueuedOperation>()
        .where((op) => op.status == 'pending')
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Get all failed operations (exceeded max retries).
  List<QueuedOperation> getFailedOperations() {
    return _queueBox.values
        .map((json) {
          try {
            return QueuedOperation.fromJson(
              jsonDecode(json) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<QueuedOperation>()
        .where((op) => op.status == 'failed')
        .toList();
  }

  /// Check if there are any pending or failed operations.
  bool get hasPendingOperations => getPendingOperations().isNotEmpty;

  /// Check if a specific operation type has pending items.
  bool hasPendingOfType(String type) =>
      getPendingOperations().any((op) => op.type == type);

  /// Process all auto-retryable pending operations.
  /// Called when connectivity is restored.
  ///
  /// Returns the number of operations successfully processed.
  Future<int> processPendingOperations() async {
    final pending = getPendingOperations();
    int processed = 0;

    for (final operation in pending) {
      if (_autoRetryableTypes.contains(operation.type)) {
        final success = await _processOperation(operation);
        if (success) {
          processed++;
        }
      }
      // Payment operations require manual user confirmation — don't auto-retry
    }

    return processed;
  }

  /// Manually retry a specific operation (for payments that need user confirmation).
  Future<bool> retryOperation(String operationId) async {
    final jsonStr = _queueBox.get(operationId);
    if (jsonStr == null) return false;

    try {
      final operation = QueuedOperation.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );

      final success = await _processOperation(operation);
      return success;
    } catch (_) {
      return false;
    }
  }

  /// Process a single operation.
  Future<bool> _processOperation(QueuedOperation operation) async {
    // Update status to processing
    await _updateOperationStatus(operation.id, 'processing');

    final api = BackendApi();
    bool success = false;

    try {
      switch (operation.type) {
        case 'topup':
          final response = await api.topUpWallet(
            amount: (operation.payload['amount'] as num).toDouble(),
          );
          success = response.success;
          break;

        case 'manual_fund':
          final response = await api.manualFundWallet(
            amount: (operation.payload['amount'] as num).toDouble(),
            reason: operation.payload['reason'] as String?,
          );
          success = response.success;
          break;

        case 'payment':
          // Only reached via manual retry — not auto-retried
          final response = await api.initiatePayment(
            merchantId: operation.payload['merchant_id'] as String,
            amount: (operation.payload['amount'] as num).toDouble(),
            pin: operation.payload['pin'] as String,
            description: operation.payload['description'] as String?,
          );
          success = response.success;
          break;

        default:
          debugPrint('[OfflineQueue] Unknown operation type: ${operation.type}');
          break;
      }
    } catch (e) {
      debugPrint('[OfflineQueue] Error processing operation: $e');
    }

    if (success) {
      // Remove from queue on success
      await _queueBox.delete(operation.id);
      debugPrint('[OfflineQueue] Successfully processed: ${operation.id}');
    } else {
      // Increment retry count
      final newRetryCount = operation.retryCount + 1;
      if (newRetryCount >= maxRetries) {
        // Mark as failed after max retries
        await _updateOperation(
          operation.id,
          operation.copyWith(retryCount: newRetryCount, status: 'failed'),
        );
        debugPrint('[OfflineQueue] Operation failed after $maxRetries retries: ${operation.id}');
      } else {
        // Keep pending for next retry
        await _updateOperation(
          operation.id,
          operation.copyWith(retryCount: newRetryCount, status: 'pending'),
        );
      }
    }

    return success;
  }

  /// Update the status of a queued operation.
  Future<void> _updateOperationStatus(String id, String status) async {
    final jsonStr = _queueBox.get(id);
    if (jsonStr == null) return;

    final operation = QueuedOperation.fromJson(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
    await _updateOperation(id, operation.copyWith(status: status));
  }

  /// Update a queued operation.
  Future<void> _updateOperation(String id, QueuedOperation operation) async {
    await _queueBox.put(id, jsonEncode(operation.toJson()));
  }

  /// Remove a specific operation from the queue.
  Future<void> removeOperation(String id) async {
    await _queueBox.delete(id);
  }

  /// Clear all operations from the queue.
  Future<void> clearAll() async {
    await _queueBox.clear();
  }
}