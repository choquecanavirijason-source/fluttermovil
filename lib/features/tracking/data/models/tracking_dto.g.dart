// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tracking_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$NamedRefDtoImpl _$$NamedRefDtoImplFromJson(Map<String, dynamic> json) =>
    _$NamedRefDtoImpl(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
    );

Map<String, dynamic> _$$NamedRefDtoImplToJson(_$NamedRefDtoImpl instance) =>
    <String, dynamic>{'id': instance.id, 'name': instance.name};

_$TrackingDtoImpl _$$TrackingDtoImplFromJson(Map<String, dynamic> json) =>
    _$TrackingDtoImpl(
      id: (json['id'] as num).toInt(),
      lastApplicationDate: json['last_application_date'] as String?,
      designNotes: json['design_notes'] as String?,
      eyeType: json['eye_type'] == null
          ? null
          : NamedRefDto.fromJson(json['eye_type'] as Map<String, dynamic>),
      effect: json['effect'] == null
          ? null
          : NamedRefDto.fromJson(json['effect'] as Map<String, dynamic>),
      volume: json['volume'] == null
          ? null
          : NamedRefDto.fromJson(json['volume'] as Map<String, dynamic>),
      lashDesign: json['lash_design'] == null
          ? null
          : NamedRefDto.fromJson(json['lash_design'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$TrackingDtoImplToJson(_$TrackingDtoImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'last_application_date': instance.lastApplicationDate,
      'design_notes': instance.designNotes,
      'eye_type': instance.eyeType,
      'effect': instance.effect,
      'volume': instance.volume,
      'lash_design': instance.lashDesign,
    };
