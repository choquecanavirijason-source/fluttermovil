// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog_item_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

CatalogItemDto _$CatalogItemDtoFromJson(Map<String, dynamic> json) {
  return _CatalogItemDto.fromJson(json);
}

/// @nodoc
mixin _$CatalogItemDto {
  int get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  String? get image => throw _privateConstructorUsedError;
  @JsonKey(name: 'model_3d_url')
  String? get model3dUrl => throw _privateConstructorUsedError;
  @JsonKey(name: 'tipo_ojo_compatible')
  String? get tipoOjoCompatible => throw _privateConstructorUsedError;

  /// Serializes this CatalogItemDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of CatalogItemDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CatalogItemDtoCopyWith<CatalogItemDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CatalogItemDtoCopyWith<$Res> {
  factory $CatalogItemDtoCopyWith(
    CatalogItemDto value,
    $Res Function(CatalogItemDto) then,
  ) = _$CatalogItemDtoCopyWithImpl<$Res, CatalogItemDto>;
  @useResult
  $Res call({
    int id,
    String name,
    String? description,
    String? image,
    @JsonKey(name: 'model_3d_url') String? model3dUrl,
    @JsonKey(name: 'tipo_ojo_compatible') String? tipoOjoCompatible,
  });
}

/// @nodoc
class _$CatalogItemDtoCopyWithImpl<$Res, $Val extends CatalogItemDto>
    implements $CatalogItemDtoCopyWith<$Res> {
  _$CatalogItemDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CatalogItemDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? image = freezed,
    Object? model3dUrl = freezed,
    Object? tipoOjoCompatible = freezed,
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
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            image: freezed == image
                ? _value.image
                : image // ignore: cast_nullable_to_non_nullable
                      as String?,
            model3dUrl: freezed == model3dUrl
                ? _value.model3dUrl
                : model3dUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            tipoOjoCompatible: freezed == tipoOjoCompatible
                ? _value.tipoOjoCompatible
                : tipoOjoCompatible // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$CatalogItemDtoImplCopyWith<$Res>
    implements $CatalogItemDtoCopyWith<$Res> {
  factory _$$CatalogItemDtoImplCopyWith(
    _$CatalogItemDtoImpl value,
    $Res Function(_$CatalogItemDtoImpl) then,
  ) = __$$CatalogItemDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int id,
    String name,
    String? description,
    String? image,
    @JsonKey(name: 'model_3d_url') String? model3dUrl,
    @JsonKey(name: 'tipo_ojo_compatible') String? tipoOjoCompatible,
  });
}

/// @nodoc
class __$$CatalogItemDtoImplCopyWithImpl<$Res>
    extends _$CatalogItemDtoCopyWithImpl<$Res, _$CatalogItemDtoImpl>
    implements _$$CatalogItemDtoImplCopyWith<$Res> {
  __$$CatalogItemDtoImplCopyWithImpl(
    _$CatalogItemDtoImpl _value,
    $Res Function(_$CatalogItemDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of CatalogItemDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? image = freezed,
    Object? model3dUrl = freezed,
    Object? tipoOjoCompatible = freezed,
  }) {
    return _then(
      _$CatalogItemDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as int,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        image: freezed == image
            ? _value.image
            : image // ignore: cast_nullable_to_non_nullable
                  as String?,
        model3dUrl: freezed == model3dUrl
            ? _value.model3dUrl
            : model3dUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        tipoOjoCompatible: freezed == tipoOjoCompatible
            ? _value.tipoOjoCompatible
            : tipoOjoCompatible // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$CatalogItemDtoImpl implements _CatalogItemDto {
  const _$CatalogItemDtoImpl({
    required this.id,
    this.name = '',
    this.description,
    this.image,
    @JsonKey(name: 'model_3d_url') this.model3dUrl,
    @JsonKey(name: 'tipo_ojo_compatible') this.tipoOjoCompatible,
  });

  factory _$CatalogItemDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$CatalogItemDtoImplFromJson(json);

  @override
  final int id;
  @override
  @JsonKey()
  final String name;
  @override
  final String? description;
  @override
  final String? image;
  @override
  @JsonKey(name: 'model_3d_url')
  final String? model3dUrl;
  @override
  @JsonKey(name: 'tipo_ojo_compatible')
  final String? tipoOjoCompatible;

  @override
  String toString() {
    return 'CatalogItemDto(id: $id, name: $name, description: $description, image: $image, model3dUrl: $model3dUrl, tipoOjoCompatible: $tipoOjoCompatible)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CatalogItemDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.image, image) || other.image == image) &&
            (identical(other.model3dUrl, model3dUrl) ||
                other.model3dUrl == model3dUrl) &&
            (identical(other.tipoOjoCompatible, tipoOjoCompatible) ||
                other.tipoOjoCompatible == tipoOjoCompatible));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    name,
    description,
    image,
    model3dUrl,
    tipoOjoCompatible,
  );

  /// Create a copy of CatalogItemDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CatalogItemDtoImplCopyWith<_$CatalogItemDtoImpl> get copyWith =>
      __$$CatalogItemDtoImplCopyWithImpl<_$CatalogItemDtoImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$CatalogItemDtoImplToJson(this);
  }
}

abstract class _CatalogItemDto implements CatalogItemDto {
  const factory _CatalogItemDto({
    required final int id,
    final String name,
    final String? description,
    final String? image,
    @JsonKey(name: 'model_3d_url') final String? model3dUrl,
    @JsonKey(name: 'tipo_ojo_compatible') final String? tipoOjoCompatible,
  }) = _$CatalogItemDtoImpl;

  factory _CatalogItemDto.fromJson(Map<String, dynamic> json) =
      _$CatalogItemDtoImpl.fromJson;

  @override
  int get id;
  @override
  String get name;
  @override
  String? get description;
  @override
  String? get image;
  @override
  @JsonKey(name: 'model_3d_url')
  String? get model3dUrl;
  @override
  @JsonKey(name: 'tipo_ojo_compatible')
  String? get tipoOjoCompatible;

  /// Create a copy of CatalogItemDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CatalogItemDtoImplCopyWith<_$CatalogItemDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
