// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_dto.freezed.dart';
part 'client_dto.g.dart';

@freezed
class ClientDto with _$ClientDto {
  const factory ClientDto({
    required int id,
    @Default('') String name,
    @JsonKey(name: 'last_name') String? lastName,
    String? phone,
    String? email,
    String? status,
  }) = _ClientDto;

  factory ClientDto.fromJson(Map<String, dynamic> json) =>
      _$ClientDtoFromJson(json);
}
