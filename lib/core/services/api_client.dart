import 'dart:convert';
import 'dart:io';

import '../config/api_config.dart';
import 'auth_service.dart';

/// Cliente HTTP mínimo con `Authorization: Bearer` para rutas bajo `/api`.
class ApiClient {
  ApiClient._();

  static Map<String, String> _jsonHeaders() {
    final h = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };
    final t = AuthSession.accessToken;
    if (t != null && t.isNotEmpty) {
      h[HttpHeaders.authorizationHeader] = 'Bearer $t';
    }
    return h;
  }

  static Future<String> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final uri = ApiConfig.uri(path, queryParameters: queryParameters);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      _jsonHeaders().forEach(request.headers.set);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GET $uri -> ${response.statusCode}: $body',
          uri: uri,
        );
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> post(
    String path, {
    Map<String, dynamic>? queryParameters,
    Object? body,
  }) async {
    final uri = ApiConfig.uri(path, queryParameters: queryParameters);
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      _jsonHeaders().forEach(request.headers.set);
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'POST $uri -> ${response.statusCode}: $text',
          uri: uri,
        );
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> put(
    String path, {
    Map<String, dynamic>? queryParameters,
    Object? body,
  }) async {
    final uri = ApiConfig.uri(path, queryParameters: queryParameters);
    final client = HttpClient();
    try {
      final request = await client.putUrl(uri);
      _jsonHeaders().forEach(request.headers.set);
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'PUT $uri -> ${response.statusCode}: $text',
          uri: uri,
        );
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> delete(String path) async {
    final uri = ApiConfig.uri(path);
    final client = HttpClient();
    try {
      final request = await client.deleteUrl(uri);
      _jsonHeaders().forEach(request.headers.set);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'DELETE $uri -> ${response.statusCode}: $text',
          uri: uri,
        );
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }
}
