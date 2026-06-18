import '../../data/models/login_response_dto.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    this.email,
    this.phone,
    required this.isActive,
    this.roleId,
    this.branchId,
    this.roleName,
    this.branchName,
    this.skillLevel,
    this.permissions = const [],
  });

  final int id;
  final String username;
  final String? email;
  final String? phone;
  final bool isActive;
  final int? roleId;
  final int? branchId;
  final String? roleName;
  final String? branchName;
  final int? skillLevel;
  final List<String> permissions;

  factory AuthUser.fromDto(UserResponseDto dto) {
    final rolePerms =
        dto.role?.permissions.map((PermissionDto p) => p.name) ??
            const <String>[];
    final directPerms = dto.directPermissions.map((PermissionDto p) => p.name);
    return AuthUser(
      id: dto.id,
      username: dto.username,
      email: dto.email,
      phone: dto.phone,
      isActive: dto.isActive,
      roleId: dto.roleId,
      branchId: dto.branchId,
      roleName: dto.role?.name,
      branchName: dto.branch?.name,
      skillLevel: dto.skillLevel,
      permissions: <String>{...rolePerms, ...directPerms}.toList(),
    );
  }

  bool hasPermission(String permission) => permissions.contains(permission);
}
