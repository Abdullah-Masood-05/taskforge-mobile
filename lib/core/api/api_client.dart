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
class ApiClient {
  ApiClient(this._tokens) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiPrefix,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 45),
      headers: {'Accept': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final skip = options.extra['skipAuth'] == true;
        final access = _tokens.access;
        if (!skip && access != null) {
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

        final ok = await _refresh();
        if (!ok) {
          await _tokens.clear();
          onAuthExpired?.call();
          return handler.next(e);
        }
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

  final TokenStorage _tokens;
  late final Dio _dio;
  Completer<bool>? _refreshing;

  /// Called when the session can't be refreshed (forces re-login).
  void Function()? onAuthExpired;

  Future<bool> _refresh() async {
    if (_refreshing != null) return _refreshing!.future;
    final c = _refreshing = Completer<bool>();
    try {
      final res =
          await Dio(BaseOptions(baseUrl: AppConfig.apiPrefix)).post<dynamic>(
        '/auth/token/refresh/',
        data: {'refresh': _tokens.refresh},
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      await _tokens.save(
        access: data['access'] as String,
        refresh: (data['refresh'] as String?) ?? _tokens.refresh,
      );
      c.complete(true);
    } catch (_) {
      c.complete(false);
    } finally {
      _refreshing = null;
    }
    return c.future;
  }

  Options _opts(String? org, bool skipAuth, [Options? base]) {
    final o = base ?? Options();
    return o.copyWith(
      headers: {...?o.headers, if (org != null) 'X-Organization-Slug': org},
      extra: {...?o.extra, 'skipAuth': skipAuth},
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

  Future<dynamic> post(String path,
          {Object? body, String? org, bool skipAuth = false}) =>
      _send(() =>
          _dio.post<dynamic>(path, data: body, options: _opts(org, skipAuth)));

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
