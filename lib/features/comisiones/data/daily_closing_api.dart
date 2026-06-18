import 'package:dio/dio.dart';

import '../../../core/network/api_endpoints.dart';
import 'models/daily_closing_dto.dart';

class DailyClosingApi {
  const DailyClosingApi(this._dio);

  final Dio _dio;

  Future<DailyClosingResponseDto> getClosing({
    required String date,
    required int professionalId,
    int? branchId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.reportsDailyClosing,
      queryParameters: {
        'date': date,
        'professional_id': professionalId,
        if (branchId != null) 'branch_id': branchId,
      },
    );
    return DailyClosingResponseDto.fromJson(response.data!);
  }
}
