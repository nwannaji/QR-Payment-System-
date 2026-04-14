import 'dart:async';

/// Request deduplication service that prevents duplicate in-flight API calls.
///
/// When multiple widgets request the same data simultaneously (e.g., on
/// screen transitions), this service returns the existing Future instead
/// of creating a new request. This eliminates wasted bandwidth and
/// reduces perceived latency on 3G connections.
class DeduplicationService {
  DeduplicationService._();
  static final DeduplicationService _instance = DeduplicationService._();
  factory DeduplicationService() => _instance;

  /// Map of in-flight requests keyed by dedup key.
  final Map<String, Future<dynamic>> _inFlight = {};

  /// Execute a request with deduplication. If a request with the same key
  /// is already in-flight, returns the existing Future instead of making
  /// a new request.
  ///
  /// [key] should be a unique identifier for the request, e.g. "GET:/wallet"
  /// [request] is the async function that performs the actual API call
  Future<T> dedup<T>(String key, Future<T> Function() request) async {
    // If there's already an in-flight request for this key, wait for it
    if (_inFlight.containsKey(key)) {
      return await _inFlight[key]!;
    }

    // Create the request and store the Future
    final future = request();
    _inFlight[key] = future;

    try {
      final result = await future;
      return result;
    } catch (e) {
      rethrow;
    } finally {
      // Remove from in-flight map after completion
      _inFlight.remove(key);
    }
  }

  /// Invalidate a dedup key. Call this after a POST/PUT/DELETE that
  /// changes data associated with a GET key. For example, after
  /// `POST /transactions/payment`, invalidate `GET:/wallet`.
  void invalidate(String key) {
    _inFlight.remove(key);
  }

  /// Invalidate all keys matching a prefix.
  /// E.g., invalidatePrefix('GET:/wallet') invalidates 'GET:/wallet'
  /// and 'GET:/wallet/ledger'.
  void invalidatePrefix(String prefix) {
    _inFlight.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Clear all in-flight dedup entries.
  void clear() {
    _inFlight.clear();
  }
}