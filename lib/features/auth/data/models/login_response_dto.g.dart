// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_response_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PermissionDtoImpl _$$PermissionDtoImplFromJson(Map<String, dynamic> json) =>
    _$PermissionDtoImpl(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
    );

Map<String, dynamic> _$$PermissionDtoImplToJson(_$PermissionDtoImpl instance) =>
    <String, dynamic>{'id': instance.id, 'name': instance.name};

_$RoleDtoImpl _$$RoleDtoImplFromJson(Map<String, dynamic> json) =>
    _$RoleDtoImpl(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      permissions:
          (json['permissions'] as List<dynamic>?)
              ?.map((e) => PermissionDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$$RoleDtoImplToJson(_$RoleDtoImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'permissions': instance.permissions,
    };

_$BranchSummaryDtoImpl _$$BranchSummaryDtoImplFromJson(
  Map<String, dynamic> json,
) => _$BranchSummaryDtoImpl(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  address: json['address'] as String?,
  city: json['city'] as String?,
  department: json['department'] as String?,
);

Map<String, dynamic> _$$BranchSummaryDtoImplToJson(
  _$BranchSummaryDtoImpl instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'address': instance.address,
  'city': instance.city,
  'department': instance.department,
};

_$UserResponseDtoImpl _$$UserResponseDtoImplFromJson(
  Map<String, dynamic> json,
) => _$UserResponseDtoImpl(
  id: (json['id'] as num).toInt(),
  username: json['username'] as String,
  email: json['email'] as String?,
  phone: json['phone'] as String?,
  isActive: json['is_active'] as bool? ?? true,
  roleId: (json['role_id'] as num?)?.toInt(),
  branchId: (json['branch_id'] as num?)?.toInt(),
  role: json['role'] == null
      ? null
      : RoleDto.fromJson(json['role'] as Map<String, dynamic>),
  branch: json['branch'] == null
      ? null
      : BranchSummaryDto.fromJson(json['branch'] as Map<String, dynamic>),
  skillLevel: (json['skill_level'] as num?)?.toInt(),
  directPermissions:
      (json['direct_permissions'] as List<dynamic>?)
          ?.map((e) => PermissionDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$$UserResponseDtoImplToJson(
  _$UserResponseDtoImpl instance,
) => <String, dynamic>{
  'id': instance.id,
  'username': instance.username,
  'email': instance.email,
  'phone': instance.phone,
  'is_active': instance.isActive,
  'role_id': instance.roleId,
  'branch_id': instance.branchId,
  'role': instance.role,
  'branch': instance.branch,
  'skill_level': instance.skillLevel,
  'direct_permissions': instance.directPermissions,
};

_$LoginResponseDtoImpl _$$LoginResponseDtoImplFromJson(
  Map<String, dynamic> json,
) => _$LoginResponseDtoImpl(
  accessToken: json['access_token'] as String,
  tokenType: json['token_type'] as String? ?? 'bearer',
  user: UserResponseDto.fromJson(json['user'] as Map<String, dynamic>),
  expiresAt: json['expires_at'] as String?,
  expiresInMinutes: (json['expires_in_minutes'] as num?)?.toInt(),
);

Map<String, dynamic> _$$LoginResponseDtoImplToJson(
  _$LoginResponseDtoImpl instance,
) => <String, dynamic>{
  'access_token': instance.accessToken,
  'token_type': instance.tokenType,
  'user': instance.user,
  'expires_at': instance.expiresAt,
  'expires_in_minutes': instance.expiresInMinutes,
};
