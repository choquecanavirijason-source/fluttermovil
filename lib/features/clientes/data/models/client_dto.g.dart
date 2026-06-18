// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ClientDtoImpl _$$ClientDtoImplFromJson(Map<String, dynamic> json) =>
    _$ClientDtoImpl(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      lastName: json['last_name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      status: json['status'] as String?,
    );

Map<String, dynamic> _$$ClientDtoImplToJson(_$ClientDtoImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'last_name': instance.lastName,
      'phone': instance.phone,
      'email': instance.email,
      'status': instance.status,
    };
