// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'client_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

ClientDto _$ClientDtoFromJson(Map<String, dynamic> json) {
  return _ClientDto.fromJson(json);
}

/// @nodoc
mixin _$ClientDto {
  int get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  @JsonKey(name: 'last_name')
  String? get lastName => throw _privateConstructorUsedError;
  String? get phone => throw _privateConstructorUsedError;
  String? get email => throw _privateConstructorUsedError;
  String? get status => throw _privateConstructorUsedError;

  /// Serializes this ClientDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ClientDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ClientDtoCopyWith<ClientDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ClientDtoCopyWith<$Res> {
  factory $ClientDtoCopyWith(ClientDto value, $Res Function(ClientDto) then) =
      _$ClientDtoCopyWithImpl<$Res, ClientDto>;
  @useResult
  $Res call({
    int id,
    String name,
    @JsonKey(name: 'last_name') String? lastName,
    String? phone,
    String? email,
    String? status,
  });
}

/// @nodoc
class _$ClientDtoCopyWithImpl<$Res, $Val extends ClientDto>
    implements $ClientDtoCopyWith<$Res> {
  _$ClientDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ClientDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? lastName = freezed,
    Object? phone = freezed,
    Object? email = freezed,
    Object? status = freezed,
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
            lastName: freezed == lastName
                ? _value.lastName
                : lastName // ignore: cast_nullable_to_non_nullable
                      as String?,
            phone: freezed == phone
                ? _value.phone
                : phone // ignore: cast_nullable_to_non_nullable
                      as String?,
            email: freezed == email
                ? _value.email
                : email // ignore: cast_nullable_to_non_nullable
                      as String?,
            status: freezed == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ClientDtoImplCopyWith<$Res>
    implements $ClientDtoCopyWith<$Res> {
  factory _$$ClientDtoImplCopyWith(
    _$ClientDtoImpl value,
    $Res Function(_$ClientDtoImpl) then,
  ) = __$$ClientDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int id,
    String name,
    @JsonKey(name: 'last_name') String? lastName,
    String? phone,
    String? email,
    String? status,
  });
}

/// @nodoc
class __$$ClientDtoImplCopyWithImpl<$Res>
    extends _$ClientDtoCopyWithImpl<$Res, _$ClientDtoImpl>
    implements _$$ClientDtoImplCopyWith<$Res> {
  __$$ClientDtoImplCopyWithImpl(
    _$ClientDtoImpl _value,
    $Res Function(_$ClientDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ClientDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? lastName = freezed,
    Object? phone = freezed,
    Object? email = freezed,
    Object? status = freezed,
  }) {
    return _then(
      _$ClientDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as int,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        lastName: freezed == lastName
            ? _value.lastName
            : lastName // ignore: cast_nullable_to_non_nullable
                  as String?,
        phone: freezed == phone
            ? _value.phone
            : phone // ignore: cast_nullable_to_non_nullable
                  as String?,
        email: freezed == email
            ? _value.email
            : email // ignore: cast_nullable_to_non_nullable
                  as String?,
        status: freezed == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ClientDtoImpl implements _ClientDto {
  const _$ClientDtoImpl({
    required this.id,
    this.name = '',
    @JsonKey(name: 'last_name') this.lastName,
    this.phone,
    this.email,
    this.status,
  });

  factory _$ClientDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$ClientDtoImplFromJson(json);

  @override
  final int id;
  @override
  @JsonKey()
  final String name;
  @override
  @JsonKey(name: 'last_name')
  final String? lastName;
  @override
  final String? phone;
  @override
  final String? email;
  @override
  final String? status;

  @override
  String toString() {
    return 'ClientDto(id: $id, name: $name, lastName: $lastName, phone: $phone, email: $email, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ClientDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.lastName, lastName) ||
                other.lastName == lastName) &&
            (identical(other.phone, phone) || other.phone == phone) &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.status, status) || other.status == status));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, name, lastName, phone, email, status);

  /// Create a copy of ClientDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ClientDtoImplCopyWith<_$ClientDtoImpl> get copyWith =>
      __$$ClientDtoImplCopyWithImpl<_$ClientDtoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ClientDtoImplToJson(this);
  }
}

abstract class _ClientDto implements ClientDto {
  const factory _ClientDto({
    required final int id,
    final String name,
    @JsonKey(name: 'last_name') final String? lastName,
    final String? phone,
    final String? email,
    final String? status,
  }) = _$ClientDtoImpl;

  factory _ClientDto.fromJson(Map<String, dynamic> json) =
      _$ClientDtoImpl.fromJson;

  @override
  int get id;
  @override
  String get name;
  @override
  @JsonKey(name: 'last_name')
  String? get lastName;
  @override
  String? get phone;
  @override
  String? get email;
  @override
  String? get status;

  /// Create a copy of ClientDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ClientDtoImplCopyWith<_$ClientDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
