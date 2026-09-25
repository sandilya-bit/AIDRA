import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../error/failure.dart';

/// Thin wrapper over Dio. Repositories depend on this (not on Dio directly) so
/// transport concerns — auth headers, idempotency keys, retries and error
/// translation — live in exactly one place.
class ApiClient {
  ApiClient({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
                connectTimeout: AppConfig.apiTimeout,
                receiveTimeout: AppConfig.apiTimeout,
                sendTimeout: AppConfig.apiTimeout,
                headers: <String, dynamic>{'Accept': 'application/json'},
                // Never throw on 4xx: we map status codes to typed failures.
                validateStatus: (int? status) => status != null && status < 500,
              ),
            );

  final Dio _dio;

  String? _accessToken;

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  Map<String, dynamic> _headers({String? idempotencyKey}) => <String, dynamic>{
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      };

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        path,
        queryParameters: query,
        options: Options(headers: _headers()),
      );
      return _decode(response);
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        path,
        queryParameters: query,
        options: Options(headers: _headers()),
      );
      _throwIfServerError(response);
      final dynamic data = response.data;
      if (data is List<dynamic>) return data;
      if (data is Map<String, dynamic>) {
        final dynamic items = data['items'] ?? data['data'];
        if (items is List<dynamic>) return items;
      }
      return const <dynamic>[];
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    String? idempotencyKey,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        path,
        data: body,
        options: Options(headers: _headers(idempotencyKey: idempotencyKey)),
      );
      return _decode(response);
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final Response<dynamic> response = await _dio.patch<dynamic>(
        path,
        data: body,
        options: Options(headers: _headers()),
      );
      return _decode(response);
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Map<String, dynamic> _decode(Response<dynamic> response) {
    _throwIfServerError(response);
    final dynamic data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is List<dynamic>) return <String, dynamic>{'items': data};
    return <String, dynamic>{};
  }

  void _throwIfServerError(Response<dynamic> response) {
    final int status = response.statusCode ?? 0;
    if (status >= 500) {
      throw ServerFailure(status, 'Server error ($status). Please retry.');
    }
    if (status == 401 || status == 403) {
      throw const AuthFailure('Your session expired. Please sign in again.');
    }
    if (status >= 400) {
      final dynamic body = response.data;
      final String detail = body is Map<String, dynamic>
          ? (body['message']?.toString() ?? 'Request failed ($status).')
          : 'Request failed ($status).';
      throw ServerFailure(status, detail);
    }
  }

  Failure _mapDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkFailure('The network is slow. Please retry.');
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return NetworkFailure.withCause(
          'Could not reach AIDRA servers.',
          error,
        );
      case DioExceptionType.cancel:
        return const NetworkFailure('Request cancelled.');
      case DioExceptionType.badCertificate:
        return const NetworkFailure('Secure connection could not be verified.');
      case DioExceptionType.badResponse:
        final int status = error.response?.statusCode ?? 0;
        if (status == 401 || status == 403) {
          return const AuthFailure();
        }
        return ServerFailure(status, 'Request failed ($status).', cause: error);
    }
  }
}
