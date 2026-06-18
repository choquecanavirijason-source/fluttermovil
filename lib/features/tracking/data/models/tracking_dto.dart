// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'tracking_dto.freezed.dart';
part 'tracking_dto.g.dart';

@freezed
class NamedRefDto with _$NamedRefDto {
  const factory NamedRefDto({
    required int id,
    @Default('') String name,
  }) = _NamedRefDto;

  factory NamedRefDto.fromJson(Map<String, dynamic> json) =>
      _$NamedRefDtoFromJson(json);
}

@freezed
class TrackingDto with _$TrackingDto {
  const factory TrackingDto({
    required int id,
    @JsonKey(name: 'last_application_date') String? lastApplicationDate,
    @JsonKey(name: 'design_notes') String? designNotes,
    @JsonKey(name: 'eye_type') NamedRefDto? eyeType,
    NamedRefDto? effect,
    NamedRefDto? volume,
    @JsonKey(name: 'lash_design') NamedRefDto? lashDesign,
  }) = _TrackingDto;

  factory TrackingDto.fromJson(Map<String, dynamic> json) =>
      _$TrackingDtoFromJson(json);
}
