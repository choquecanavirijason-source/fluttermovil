// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'login_response_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

PermissionDto _$PermissionDtoFromJson(Map<String, dynamic> json) {
  return _PermissionDto.fromJson(json);
}

/// @nodoc
mixin _$PermissionDto {
  int get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;

  /// Serializes this PermissionDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PermissionDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PermissionDtoCopyWith<PermissionDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PermissionDtoCopyWith<$Res> {
  factory $PermissionDtoCopyWith(
    PermissionDto value,
    $Res Function(PermissionDto) then,
  ) = _$PermissionDtoCopyWithImpl<$Res, PermissionDto>;
  @useResult
  $Res call({int id, String name});
}

/// @nodoc
class _$PermissionDtoCopyWithImpl<$Res, $Val extends PermissionDto>
    implements $PermissionDtoCopyWith<$Res> {
  _$PermissionDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PermissionDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? id = null, Object? name = null}) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as int,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PermissionDtoImplCopyWith<$Res>
    implements $PermissionDtoCopyWith<$Res> {
  factory _$$PermissionDtoImplCopyWith(
    _$PermissionDtoImpl value,
    $Res Function(_$PermissionDtoImpl) then,
  ) = __$$PermissionDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int id, String name});
}

/// @nodoc
class __$$PermissionDtoImplCopyWithImpl<$Res>
    extends _$PermissionDtoCopyWithImpl<$Res, _$PermissionDtoImpl>
    implements _$$PermissionDtoImplCopyWith<$Res> {
  __$$PermissionDtoImplCopyWithImpl(
    _$PermissionDtoImpl _value,
    $Res Function(_$PermissionDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PermissionDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? id = null, Object? name = null}) {
    return _then(
      _$PermissionDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as int,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$PermissionDtoImpl implements _PermissionDto {
  const _$PermissionDtoImpl({required this.id, required this.name});

  factory _$PermissionDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$PermissionDtoImplFromJson(json);

  @override
  final int id;
  @override
  final String name;

  @override
  String toString() {
    return 'PermissionDto(id: $id, name: $name)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PermissionDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name);

  /// Create a copy of PermissionDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PermissionDtoImplCopyWith<_$PermissionDtoImpl> get copyWith =>
      __$$PermissionDtoImplCopyWithImpl<_$PermissionDtoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PermissionDtoImplToJson(this);
  }
}

abstract class _PermissionDto implements PermissionDto {
  const factory _PermissionDto({
    required final int id,
    required final String name,
  }) = _$PermissionDtoImpl;

  factory _PermissionDto.fromJson(Map<String, dynamic> json) =
      _$PermissionDtoImpl.fromJson;

  @override
  int get id;
  @override
  String get name;

  /// Create a copy of PermissionDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PermissionDtoImplCopyWith<_$PermissionDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

RoleDto _$RoleDtoFromJson(Map<String, dynamic> json) {
  return _RoleDto.fromJson(json);
}

/// @nodoc
mixin _$RoleDto {
  int get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  List<PermissionDto> get permissions => throw _privateConstructorUsedError;

  /// Serializes this RoleDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of RoleDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RoleDtoCopyWith<RoleDto> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RoleDtoCopyWith<$Res> {
  factory $RoleDtoCopyWith(RoleDto value, $Res Function(RoleDto) then) =
      _$RoleDtoCopyWithImpl<$Res, RoleDto>;
  @useResult
  $Res call({int id, String name, List<PermissionDto> permissions});
}

/// @nodoc
class _$RoleDtoCopyWithImpl<$Res, $Val extends RoleDto>
    implements $RoleDtoCopyWith<$Res> {
  _$RoleDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RoleDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? permissions = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as int,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            permissions: null == permissions
                ? _value.permissions
                : permissions // ignore: cast_nullable_to_non_nullable
                      as List<PermissionDto>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$RoleDtoImplCopyWith<$Res> implements $RoleDtoCopyWith<$Res> {
  factory _$$RoleDtoImplCopyWith(
    _$RoleDtoImpl value,
    $Res Function(_$RoleDtoImpl) then,
  ) = __$$RoleDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int id, String name, List<PermissionDto> permissions});
}

/// @nodoc
class __$$RoleDtoImplCopyWithImpl<$Res>
    extends _$RoleDtoCopyWithImpl<$Res, _$RoleDtoImpl>
    implements _$$RoleDtoImplCopyWith<$Res> {
  __$$RoleDtoImplCopyWithImpl(
    _$RoleDtoImpl _value,
    $Res Function(_$RoleDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of RoleDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? permissions = null,
  }) {
    return _then(
      _$RoleDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as int,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        permissions: null == permissions
            ? _value._permissions
            : permissions // ignore: cast_nullable_to_non_nullable
                  as List<PermissionDto>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$RoleDtoImpl implements _RoleDto {
  const _$RoleDtoImpl({
    required this.id,
    required this.name,
    final List<PermissionDto> permissions = const [],
  }) : _permissions = permissions;

  factory _$RoleDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$RoleDtoImplFromJson(json);

  @override
  final int id;
  @override
  final String name;
  final List<PermissionDto> _permissions;
  @override
  @JsonKey()
  List<PermissionDto> get permissions {
    if (_permissions is EqualUnmodifiableListView) return _permissions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_permissions);
  }

  @override
  String toString() {
    return 'RoleDto(id: $id, name: $name, permissions: $permissions)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RoleDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality().equals(
              other._permissions,
              _permissions,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    name,
    const DeepCollectionEquality().hash(_permissions),
  );

  /// Create a copy of RoleDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RoleDtoImplCopyWith<_$RoleDtoImpl> get copyWith =>
      __$$RoleDtoImplCopyWithImpl<_$RoleDtoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RoleDtoImplToJson(this);
  }
}

abstract class _RoleDto implements RoleDto {
  const factory _RoleDto({
    required final int id,
    required final String name,
    final List<PermissionDto> permissions,
  }) = _$RoleDtoImpl;

  factory _RoleDto.fromJson(Map<String, dynamic> json) = _$RoleDtoImpl.fromJson;

  @override
  int get id;
  @override
  String get name;
  @override
  List<PermissionDto> get permissions;

  /// Create a copy of RoleDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RoleDtoImplCopyWith<_$RoleDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

BranchSummaryDto _$BranchSummaryDtoFromJson(Map<String, dynamic> json) {
  return _BranchSummaryDto.fromJson(json);
}

/// @nodoc
mixin _$BranchSummaryDto {
  int get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get address => throw _privateConstructorUsedError;
  String? get city => throw _privateConstructorUsedError;
  String? get department => throw _privateConstructorUsedError;

  /// Serializes this BranchSummaryDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of BranchSummaryDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BranchSummaryDtoCopyWith<BranchSummaryDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BranchSummaryDtoCopyWith<$Res> {
  factory $BranchSummaryDtoCopyWith(
    BranchSummaryDto value,
    $Res Function(BranchSummaryDto) then,
  ) = _$BranchSummaryDtoCopyWithImpl<$Res, BranchSummaryDto>;
  @useResult
  $Res call({
    int id,
    String name,
    String? address,
    String? city,
    String? department,
  });
}

/// @nodoc
class _$BranchSummaryDtoCopyWithImpl<$Res, $Val extends BranchSummaryDto>
    implements $BranchSummaryDtoCopyWith<$Res> {
  _$BranchSummaryDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BranchSummaryDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? address = freezed,
    Object? city = freezed,
    Object? department = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as int,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            address: freezed == address
                ? _value.address
                : address // ignore: cast_nullable_to_non_nullable
                      as String?,
            city: freezed == city
                ? _value.city
                : city // ignore: cast_nullable_to_non_nullable
                      as String?,
            department: freezed == department
                ? _value.department
                : department // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$BranchSummaryDtoImplCopyWith<$Res>
    implements $BranchSummaryDtoCopyWith<$Res> {
  factory _$$BranchSummaryDtoImplCopyWith(
    _$BranchSummaryDtoImpl value,
    $Res Function(_$BranchSummaryDtoImpl) then,
  ) = __$$BranchSummaryDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int id,
    String name,
    String? address,
    String? city,
    String? department,
  });
}

/// @nodoc
class __$$BranchSummaryDtoImplCopyWithImpl<$Res>
    extends _$BranchSummaryDtoCopyWithImpl<$Res, _$BranchSummaryDtoImpl>
    implements _$$BranchSummaryDtoImplCopyWith<$Res> {
  __$$BranchSummaryDtoImplCopyWithImpl(
    _$BranchSummaryDtoImpl _value,
    $Res Function(_$BranchSummaryDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of BranchSummaryDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? address = freezed,
    Object? city = freezed,
    Object? department = freezed,
  }) {
    return _then(
      _$BranchSummaryDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as int,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        address: freezed == address
            ? _value.address
            : address // ignore: cast_nullable_to_non_nullable
                  as String?,
        city: freezed == city
            ? _value.city
            : city // ignore: cast_nullable_to_non_nullable
                  as String?,
        department: freezed == department
            ? _value.department
            : department // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$BranchSummaryDtoImpl implements _BranchSummaryDto {
  const _$BranchSummaryDtoImpl({
    required this.id,
    required this.name,
    this.address,
    this.city,
    this.department,
  });

  factory _$BranchSummaryDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$BranchSummaryDtoImplFromJson(json);

  @override
  final int id;
  @override
  final String name;
  @override
  final String? address;
  @override
  final String? city;
  @override
  final String? department;

  @override
  String toString() {
    return 'BranchSummaryDto(id: $id, name: $name, address: $address, city: $city, department: $department)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BranchSummaryDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.address, address) || other.address == address) &&
            (identical(other.city, city) || other.city == city) &&
            (identical(other.department, department) ||
                other.department == department));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, name, address, city, department);

  /// Create a copy of BranchSummaryDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BranchSummaryDtoImplCopyWith<_$BranchSummaryDtoImpl> get copyWith =>
      __$$BranchSummaryDtoImplCopyWithImpl<_$BranchSummaryDtoImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$BranchSummaryDtoImplToJson(this);
  }
}

abstract class _BranchSummaryDto implements BranchSummaryDto {
  const factory _BranchSummaryDto({
    required final int id,
    required final String name,
    final String? address,
    final String? city,
    final String? department,
  }) = _$BranchSummaryDtoImpl;

  factory _BranchSummaryDto.fromJson(Map<String, dynamic> json) =
      _$BranchSummaryDtoImpl.fromJson;

  @override
  int get id;
  @override
  String get name;
  @override
  String? get address;
  @override
  String? get city;
  @override
  String? get department;

  /// Create a copy of BranchSummaryDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BranchSummaryDtoImplCopyWith<_$BranchSummaryDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

UserResponseDto _$UserResponseDtoFromJson(Map<String, dynamic> json) {
  return _UserResponseDto.fromJson(json);
}

/// @nodoc
mixin _$UserResponseDto {
  int get id => throw _privateConstructorUsedError;
  String get username => throw _privateConstructorUsedError;
  String? get email => throw _privateConstructorUsedError;
  String? get phone => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_active')
  bool get isActive => throw _privateConstructorUsedError;
  @JsonKey(name: 'role_id')
  int? get roleId => throw _privateConstructorUsedError;
  @JsonKey(name: 'branch_id')
  int? get branchId => throw _privateConstructorUsedError;
  RoleDto? get role => throw _privateConstructorUsedError;
  BranchSummaryDto? get branch => throw _privateConstructorUsedError;
  @JsonKey(name: 'skill_level')
  int? get skillLevel => throw _privateConstructorUsedError;
  @JsonKey(name: 'direct_permissions')
  List<PermissionDto> get directPermissions =>
      throw _privateConstructorUsedError;

  /// Serializes this UserResponseDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of UserResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UserResponseDtoCopyWith<UserResponseDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UserResponseDtoCopyWith<$Res> {
  factory $UserResponseDtoCopyWith(
    UserResponseDto value,
    $Res Function(UserResponseDto) then,
  ) = _$UserResponseDtoCopyWithImpl<$Res, UserResponseDto>;
  @useResult
  $Res call({
    int id,
    String username,
    String? email,
    String? phone,
    @JsonKey(name: 'is_active') bool isActive,
    @JsonKey(name: 'role_id') int? roleId,
    @JsonKey(name: 'branch_id') int? branchId,
    RoleDto? role,
    BranchSummaryDto? branch,
    @JsonKey(name: 'skill_level') int? skillLevel,
    @JsonKey(name: 'direct_permissions') List<PermissionDto> directPermissions,
  });

  $RoleDtoCopyWith<$Res>? get role;
  $BranchSummaryDtoCopyWith<$Res>? get branch;
}

/// @nodoc
class _$UserResponseDtoCopyWithImpl<$Res, $Val extends UserResponseDto>
    implements $UserResponseDtoCopyWith<$Res> {
  _$UserResponseDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UserResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? username = null,
    Object? email = freezed,
    Object? phone = freezed,
    Object? isActive = null,
    Object? roleId = freezed,
    Object? branchId = freezed,
    Object? role = freezed,
    Object? branch = freezed,
    Object? skillLevel = freezed,
    Object? directPermissions = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as int,
            username: null == username
                ? _value.username
                : username // ignore: cast_nullable_to_non_nullable
                      as String,
            email: freezed == email
                ? _value.email
                : email // ignore: cast_nullable_to_non_nullable
                      as String?,
            phone: freezed == phone
                ? _value.phone
                : phone // ignore: cast_nullable_to_non_nullable
                      as String?,
            isActive: null == isActive
                ? _value.isActive
                : isActive // ignore: cast_nullable_to_non_nullable
                      as bool,
            roleId: freezed == roleId
                ? _value.roleId
                : roleId // ignore: cast_nullable_to_non_nullable
                      as int?,
            branchId: freezed == branchId
                ? _value.branchId
                : branchId // ignore: cast_nullable_to_non_nullable
                      as int?,
            role: freezed == role
                ? _value.role
                : role // ignore: cast_nullable_to_non_nullable
                      as RoleDto?,
            branch: freezed == branch
                ? _value.branch
                : branch // ignore: cast_nullable_to_non_nullable
                      as BranchSummaryDto?,
            skillLevel: freezed == skillLevel
                ? _value.skillLevel
                : skillLevel // ignore: cast_nullable_to_non_nullable
                      as int?,
            directPermissions: null == directPermissions
                ? _value.directPermissions
                : directPermissions // ignore: cast_nullable_to_non_nullable
                      as List<PermissionDto>,
          )
          as $Val,
    );
  }

  /// Create a copy of UserResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $RoleDtoCopyWith<$Res>? get role {
    if (_value.role == null) {
      return null;
    }

    return $RoleDtoCopyWith<$Res>(_value.role!, (value) {
      return _then(_value.copyWith(role: value) as $Val);
    });
  }

  /// Create a copy of UserResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $BranchSummaryDtoCopyWith<$Res>? get branch {
    if (_value.branch == null) {
      return null;
    }

    return $BranchSummaryDtoCopyWith<$Res>(_value.branch!, (value) {
      return _then(_value.copyWith(branch: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$UserResponseDtoImplCopyWith<$Res>
    implements $UserResponseDtoCopyWith<$Res> {
  factory _$$UserResponseDtoImplCopyWith(
    _$UserResponseDtoImpl value,
    $Res Function(_$UserResponseDtoImpl) then,
  ) = __$$UserResponseDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int id,
    String username,
    String? email,
    String? phone,
    @JsonKey(name: 'is_active') bool isActive,
    @JsonKey(name: 'role_id') int? roleId,
    @JsonKey(name: 'branch_id') int? branchId,
    RoleDto? role,
    BranchSummaryDto? branch,
    @JsonKey(name: 'skill_level') int? skillLevel,
    @JsonKey(name: 'direct_permissions') List<PermissionDto> directPermissions,
  });

  @override
  $RoleDtoCopyWith<$Res>? get role;
  @override
  $BranchSummaryDtoCopyWith<$Res>? get branch;
}

/// @nodoc
class __$$UserResponseDtoImplCopyWithImpl<$Res>
    extends _$UserResponseDtoCopyWithImpl<$Res, _$UserResponseDtoImpl>
    implements _$$UserResponseDtoImplCopyWith<$Res> {
  __$$UserResponseDtoImplCopyWithImpl(
    _$UserResponseDtoImpl _value,
    $Res Function(_$UserResponseDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UserResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? username = null,
    Object? email = freezed,
    Object? phone = freezed,
    Object? isActive = null,
    Object? roleId = freezed,
    Object? branchId = freezed,
    Object? role = freezed,
    Object? branch = freezed,
    Object? skillLevel = freezed,
    Object? directPermissions = null,
  }) {
    return _then(
      _$UserResponseDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as int,
        username: null == username
            ? _value.username
            : username // ignore: cast_nullable_to_non_nullable
                  as String,
        email: freezed == email
            ? _value.email
            : email // ignore: cast_nullable_to_non_nullable
                  as String?,
        phone: freezed == phone
            ? _value.phone
            : phone // ignore: cast_nullable_to_non_nullable
                  as String?,
        isActive: null == isActive
            ? _value.isActive
            : isActive // ignore: cast_nullable_to_non_nullable
                  as bool,
        roleId: freezed == roleId
            ? _value.roleId
            : roleId // ignore: cast_nullable_to_non_nullable
                  as int?,
        branchId: freezed == branchId
            ? _value.branchId
            : branchId // ignore: cast_nullable_to_non_nullable
                  as int?,
        role: freezed == role
            ? _value.role
            : role // ignore: cast_nullable_to_non_nullable
                  as RoleDto?,
        branch: freezed == branch
            ? _value.branch
            : branch // ignore: cast_nullable_to_non_nullable
                  as BranchSummaryDto?,
        skillLevel: freezed == skillLevel
            ? _value.skillLevel
            : skillLevel // ignore: cast_nullable_to_non_nullable
                  as int?,
        directPermissions: null == directPermissions
            ? _value._directPermissions
            : directPermissions // ignore: cast_nullable_to_non_nullable
                  as List<PermissionDto>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$UserResponseDtoImpl implements _UserResponseDto {
  const _$UserResponseDtoImpl({
    required this.id,
    required this.username,
    this.email,
    this.phone,
    @JsonKey(name: 'is_active') this.isActive = true,
    @JsonKey(name: 'role_id') this.roleId,
    @JsonKey(name: 'branch_id') this.branchId,
    this.role,
    this.branch,
    @JsonKey(name: 'skill_level') this.skillLevel,
    @JsonKey(name: 'direct_permissions')
    final List<PermissionDto> directPermissions = const [],
  }) : _directPermissions = directPermissions;

  factory _$UserResponseDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$UserResponseDtoImplFromJson(json);

  @override
  final int id;
  @override
  final String username;
  @override
  final String? email;
  @override
  final String? phone;
  @override
  @JsonKey(name: 'is_active')
  final bool isActive;
  @override
  @JsonKey(name: 'role_id')
  final int? roleId;
  @override
  @JsonKey(name: 'branch_id')
  final int? branchId;
  @override
  final RoleDto? role;
  @override
  final BranchSummaryDto? branch;
  @override
  @JsonKey(name: 'skill_level')
  final int? skillLevel;
  final List<PermissionDto> _directPermissions;
  @override
  @JsonKey(name: 'direct_permissions')
  List<PermissionDto> get directPermissions {
    if (_directPermissions is EqualUnmodifiableListView)
      return _directPermissions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_directPermissions);
  }

  @override
  String toString() {
    return 'UserResponseDto(id: $id, username: $username, email: $email, phone: $phone, isActive: $isActive, roleId: $roleId, branchId: $branchId, role: $role, branch: $branch, skillLevel: $skillLevel, directPermissions: $directPermissions)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UserResponseDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.username, username) ||
                other.username == username) &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.phone, phone) || other.phone == phone) &&
            (identical(other.isActive, isActive) ||
                other.isActive == isActive) &&
            (identical(other.roleId, roleId) || other.roleId == roleId) &&
            (identical(other.branchId, branchId) ||
                other.branchId == branchId) &&
            (identical(other.role, role) || other.role == role) &&
            (identical(other.branch, branch) || other.branch == branch) &&
            (identical(other.skillLevel, skillLevel) ||
                other.skillLevel == skillLevel) &&
            const DeepCollectionEquality().equals(
              other._directPermissions,
              _directPermissions,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    username,
    email,
    phone,
    isActive,
    roleId,
    branchId,
    role,
    branch,
    skillLevel,
    const DeepCollectionEquality().hash(_directPermissions),
  );

  /// Create a copy of UserResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UserResponseDtoImplCopyWith<_$UserResponseDtoImpl> get copyWith =>
      __$$UserResponseDtoImplCopyWithImpl<_$UserResponseDtoImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$UserResponseDtoImplToJson(this);
  }
}

abstract class _UserResponseDto implements UserResponseDto {
  const factory _UserResponseDto({
    required final int id,
    required final String username,
    final String? email,
    final String? phone,
    @JsonKey(name: 'is_active') final bool isActive,
    @JsonKey(name: 'role_id') final int? roleId,
    @JsonKey(name: 'branch_id') final int? branchId,
    final RoleDto? role,
    final BranchSummaryDto? branch,
    @JsonKey(name: 'skill_level') final int? skillLevel,
    @JsonKey(name: 'direct_permissions')
    final List<PermissionDto> directPermissions,
  }) = _$UserResponseDtoImpl;

  factory _UserResponseDto.fromJson(Map<String, dynamic> json) =
      _$UserResponseDtoImpl.fromJson;

  @override
  int get id;
  @override
  String get username;
  @override
  String? get email;
  @override
  String? get phone;
  @override
  @JsonKey(name: 'is_active')
  bool get isActive;
  @override
  @JsonKey(name: 'role_id')
  int? get roleId;
  @override
  @JsonKey(name: 'branch_id')
  int? get branchId;
  @override
  RoleDto? get role;
  @override
  BranchSummaryDto? get branch;
  @override
  @JsonKey(name: 'skill_level')
  int? get skillLevel;
  @override
  @JsonKey(name: 'direct_permissions')
  List<PermissionDto> get directPermissions;

  /// Create a copy of UserResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UserResponseDtoImplCopyWith<_$UserResponseDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

LoginResponseDto _$LoginResponseDtoFromJson(Map<String, dynamic> json) {
  return _LoginResponseDto.fromJson(json);
}

/// @nodoc
mixin _$LoginResponseDto {
  @JsonKey(name: 'access_token')
  String get accessToken => throw _privateConstructorUsedError;
  @JsonKey(name: 'token_type')
  String get tokenType => throw _privateConstructorUsedError;
  UserResponseDto get user => throw _privateConstructorUsedError;
  @JsonKey(name: 'expires_at')
  String? get expiresAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'expires_in_minutes')
  int? get expiresInMinutes => throw _privateConstructorUsedError;

  /// Serializes this LoginResponseDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of LoginResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $LoginResponseDtoCopyWith<LoginResponseDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LoginResponseDtoCopyWith<$Res> {
  factory $LoginResponseDtoCopyWith(
    LoginResponseDto value,
    $Res Function(LoginResponseDto) then,
  ) = _$LoginResponseDtoCopyWithImpl<$Res, LoginResponseDto>;
  @useResult
  $Res call({
    @JsonKey(name: 'access_token') String accessToken,
    @JsonKey(name: 'token_type') String tokenType,
    UserResponseDto user,
    @JsonKey(name: 'expires_at') String? expiresAt,
    @JsonKey(name: 'expires_in_minutes') int? expiresInMinutes,
  });

  $UserResponseDtoCopyWith<$Res> get user;
}

/// @nodoc
class _$LoginResponseDtoCopyWithImpl<$Res, $Val extends LoginResponseDto>
    implements $LoginResponseDtoCopyWith<$Res> {
  _$LoginResponseDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of LoginResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? accessToken = null,
    Object? tokenType = null,
    Object? user = null,
    Object? expiresAt = freezed,
    Object? expiresInMinutes = freezed,
  }) {
    return _then(
      _value.copyWith(
            accessToken: null == accessToken
                ? _value.accessToken
                : accessToken // ignore: cast_nullable_to_non_nullable
                      as String,
            tokenType: null == tokenType
                ? _value.tokenType
                : tokenType // ignore: cast_nullable_to_non_nullable
                      as String,
            user: null == user
                ? _value.user
                : user // ignore: cast_nullable_to_non_nullable
                      as UserResponseDto,
            expiresAt: freezed == expiresAt
                ? _value.expiresAt
                : expiresAt // ignore: cast_nullable_to_non_nullable
                      as String?,
            expiresInMinutes: freezed == expiresInMinutes
                ? _value.expiresInMinutes
                : expiresInMinutes // ignore: cast_nullable_to_non_nullable
                      as int?,
          )
          as $Val,
    );
  }

  /// Create a copy of LoginResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $UserResponseDtoCopyWith<$Res> get user {
    return $UserResponseDtoCopyWith<$Res>(_value.user, (value) {
      return _then(_value.copyWith(user: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$LoginResponseDtoImplCopyWith<$Res>
    implements $LoginResponseDtoCopyWith<$Res> {
  factory _$$LoginResponseDtoImplCopyWith(
    _$LoginResponseDtoImpl value,
    $Res Function(_$LoginResponseDtoImpl) then,
  ) = __$$LoginResponseDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'access_token') String accessToken,
    @JsonKey(name: 'token_type') String tokenType,
    UserResponseDto user,
    @JsonKey(name: 'expires_at') String? expiresAt,
    @JsonKey(name: 'expires_in_minutes') int? expiresInMinutes,
  });

  @override
  $UserResponseDtoCopyWith<$Res> get user;
}

/// @nodoc
class __$$LoginResponseDtoImplCopyWithImpl<$Res>
    extends _$LoginResponseDtoCopyWithImpl<$Res, _$LoginResponseDtoImpl>
    implements _$$LoginResponseDtoImplCopyWith<$Res> {
  __$$LoginResponseDtoImplCopyWithImpl(
    _$LoginResponseDtoImpl _value,
    $Res Function(_$LoginResponseDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of LoginResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? accessToken = null,
    Object? tokenType = null,
    Object? user = null,
    Object? expiresAt = freezed,
    Object? expiresInMinutes = freezed,
  }) {
    return _then(
      _$LoginResponseDtoImpl(
        accessToken: null == accessToken
            ? _value.accessToken
            : accessToken // ignore: cast_nullable_to_non_nullable
                  as String,
        tokenType: null == tokenType
            ? _value.tokenType
            : tokenType // ignore: cast_nullable_to_non_nullable
                  as String,
        user: null == user
            ? _value.user
            : user // ignore: cast_nullable_to_non_nullable
                  as UserResponseDto,
        expiresAt: freezed == expiresAt
            ? _value.expiresAt
            : expiresAt // ignore: cast_nullable_to_non_nullable
                  as String?,
        expiresInMinutes: freezed == expiresInMinutes
            ? _value.expiresInMinutes
            : expiresInMinutes // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$LoginResponseDtoImpl implements _LoginResponseDto {
  const _$LoginResponseDtoImpl({
    @JsonKey(name: 'access_token') required this.accessToken,
    @JsonKey(name: 'token_type') this.tokenType = 'bearer',
    required this.user,
    @JsonKey(name: 'expires_at') this.expiresAt,
    @JsonKey(name: 'expires_in_minutes') this.expiresInMinutes,
  });

  factory _$LoginResponseDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$LoginResponseDtoImplFromJson(json);

  @override
  @JsonKey(name: 'access_token')
  final String accessToken;
  @override
  @JsonKey(name: 'token_type')
  final String tokenType;
  @override
  final UserResponseDto user;
  @override
  @JsonKey(name: 'expires_at')
  final String? expiresAt;
  @override
  @JsonKey(name: 'expires_in_minutes')
  final int? expiresInMinutes;

  @override
  String toString() {
    return 'LoginResponseDto(accessToken: $accessToken, tokenType: $tokenType, user: $user, expiresAt: $expiresAt, expiresInMinutes: $expiresInMinutes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LoginResponseDtoImpl &&
            (identical(other.accessToken, accessToken) ||
                other.accessToken == accessToken) &&
            (identical(other.tokenType, tokenType) ||
                other.tokenType == tokenType) &&
            (identical(other.user, user) || other.user == user) &&
            (identical(other.expiresAt, expiresAt) ||
                other.expiresAt == expiresAt) &&
            (identical(other.expiresInMinutes, expiresInMinutes) ||
                other.expiresInMinutes == expiresInMinutes));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    accessToken,
    tokenType,
    user,
    expiresAt,
    expiresInMinutes,
  );

  /// Create a copy of LoginResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$LoginResponseDtoImplCopyWith<_$LoginResponseDtoImpl> get copyWith =>
      __$$LoginResponseDtoImplCopyWithImpl<_$LoginResponseDtoImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$LoginResponseDtoImplToJson(this);
  }
}

abstract class _LoginResponseDto implements LoginResponseDto {
  const factory _LoginResponseDto({
    @JsonKey(name: 'access_token') required final String accessToken,
    @JsonKey(name: 'token_type') final String tokenType,
    required final UserResponseDto user,
    @JsonKey(name: 'expires_at') final String? expiresAt,
    @JsonKey(name: 'expires_in_minutes') final int? expiresInMinutes,
  }) = _$LoginResponseDtoImpl;

  factory _LoginResponseDto.fromJson(Map<String, dynamic> json) =
      _$LoginResponseDtoImpl.fromJson;

  @override
  @JsonKey(name: 'access_token')
  String get accessToken;
  @override
  @JsonKey(name: 'token_type')
  String get tokenType;
  @override
  UserResponseDto get user;
  @override
  @JsonKey(name: 'expires_at')
  String? get expiresAt;
  @override
  @JsonKey(name: 'expires_in_minutes')
  int? get expiresInMinutes;

  /// Create a copy of LoginResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$LoginResponseDtoImplCopyWith<_$LoginResponseDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
