// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_response_dto.freezed.dart';
part 'login_response_dto.g.dart';

@freezed
class PermissionDto with _$PermissionDto {
  const factory PermissionDto({
    required int id,
    required String name,
  }) = _PermissionDto;
  factory PermissionDto.fromJson(Map<String, dynamic> json) =>
      _$PermissionDtoFromJson(json);
}

@freezed
class RoleDto with _$RoleDto {
  const factory RoleDto({
    required int id,
    required String name,
    @Default([]) List<PermissionDto> permissions,
  }) = _RoleDto;
  factory RoleDto.fromJson(Map<String, dynamic> json) =>
      _$RoleDtoFromJson(json);
}

@freezed
class BranchSummaryDto with _$BranchSummaryDto {
  const factory BranchSummaryDto({
    required int id,
    required String name,
    String? address,
    String? city,
    String? department,
  }) = _BranchSummaryDto;
  factory BranchSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$BranchSummaryDtoFromJson(json);
}

@freezed
class UserResponseDto with _$UserResponseDto {
  const factory UserResponseDto({
    required int id,
    required String username,
    String? email,
    String? phone,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
    @JsonKey(name: 'role_id') int? roleId,
    @JsonKey(name: 'branch_id') int? branchId,
    RoleDto? role,
    BranchSummaryDto? branch,
    @JsonKey(name: 'skill_level') int? skillLevel,
    @JsonKey(name: 'direct_permissions')
    @Default([])
    List<PermissionDto> directPermissions,
  }) = _UserResponseDto;
  factory UserResponseDto.fromJson(Map<String, dynamic> json) =>
      _$UserResponseDtoFromJson(json);
}

@freezed
class LoginResponseDto with _$LoginResponseDto {
  const factory LoginResponseDto({
    @JsonKey(name: 'access_token') required String accessToken,
    @JsonKey(name: 'token_type') @Default('bearer') String tokenType,
    required UserResponseDto user,
    @JsonKey(name: 'expires_at') String? expiresAt,
    @JsonKey(name: 'expires_in_minutes') int? expiresInMinutes,
  }) = _LoginResponseDto;
  factory LoginResponseDto.fromJson(Map<String, dynamic> json) =>
      _$LoginResponseDtoFromJson(json);
}
