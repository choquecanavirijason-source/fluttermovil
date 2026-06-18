import 'package:dio/dio.dart';

import '../../../core/network/api_endpoints.dart';
import 'models/login_response_dto.dart';

class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<LoginResponseDto> login(String username, String password) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.login,
      data: {'username': username, 'password': password},
      options: Options(extra: {'skipAuth': true}),
    );
    return LoginResponseDto.fromJson(response.data!);
  }

  Future<UserResponseDto> me() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiEndpoints.me);
    return UserResponseDto.fromJson(response.data!);
  }
}
