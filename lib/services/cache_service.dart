import 'dart:convert';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'cache_keys.dart';

/// Stale-While-Revalidate (SWR) cache service using Hive.
///
/// Returns cached data instantly (even if stale), then kicks off a background
/// refresh. This eliminates loading spinners on screen transitions.
class CacheService {
  CacheService._();
  static final CacheService _instance = CacheService._();
  factory CacheService() => _instance;

  static const String _boxName = 'qrpay_cache';
  Box<dynamic>? _box;

  /// Initialize Hive and open the cache box.
  /// Must be called once at app startup before any cache operations.
  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  Box<dynamic> get _cacheBox {
    if (_box == null || !_box!.isOpen) {
      throw StateError('CacheService not initialized. Call CacheService().init() first.');
    }
    return _box!;
  }

  // ---- Core SWR Methods ----

  /// Read a cached value. Returns null if not cached.
  /// Does NOT check TTL — the caller decides whether stale data is acceptable.
  T? read<T>(String key) {
    try {
      final entry = _cacheBox.get(key);
      if (entry == null) return null;
      if (entry is! Map) return null;
      final data = entry['data'];
      if (data is T) return data;
      // Attempt JSON decode for complex types stored as strings
      if (data is String && T != String) {
        return jsonDecode(data) as T;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Read a cached JSON map. Returns null if not cached or invalid.
  Map<String, dynamic>? readJson(String key) {
    try {
      final entry = _cacheBox.get(key);
      if (entry == null) return null;
      if (entry is! Map) return null;
      final data = entry['data'];
      if (data is Map<String, dynamic>) return data;
      if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Read a cached JSON list. Returns null if not cached or invalid.
  List<Map<String, dynamic>>? readJsonList(String key) {
    try {
      final entry = _cacheBox.get(key);
      if (entry == null) return null;
      if (entry is! Map) return null;
      final data = entry['data'];
      if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Write a value to cache with an optional TTL.
  /// [ttl] is used by [isStale] to determine freshness.
  Future<void> write(String key, dynamic value, {Duration? ttl}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _cacheBox.put(key, {
      'data': value is Map || value is List ? jsonEncode(value) : value,
      'cachedAt': now,
      'ttl': ttl?.inMilliseconds ?? CacheKeys.walletTtl.inMilliseconds,
    });
  }

  /// Write a JSON map to cache.
  Future<void> writeJson(String key, Map<String, dynamic> value, {Duration? ttl}) async {
    await write(key, jsonEncode(value), ttl: ttl);
  }

  /// Write a list of JSON maps to cache.
  Future<void> writeJsonList(String key, List<Map<String, dynamic>> value, {Duration? ttl}) async {
    await write(key, jsonEncode(value), ttl: ttl);
  }

  /// Check if a cached entry is stale (TTL exceeded).
  bool isStale(String key) {
    try {
      final entry = _cacheBox.get(key);
      if (entry == null || entry is! Map) return true;
      final cachedAt = entry['cachedAt'] as int?;
      final ttlMs = entry['ttl'] as int?;
      if (cachedAt == null || ttlMs == null) return true;
      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      return age > ttlMs;
    } catch (_) {
      return true;
    }
  }

  /// Check if a cached entry exists and is still fresh (within TTL).
  bool isFresh(String key) {
    try {
      final entry = _cacheBox.get(key);
      if (entry == null || entry is! Map) return false;
      final cachedAt = entry['cachedAt'] as int?;
      final ttlMs = entry['ttl'] as int?;
      if (cachedAt == null || ttlMs == null) return false;
      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      return age <= ttlMs;
    } catch (_) {
      return false;
    }
  }

  /// Remove a cached entry.
  Future<void> remove(String key) async {
    await _cacheBox.delete(key);
  }

  /// Remove all cached entries.
  Future<void> clear() async {
    await _cacheBox.clear();
  }

  // ---- SWR Convenience Methods ----

  /// Stale-While-Revalidate pattern for typed data.
  ///
  /// Returns cached data immediately (if any) via [onCached], then
  /// fetches fresh data via [fetcher] and provides it via [onFresh].
  ///
  /// If no cached data exists, shows loading and waits for [fetcher].
  Future<T> swr<T>({
    required String cacheKey,
    required Future<T> Function() fetcher,
    required Duration ttl,
    required void Function(T data) onCached,
    required void Function(T data) onFresh,
    void Function(String? error)? onError,
  }) async {
    // Try to return cached data immediately
    final cached = read<T>(cacheKey);
    if (cached != null) {
      onCached(cached);

      // Kick off background refresh if stale
      if (isStale(cacheKey)) {
        try {
          final fresh = await fetcher();
          await write(cacheKey, fresh, ttl: ttl);
          onFresh(fresh);
        } catch (e) {
          onError?.call(e.toString());
        }
      }
      return cached;
    }

    // No cache — must wait for network
    try {
      final fresh = await fetcher();
      await write(cacheKey, fresh, ttl: ttl);
      onFresh(fresh);
      return fresh;
    } catch (e) {
      onError?.call(e.toString());
      rethrow;
    }
  }

  /// SWR for JSON-serializable model objects.
  ///
  /// Similar to [swr] but handles JSON serialization/deserialization
  /// using the provided [fromJson] and [toJson] functions.
  Future<T> swrModel<T>({
    required String cacheKey,
    required Future<T> Function() fetcher,
    required Duration ttl,
    required Map<String, dynamic> Function(T) toJson,
    required T Function(Map<String, dynamic>) fromJson,
    required void Function(T data) onCached,
    required void Function(T data) onFresh,
    void Function(String? error)? onError,
  }) async {
    // Try cache first
    final cachedJson = readJson(cacheKey);
    if (cachedJson != null) {
      try {
        final cachedModel = fromJson(cachedJson);
        onCached(cachedModel);

        // Background refresh if stale
        if (isStale(cacheKey)) {
          try {
            final fresh = await fetcher();
            await writeJson(cacheKey, toJson(fresh), ttl: ttl);
            onFresh(fresh);
          } catch (e) {
            onError?.call(e.toString());
          }
        }
        return cachedModel;
      } catch (_) {
        // Cached data corrupt — remove and refetch
        await remove(cacheKey);
      }
    }

    // No valid cache — must fetch
    try {
      final fresh = await fetcher();
      await writeJson(cacheKey, toJson(fresh), ttl: ttl);
      onFresh(fresh);
      return fresh;
    } catch (e) {
      onError?.call(e.toString());
      rethrow;
    }
  }

  /// SWR for lists of JSON-serializable model objects.
  Future<List<T>> swrModelList<T>({
    required String cacheKey,
    required Future<List<T>> Function() fetcher,
    required Duration ttl,
    required List<Map<String, dynamic>> Function(List<T>) toJsonList,
    required T Function(Map<String, dynamic>) fromJson,
    required void Function(List<T> data) onCached,
    required void Function(List<T> data) onFresh,
    void Function(String? error)? onError,
  }) async {
    // Try cache first
    final cachedJsonList = readJsonList(cacheKey);
    if (cachedJsonList != null) {
      try {
        final cachedModels = cachedJsonList.map(fromJson).toList();
        onCached(cachedModels);

        // Background refresh if stale
        if (isStale(cacheKey)) {
          try {
            final fresh = await fetcher();
            await writeJsonList(cacheKey, toJsonList(fresh), ttl: ttl);
            onFresh(fresh);
          } catch (e) {
            onError?.call(e.toString());
          }
        }
        return cachedModels;
      } catch (_) {
        await remove(cacheKey);
      }
    }

    // No valid cache — must fetch
    try {
      final fresh = await fetcher();
      await writeJsonList(cacheKey, toJsonList(fresh), ttl: ttl);
      onFresh(fresh);
      return fresh;
    } catch (e) {
      onError?.call(e.toString());
      rethrow;
    }
  }
}