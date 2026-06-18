// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'tracking_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

NamedRefDto _$NamedRefDtoFromJson(Map<String, dynamic> json) {
  return _NamedRefDto.fromJson(json);
}

/// @nodoc
mixin _$NamedRefDto {
  int get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;

  /// Serializes this NamedRefDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of NamedRefDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NamedRefDtoCopyWith<NamedRefDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NamedRefDtoCopyWith<$Res> {
  factory $NamedRefDtoCopyWith(
    NamedRefDto value,
    $Res Function(NamedRefDto) then,
  ) = _$NamedRefDtoCopyWithImpl<$Res, NamedRefDto>;
  @useResult
  $Res call({int id, String name});
}

/// @nodoc
class _$NamedRefDtoCopyWithImpl<$Res, $Val extends NamedRefDto>
    implements $NamedRefDtoCopyWith<$Res> {
  _$NamedRefDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of NamedRefDto
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
abstract class _$$NamedRefDtoImplCopyWith<$Res>
    implements $NamedRefDtoCopyWith<$Res> {
  factory _$$NamedRefDtoImplCopyWith(
    _$NamedRefDtoImpl value,
    $Res Function(_$NamedRefDtoImpl) then,
  ) = __$$NamedRefDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int id, String name});
}

/// @nodoc
class __$$NamedRefDtoImplCopyWithImpl<$Res>
    extends _$NamedRefDtoCopyWithImpl<$Res, _$NamedRefDtoImpl>
    implements _$$NamedRefDtoImplCopyWith<$Res> {
  __$$NamedRefDtoImplCopyWithImpl(
    _$NamedRefDtoImpl _value,
    $Res Function(_$NamedRefDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of NamedRefDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? id = null, Object? name = null}) {
    return _then(
      _$NamedRefDtoImpl(
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
class _$NamedRefDtoImpl implements _NamedRefDto {
  const _$NamedRefDtoImpl({required this.id, this.name = ''});

  factory _$NamedRefDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$NamedRefDtoImplFromJson(json);

  @override
  final int id;
  @override
  @JsonKey()
  final String name;

  @override
  String toString() {
    return 'NamedRefDto(id: $id, name: $name)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NamedRefDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name);

  /// Create a copy of NamedRefDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NamedRefDtoImplCopyWith<_$NamedRefDtoImpl> get copyWith =>
      __$$NamedRefDtoImplCopyWithImpl<_$NamedRefDtoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$NamedRefDtoImplToJson(this);
  }
}

abstract class _NamedRefDto implements NamedRefDto {
  const factory _NamedRefDto({required final int id, final String name}) =
      _$NamedRefDtoImpl;

  factory _NamedRefDto.fromJson(Map<String, dynamic> json) =
      _$NamedRefDtoImpl.fromJson;

  @override
  int get id;
  @override
  String get name;

  /// Create a copy of NamedRefDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NamedRefDtoImplCopyWith<_$NamedRefDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

TrackingDto _$TrackingDtoFromJson(Map<String, dynamic> json) {
  return _TrackingDto.fromJson(json);
}

/// @nodoc
mixin _$TrackingDto {
  int get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'last_application_date')
  String? get lastApplicationDate => throw _privateConstructorUsedError;
  @JsonKey(name: 'design_notes')
  String? get designNotes => throw _privateConstructorUsedError;
  @JsonKey(name: 'eye_type')
  NamedRefDto? get eyeType => throw _privateConstructorUsedError;
  NamedRefDto? get effect => throw _privateConstructorUsedError;
  NamedRefDto? get volume => throw _privateConstructorUsedError;
  @JsonKey(name: 'lash_design')
  NamedRefDto? get lashDesign => throw _privateConstructorUsedError;

  /// Serializes this TrackingDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TrackingDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TrackingDtoCopyWith<TrackingDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TrackingDtoCopyWith<$Res> {
  factory $TrackingDtoCopyWith(
    TrackingDto value,
    $Res Function(TrackingDto) then,
  ) = _$TrackingDtoCopyWithImpl<$Res, TrackingDto>;
  @useResult
  $Res call({
    int id,
    @JsonKey(name: 'last_application_date') String? lastApplicationDate,
    @JsonKey(name: 'design_notes') String? designNotes,
    @JsonKey(name: 'eye_type') NamedRefDto? eyeType,
    NamedRefDto? effect,
    NamedRefDto? volume,
    @JsonKey(name: 'lash_design') NamedRefDto? lashDesign,
  });

  $NamedRefDtoCopyWith<$Res>? get eyeType;
  $NamedRefDtoCopyWith<$Res>? get effect;
  $NamedRefDtoCopyWith<$Res>? get volume;
  $NamedRefDtoCopyWith<$Res>? get lashDesign;
}

/// @nodoc
class _$TrackingDtoCopyWithImpl<$Res, $Val extends TrackingDto>
    implements $TrackingDtoCopyWith<$Res> {
  _$TrackingDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TrackingDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? lastApplicationDate = freezed,
    Object? designNotes = freezed,
    Object? eyeType = freezed,
    Object? effect = freezed,
    Object? volume = freezed,
    Object? lashDesign = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as int,
            lastApplicationDate: freezed == lastApplicationDate
                ? _value.lastApplicationDate
                : lastApplicationDate // ignore: cast_nullable_to_non_nullable
                      as String?,
            designNotes: freezed == designNotes
                ? _value.designNotes
                : designNotes // ignore: cast_nullable_to_non_nullable
                      as String?,
            eyeType: freezed == eyeType
                ? _value.eyeType
                : eyeType // ignore: cast_nullable_to_non_nullable
                      as NamedRefDto?,
            effect: freezed == effect
                ? _value.effect
                : effect // ignore: cast_nullable_to_non_nullable
                      as NamedRefDto?,
            volume: freezed == volume
                ? _value.volume
                : volume // ignore: cast_nullable_to_non_nullable
                      as NamedRefDto?,
            lashDesign: freezed == lashDesign
                ? _value.lashDesign
                : lashDesign // ignore: cast_nullable_to_non_nullable
                      as NamedRefDto?,
          )
          as $Val,
    );
  }

  /// Create a copy of TrackingDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $NamedRefDtoCopyWith<$Res>? get eyeType {
    if (_value.eyeType == null) {
      return null;
    }

    return $NamedRefDtoCopyWith<$Res>(_value.eyeType!, (value) {
      return _then(_value.copyWith(eyeType: value) as $Val);
    });
  }

  /// Create a copy of TrackingDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $NamedRefDtoCopyWith<$Res>? get effect {
    if (_value.effect == null) {
      return null;
    }

    return $NamedRefDtoCopyWith<$Res>(_value.effect!, (value) {
      return _then(_value.copyWith(effect: value) as $Val);
    });
  }

  /// Create a copy of TrackingDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $NamedRefDtoCopyWith<$Res>? get volume {
    if (_value.volume == null) {
      return null;
    }

    return $NamedRefDtoCopyWith<$Res>(_value.volume!, (value) {
      return _then(_value.copyWith(volume: value) as $Val);
    });
  }

  /// Create a copy of TrackingDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $NamedRefDtoCopyWith<$Res>? get lashDesign {
    if (_value.lashDesign == null) {
      return null;
    }

    return $NamedRefDtoCopyWith<$Res>(_value.lashDesign!, (value) {
      return _then(_value.copyWith(lashDesign: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$TrackingDtoImplCopyWith<$Res>
    implements $TrackingDtoCopyWith<$Res> {
  factory _$$TrackingDtoImplCopyWith(
    _$TrackingDtoImpl value,
    $Res Function(_$TrackingDtoImpl) then,
  ) = __$$TrackingDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int id,
    @JsonKey(name: 'last_application_date') String? lastApplicationDate,
    @JsonKey(name: 'design_notes') String? designNotes,
    @JsonKey(name: 'eye_type') NamedRefDto? eyeType,
    NamedRefDto? effect,
    NamedRefDto? volume,
    @JsonKey(name: 'lash_design') NamedRefDto? lashDesign,
  });

  @override
  $NamedRefDtoCopyWith<$Res>? get eyeType;
  @override
  $NamedRefDtoCopyWith<$Res>? get effect;
  @override
  $NamedRefDtoCopyWith<$Res>? get volume;
  @override
  $NamedRefDtoCopyWith<$Res>? get lashDesign;
}

/// @nodoc
class __$$TrackingDtoImplCopyWithImpl<$Res>
    extends _$TrackingDtoCopyWithImpl<$Res, _$TrackingDtoImpl>
    implements _$$TrackingDtoImplCopyWith<$Res> {
  __$$TrackingDtoImplCopyWithImpl(
    _$TrackingDtoImpl _value,
    $Res Function(_$TrackingDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of TrackingDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? lastApplicationDate = freezed,
    Object? designNotes = freezed,
    Object? eyeType = freezed,
    Object? effect = freezed,
    Object? volume = freezed,
    Object? lashDesign = freezed,
  }) {
    return _then(
      _$TrackingDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as int,
        lastApplicationDate: freezed == lastApplicationDate
            ? _value.lastApplicationDate
            : lastApplicationDate // ignore: cast_nullable_to_non_nullable
                  as String?,
        designNotes: freezed == designNotes
            ? _value.designNotes
            : designNotes // ignore: cast_nullable_to_non_nullable
                  as String?,
        eyeType: freezed == eyeType
            ? _value.eyeType
            : eyeType // ignore: cast_nullable_to_non_nullable
                  as NamedRefDto?,
        effect: freezed == effect
            ? _value.effect
            : effect // ignore: cast_nullable_to_non_nullable
                  as NamedRefDto?,
        volume: freezed == volume
            ? _value.volume
            : volume // ignore: cast_nullable_to_non_nullable
                  as NamedRefDto?,
        lashDesign: freezed == lashDesign
            ? _value.lashDesign
            : lashDesign // ignore: cast_nullable_to_non_nullable
                  as NamedRefDto?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$TrackingDtoImpl implements _TrackingDto {
  const _$TrackingDtoImpl({
    required this.id,
    @JsonKey(name: 'last_application_date') this.lastApplicationDate,
    @JsonKey(name: 'design_notes') this.designNotes,
    @JsonKey(name: 'eye_type') this.eyeType,
    this.effect,
    this.volume,
    @JsonKey(name: 'lash_design') this.lashDesign,
  });

  factory _$TrackingDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$TrackingDtoImplFromJson(json);

  @override
  final int id;
  @override
  @JsonKey(name: 'last_application_date')
  final String? lastApplicationDate;
  @override
  @JsonKey(name: 'design_notes')
  final String? designNotes;
  @override
  @JsonKey(name: 'eye_type')
  final NamedRefDto? eyeType;
  @override
  final NamedRefDto? effect;
  @override
  final NamedRefDto? volume;
  @override
  @JsonKey(name: 'lash_design')
  final NamedRefDto? lashDesign;

  @override
  String toString() {
    return 'TrackingDto(id: $id, lastApplicationDate: $lastApplicationDate, designNotes: $designNotes, eyeType: $eyeType, effect: $effect, volume: $volume, lashDesign: $lashDesign)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TrackingDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.lastApplicationDate, lastApplicationDate) ||
                other.lastApplicationDate == lastApplicationDate) &&
            (identical(other.designNotes, designNotes) ||
                other.designNotes == designNotes) &&
            (identical(other.eyeType, eyeType) || other.eyeType == eyeType) &&
            (identical(other.effect, effect) || other.effect == effect) &&
            (identical(other.volume, volume) || other.volume == volume) &&
            (identical(other.lashDesign, lashDesign) ||
                other.lashDesign == lashDesign));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    lastApplicationDate,
    designNotes,
    eyeType,
    effect,
    volume,
    lashDesign,
  );

  /// Create a copy of TrackingDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TrackingDtoImplCopyWith<_$TrackingDtoImpl> get copyWith =>
      __$$TrackingDtoImplCopyWithImpl<_$TrackingDtoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TrackingDtoImplToJson(this);
  }
}

abstract class _TrackingDto implements TrackingDto {
  const factory _TrackingDto({
    required final int id,
    @JsonKey(name: 'last_application_date') final String? lastApplicationDate,
    @JsonKey(name: 'design_notes') final String? designNotes,
    @JsonKey(name: 'eye_type') final NamedRefDto? eyeType,
    final NamedRefDto? effect,
    final NamedRefDto? volume,
    @JsonKey(name: 'lash_design') final NamedRefDto? lashDesign,
  }) = _$TrackingDtoImpl;

  factory _TrackingDto.fromJson(Map<String, dynamic> json) =
      _$TrackingDtoImpl.fromJson;

  @override
  int get id;
  @override
  @JsonKey(name: 'last_application_date')
  String? get lastApplicationDate;
  @override
  @JsonKey(name: 'design_notes')
  String? get designNotes;
  @override
  @JsonKey(name: 'eye_type')
  NamedRefDto? get eyeType;
  @override
  NamedRefDto? get effect;
  @override
  NamedRefDto? get volume;
  @override
  @JsonKey(name: 'lash_design')
  NamedRefDto? get lashDesign;

  /// Create a copy of TrackingDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TrackingDtoImplCopyWith<_$TrackingDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
