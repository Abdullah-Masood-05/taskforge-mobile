import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_storage.dart';
import '../config.dart';
import 'api_error.dart';

/// Thin Dio wrapper with the same behaviour as the web client:
/// - `Authorization: Bearer <access>` on every request (unless skipAuth)
/// - `X-Organization-Slug` when an org scope is passed
/// - On 401: one refresh attempt via /auth/token/refresh/, then retry; on
///   failure tokens are cleared and [onAuthExpired] fires.
/// - All non-2xx responses surface as [ApiError].
/// - The API runs on Render's free tier, which sleeps when idle and takes a
///   minute or more to boot. Timeouts are generous, idempotent requests are
///   retried while the server wakes, and [warmUp] pings /health/ early.
class ApiClient {
  ApiClient(this._tokens) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiPrefix,
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
      headers: {'Accept': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (e, handler) async {
        final opts = e.requestOptions;
        final attempt = (opts.extra['_attempt'] as int?) ?? 0;
        final idempotent = opts.method == 'GET' || opts.extra['retry'] == true;
        if (!idempotent || attempt >= _maxRetries || !_isWakingError(e)) {
          return handler.next(e);
        }
        await Future<void>.delayed(Duration(seconds: 2 << attempt));
        try {
          opts.extra['_attempt'] = attempt + 1;
          handler.resolve(await _dio.fetch<dynamic>(opts));
        } on DioException catch (err) {
          handler.next(err);
        }
      },
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final skip = options.extra['skipAuth'] == true;
        final access = _tokens.access;
        if (!skip &&
            access != null &&
            !options.headers.containsKey('Authorization')) {
          options.headers['Authorization'] = 'Bearer $access';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final opts = e.requestOptions;
        final shouldRefresh = e.response?.statusCode == 401 &&
            opts.extra['skipAuth'] != true &&
            opts.extra['_retry'] != true &&
            _tokens.refresh != null;
        if (!shouldRefresh) return handler.next(e);

        final result = await _refresh();
        if (result == _RefreshResult.rejected) {
          await _tokens.clear();
          onAuthExpired?.call();
          return handler.next(e);
        }
        // Server unreachable: keep the session and surface the error.
        if (result == _RefreshResult.unreachable) return handler.next(e);
        try {
          opts.extra['_retry'] = true;
          opts.headers['Authorization'] = 'Bearer ${_tokens.access}';
          final res = await _dio.fetch<dynamic>(opts);
          handler.resolve(res);
        } on DioException catch (err) {
          handler.next(err);
        }
      },
    ));
  }

  static const _connectTimeout = Duration(seconds: 30);
  static const _receiveTimeout = Duration(seconds: 90);
  static const _maxRetries = 3;

  final TokenStorage _tokens;
  late final Dio _dio;
  Completer<_RefreshResult>? _refreshing;
  DateTime? _lastWarmUp;

  /// True for failures that mean "the server is asleep or booting".
  static bool _isWakingError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        return code == 502 || code == 503 || code == 504;
      default:
        return false;
    }
  }

  /// Fire-and-forget ping so a sleeping Render instance starts booting before
  /// the first real request. Throttled to once every 30 seconds.
  void warmUp() {
    final now = DateTime.now();
    final last = _lastWarmUp;
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastWarmUp = now;
    Dio(BaseOptions(
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
    )).get<dynamic>('${AppConfig.apiBase}/health/').ignore();
  }

  /// Called when the session can't be refreshed (forces re-login).
  void Function()? onAuthExpired;

  Future<_RefreshResult> _refresh() async {
    if (_refreshing != null) return _refreshing!.future;
    final c = _refreshing = Completer<_RefreshResult>();
    final refreshDio = Dio(BaseOptions(
      baseUrl: AppConfig.apiPrefix,
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
    ));
    try {
      Response<dynamic>? res;
      for (var attempt = 0;; attempt++) {
        try {
          res = await refreshDio.post<dynamic>(
            '/auth/token/refresh/',
            data: {'refresh': _tokens.refresh},
          );
          break;
        } on DioException catch (e) {
          if (!_isWakingError(e) || attempt >= _maxRetries) rethrow;
          await Future<void>.delayed(Duration(seconds: 2 << attempt));
        }
      }
      final data = Map<String, dynamic>.from(res.data as Map);
      await _tokens.save(
        access: data['access'] as String,
        refresh: (data['refresh'] as String?) ?? _tokens.refresh,
      );
      c.complete(_RefreshResult.refreshed);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      c.complete(code == 400 || code == 401
          ? _RefreshResult.rejected
          : _RefreshResult.unreachable);
    } catch (_) {
      c.complete(_RefreshResult.unreachable);
    } finally {
      _refreshing = null;
    }
    return c.future;
  }

  Options _opts(String? org, bool skipAuth,
      [Map<String, String>? headers, bool retry = false]) {
    return Options(
      headers: {...?headers, if (org != null) 'X-Organization-Slug': org},
      extra: {'skipAuth': skipAuth, 'retry': retry},
    );
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      if (res.statusCode == 204) return null;
      return res.data;
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  Future<dynamic> get(String path,
          {String? org, Map<String, dynamic>? query, bool skipAuth = false}) =>
      _send(() => _dio.get<dynamic>(path,
          queryParameters: _clean(query), options: _opts(org, skipAuth)));

  /// [retry] marks a POST as safe to repeat while the server wakes up.
  Future<dynamic> post(String path,
          {Object? body,
          String? org,
          bool skipAuth = false,
          bool retry = false,
          Map<String, String>? headers}) =>
      _send(() => _dio.post<dynamic>(path,
          data: body, options: _opts(org, skipAuth, headers, retry)));

  Future<dynamic> patch(String path, {Object? body, String? org}) => _send(
      () => _dio.patch<dynamic>(path, data: body, options: _opts(org, false)));

  Future<dynamic> put(String path, {Object? body, String? org}) => _send(
      () => _dio.put<dynamic>(path, data: body, options: _opts(org, false)));

  Future<dynamic> delete(String path, {String? org}) =>
      _send(() => _dio.delete<dynamic>(path, options: _opts(org, false)));

  /// Multipart upload (e.g. project import, local attachment upload).
  Future<dynamic> postForm(String path, FormData form, {String? org}) => _send(
      () => _dio.post<dynamic>(path, data: form, options: _opts(org, false)));

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    return Map.fromEntries(
        q.entries.where((e) => e.value != null && e.value != ''));
  }
}

enum _RefreshResult { refreshed, rejected, unreachable }

final tokenStorageProvider = Provider<TokenStorage>(
    (ref) => throw UnimplementedError('overridden in main'));

final apiClientProvider =
    Provider<ApiClient>((ref) => ApiClient(ref.watch(tokenStorageProvider)));

/// Unwraps DRF list responses: paginated `{results: [...]}` or a bare list.
List<Map<String, dynamic>> unwrapList(dynamic data) {
  final raw = data is Map && data['results'] is List
      ? data['results'] as List
      : (data is List ? data : const []);
  return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
}
