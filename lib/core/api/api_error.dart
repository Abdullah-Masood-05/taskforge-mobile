import 'package:dio/dio.dart';

/// Mirrors the backend's standard error envelope:
/// `{ status: "error", code, message, errors: { field: [msg] } }`.
class ApiError implements Exception {
  ApiError(
      {required this.status,
      required this.code,
      required this.message,
      this.errors = const {}});

  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> errors;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;

  /// First field-level error message for [field], if any.
  String? fieldError(String field) {
    final v = errors[field];
    if (v == null) return null;
    if (v is List && v.isNotEmpty) return v.first.toString();
    return v.toString();
  }

  /// Best human-readable message: the summary, else the first field error.
  String get friendly {
    if (errors.isNotEmpty &&
        (message.isEmpty || message.toLowerCase().contains('invalid input'))) {
      final first = errors.entries.first;
      final v = first.value;
      final msg = v is List && v.isNotEmpty ? v.first.toString() : v.toString();
      return first.key == 'non_field_errors' ? msg : msg;
    }
    return message.isEmpty ? 'Something went wrong.' : message;
  }

  factory ApiError.fromDio(DioException e) {
    final res = e.response;
    if (res == null) {
      return ApiError(
        status: 0,
        code: 'network_error',
        message: e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout
            ? 'The server is taking a while to respond. It may be waking up — try again in a moment.'
            : 'Unable to reach TaskForge. Check your connection.',
      );
    }
    final data = res.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final errors = map['errors'] is Map
          ? Map<String, dynamic>.from(map['errors'] as Map)
          : <String, dynamic>{};
      return ApiError(
        status: res.statusCode ?? 0,
        code: (map['code'] ?? 'error').toString(),
        message: (map['message'] ??
                map['detail'] ??
                'Request failed (${res.statusCode}).')
            .toString(),
        errors: errors,
      );
    }
    return ApiError(
      status: res.statusCode ?? 0,
      code: 'parse_error',
      message: 'Server returned status ${res.statusCode}.',
    );
  }

  @override
  String toString() => 'ApiError($status, $code): $message';
}

/// Turns any thrown object into a user-facing message.
String errorMessage(Object error) {
  if (error is ApiError) return error.friendly;
  if (error is DioException) return ApiError.fromDio(error).friendly;
  return 'Something went wrong.';
}
