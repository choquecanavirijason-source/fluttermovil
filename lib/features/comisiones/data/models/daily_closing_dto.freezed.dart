// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'daily_closing_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

DailyClosingItemDto _$DailyClosingItemDtoFromJson(Map<String, dynamic> json) {
  return _DailyClosingItemDto.fromJson(json);
}

/// @nodoc
mixin _$DailyClosingItemDto {
  @JsonKey(name: 'appointment_id')
  int get appointmentId => throw _privateConstructorUsedError;
  @JsonKey(name: 'ticket_code')
  String? get ticketCode => throw _privateConstructorUsedError;
  @JsonKey(name: 'client_name')
  String get clientName => throw _privateConstructorUsedError;
  @JsonKey(name: 'service_names')
  List<String> get serviceNames => throw _privateConstructorUsedError;
  @JsonKey(name: 'professional_name')
  String get professionalName => throw _privateConstructorUsedError;
  @JsonKey(name: 'professional_id')
  int? get professionalId => throw _privateConstructorUsedError;
  @JsonKey(name: 'start_time')
  String get startTime => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_price')
  double get totalPrice => throw _privateConstructorUsedError;
  @JsonKey(name: 'commission_rate')
  double get commissionRate => throw _privateConstructorUsedError;
  double get commission => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_paid')
  bool get isPaid => throw _privateConstructorUsedError;

  /// Serializes this DailyClosingItemDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DailyClosingItemDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DailyClosingItemDtoCopyWith<DailyClosingItemDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DailyClosingItemDtoCopyWith<$Res> {
  factory $DailyClosingItemDtoCopyWith(
    DailyClosingItemDto value,
    $Res Function(DailyClosingItemDto) then,
  ) = _$DailyClosingItemDtoCopyWithImpl<$Res, DailyClosingItemDto>;
  @useResult
  $Res call({
    @JsonKey(name: 'appointment_id') int appointmentId,
    @JsonKey(name: 'ticket_code') String? ticketCode,
    @JsonKey(name: 'client_name') String clientName,
    @JsonKey(name: 'service_names') List<String> serviceNames,
    @JsonKey(name: 'professional_name') String professionalName,
    @JsonKey(name: 'professional_id') int? professionalId,
    @JsonKey(name: 'start_time') String startTime,
    String status,
    @JsonKey(name: 'total_price') double totalPrice,
    @JsonKey(name: 'commission_rate') double commissionRate,
    double commission,
    @JsonKey(name: 'is_paid') bool isPaid,
  });
}

/// @nodoc
class _$DailyClosingItemDtoCopyWithImpl<$Res, $Val extends DailyClosingItemDto>
    implements $DailyClosingItemDtoCopyWith<$Res> {
  _$DailyClosingItemDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DailyClosingItemDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? appointmentId = null,
    Object? ticketCode = freezed,
    Object? clientName = null,
    Object? serviceNames = null,
    Object? professionalName = null,
    Object? professionalId = freezed,
    Object? startTime = null,
    Object? status = null,
    Object? totalPrice = null,
    Object? commissionRate = null,
    Object? commission = null,
    Object? isPaid = null,
  }) {
    return _then(
      _value.copyWith(
            appointmentId: null == appointmentId
                ? _value.appointmentId
                : appointmentId // ignore: cast_nullable_to_non_nullable
                      as int,
            ticketCode: freezed == ticketCode
                ? _value.ticketCode
                : ticketCode // ignore: cast_nullable_to_non_nullable
                      as String?,
            clientName: null == clientName
                ? _value.clientName
                : clientName // ignore: cast_nullable_to_non_nullable
                      as String,
            serviceNames: null == serviceNames
                ? _value.serviceNames
                : serviceNames // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            professionalName: null == professionalName
                ? _value.professionalName
                : professionalName // ignore: cast_nullable_to_non_nullable
                      as String,
            professionalId: freezed == professionalId
                ? _value.professionalId
                : professionalId // ignore: cast_nullable_to_non_nullable
                      as int?,
            startTime: null == startTime
                ? _value.startTime
                : startTime // ignore: cast_nullable_to_non_nullable
                      as String,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String,
            totalPrice: null == totalPrice
                ? _value.totalPrice
                : totalPrice // ignore: cast_nullable_to_non_nullable
                      as double,
            commissionRate: null == commissionRate
                ? _value.commissionRate
                : commissionRate // ignore: cast_nullable_to_non_nullable
                      as double,
            commission: null == commission
                ? _value.commission
                : commission // ignore: cast_nullable_to_non_nullable
                      as double,
            isPaid: null == isPaid
                ? _value.isPaid
                : isPaid // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$DailyClosingItemDtoImplCopyWith<$Res>
    implements $DailyClosingItemDtoCopyWith<$Res> {
  factory _$$DailyClosingItemDtoImplCopyWith(
    _$DailyClosingItemDtoImpl value,
    $Res Function(_$DailyClosingItemDtoImpl) then,
  ) = __$$DailyClosingItemDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'appointment_id') int appointmentId,
    @JsonKey(name: 'ticket_code') String? ticketCode,
    @JsonKey(name: 'client_name') String clientName,
    @JsonKey(name: 'service_names') List<String> serviceNames,
    @JsonKey(name: 'professional_name') String professionalName,
    @JsonKey(name: 'professional_id') int? professionalId,
    @JsonKey(name: 'start_time') String startTime,
    String status,
    @JsonKey(name: 'total_price') double totalPrice,
    @JsonKey(name: 'commission_rate') double commissionRate,
    double commission,
    @JsonKey(name: 'is_paid') bool isPaid,
  });
}

/// @nodoc
class __$$DailyClosingItemDtoImplCopyWithImpl<$Res>
    extends _$DailyClosingItemDtoCopyWithImpl<$Res, _$DailyClosingItemDtoImpl>
    implements _$$DailyClosingItemDtoImplCopyWith<$Res> {
  __$$DailyClosingItemDtoImplCopyWithImpl(
    _$DailyClosingItemDtoImpl _value,
    $Res Function(_$DailyClosingItemDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of DailyClosingItemDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? appointmentId = null,
    Object? ticketCode = freezed,
    Object? clientName = null,
    Object? serviceNames = null,
    Object? professionalName = null,
    Object? professionalId = freezed,
    Object? startTime = null,
    Object? status = null,
    Object? totalPrice = null,
    Object? commissionRate = null,
    Object? commission = null,
    Object? isPaid = null,
  }) {
    return _then(
      _$DailyClosingItemDtoImpl(
        appointmentId: null == appointmentId
            ? _value.appointmentId
            : appointmentId // ignore: cast_nullable_to_non_nullable
                  as int,
        ticketCode: freezed == ticketCode
            ? _value.ticketCode
            : ticketCode // ignore: cast_nullable_to_non_nullable
                  as String?,
        clientName: null == clientName
            ? _value.clientName
            : clientName // ignore: cast_nullable_to_non_nullable
                  as String,
        serviceNames: null == serviceNames
            ? _value._serviceNames
            : serviceNames // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        professionalName: null == professionalName
            ? _value.professionalName
            : professionalName // ignore: cast_nullable_to_non_nullable
                  as String,
        professionalId: freezed == professionalId
            ? _value.professionalId
            : professionalId // ignore: cast_nullable_to_non_nullable
                  as int?,
        startTime: null == startTime
            ? _value.startTime
            : startTime // ignore: cast_nullable_to_non_nullable
                  as String,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String,
        totalPrice: null == totalPrice
            ? _value.totalPrice
            : totalPrice // ignore: cast_nullable_to_non_nullable
                  as double,
        commissionRate: null == commissionRate
            ? _value.commissionRate
            : commissionRate // ignore: cast_nullable_to_non_nullable
                  as double,
        commission: null == commission
            ? _value.commission
            : commission // ignore: cast_nullable_to_non_nullable
                  as double,
        isPaid: null == isPaid
            ? _value.isPaid
            : isPaid // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$DailyClosingItemDtoImpl implements _DailyClosingItemDto {
  const _$DailyClosingItemDtoImpl({
    @JsonKey(name: 'appointment_id') required this.appointmentId,
    @JsonKey(name: 'ticket_code') this.ticketCode,
    @JsonKey(name: 'client_name') this.clientName = '',
    @JsonKey(name: 'service_names') final List<String> serviceNames = const [],
    @JsonKey(name: 'professional_name') this.professionalName = '',
    @JsonKey(name: 'professional_id') this.professionalId,
    @JsonKey(name: 'start_time') required this.startTime,
    this.status = '',
    @JsonKey(name: 'total_price') this.totalPrice = 0.0,
    @JsonKey(name: 'commission_rate') this.commissionRate = 0.0,
    this.commission = 0.0,
    @JsonKey(name: 'is_paid') this.isPaid = false,
  }) : _serviceNames = serviceNames;

  factory _$DailyClosingItemDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$DailyClosingItemDtoImplFromJson(json);

  @override
  @JsonKey(name: 'appointment_id')
  final int appointmentId;
  @override
  @JsonKey(name: 'ticket_code')
  final String? ticketCode;
  @override
  @JsonKey(name: 'client_name')
  final String clientName;
  final List<String> _serviceNames;
  @override
  @JsonKey(name: 'service_names')
  List<String> get serviceNames {
    if (_serviceNames is EqualUnmodifiableListView) return _serviceNames;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_serviceNames);
  }

  @override
  @JsonKey(name: 'professional_name')
  final String professionalName;
  @override
  @JsonKey(name: 'professional_id')
  final int? professionalId;
  @override
  @JsonKey(name: 'start_time')
  final String startTime;
  @override
  @JsonKey()
  final String status;
  @override
  @JsonKey(name: 'total_price')
  final double totalPrice;
  @override
  @JsonKey(name: 'commission_rate')
  final double commissionRate;
  @override
  @JsonKey()
  final double commission;
  @override
  @JsonKey(name: 'is_paid')
  final bool isPaid;

  @override
  String toString() {
    return 'DailyClosingItemDto(appointmentId: $appointmentId, ticketCode: $ticketCode, clientName: $clientName, serviceNames: $serviceNames, professionalName: $professionalName, professionalId: $professionalId, startTime: $startTime, status: $status, totalPrice: $totalPrice, commissionRate: $commissionRate, commission: $commission, isPaid: $isPaid)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DailyClosingItemDtoImpl &&
            (identical(other.appointmentId, appointmentId) ||
                other.appointmentId == appointmentId) &&
            (identical(other.ticketCode, ticketCode) ||
                other.ticketCode == ticketCode) &&
            (identical(other.clientName, clientName) ||
                other.clientName == clientName) &&
            const DeepCollectionEquality().equals(
              other._serviceNames,
              _serviceNames,
            ) &&
            (identical(other.professionalName, professionalName) ||
                other.professionalName == professionalName) &&
            (identical(other.professionalId, professionalId) ||
                other.professionalId == professionalId) &&
            (identical(other.startTime, startTime) ||
                other.startTime == startTime) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.totalPrice, totalPrice) ||
                other.totalPrice == totalPrice) &&
            (identical(other.commissionRate, commissionRate) ||
                other.commissionRate == commissionRate) &&
            (identical(other.commission, commission) ||
                other.commission == commission) &&
            (identical(other.isPaid, isPaid) || other.isPaid == isPaid));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    appointmentId,
    ticketCode,
    clientName,
    const DeepCollectionEquality().hash(_serviceNames),
    professionalName,
    professionalId,
    startTime,
    status,
    totalPrice,
    commissionRate,
    commission,
    isPaid,
  );

  /// Create a copy of DailyClosingItemDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DailyClosingItemDtoImplCopyWith<_$DailyClosingItemDtoImpl> get copyWith =>
      __$$DailyClosingItemDtoImplCopyWithImpl<_$DailyClosingItemDtoImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$DailyClosingItemDtoImplToJson(this);
  }
}

abstract class _DailyClosingItemDto implements DailyClosingItemDto {
  const factory _DailyClosingItemDto({
    @JsonKey(name: 'appointment_id') required final int appointmentId,
    @JsonKey(name: 'ticket_code') final String? ticketCode,
    @JsonKey(name: 'client_name') final String clientName,
    @JsonKey(name: 'service_names') final List<String> serviceNames,
    @JsonKey(name: 'professional_name') final String professionalName,
    @JsonKey(name: 'professional_id') final int? professionalId,
    @JsonKey(name: 'start_time') required final String startTime,
    final String status,
    @JsonKey(name: 'total_price') final double totalPrice,
    @JsonKey(name: 'commission_rate') final double commissionRate,
    final double commission,
    @JsonKey(name: 'is_paid') final bool isPaid,
  }) = _$DailyClosingItemDtoImpl;

  factory _DailyClosingItemDto.fromJson(Map<String, dynamic> json) =
      _$DailyClosingItemDtoImpl.fromJson;

  @override
  @JsonKey(name: 'appointment_id')
  int get appointmentId;
  @override
  @JsonKey(name: 'ticket_code')
  String? get ticketCode;
  @override
  @JsonKey(name: 'client_name')
  String get clientName;
  @override
  @JsonKey(name: 'service_names')
  List<String> get serviceNames;
  @override
  @JsonKey(name: 'professional_name')
  String get professionalName;
  @override
  @JsonKey(name: 'professional_id')
  int? get professionalId;
  @override
  @JsonKey(name: 'start_time')
  String get startTime;
  @override
  String get status;
  @override
  @JsonKey(name: 'total_price')
  double get totalPrice;
  @override
  @JsonKey(name: 'commission_rate')
  double get commissionRate;
  @override
  double get commission;
  @override
  @JsonKey(name: 'is_paid')
  bool get isPaid;

  /// Create a copy of DailyClosingItemDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DailyClosingItemDtoImplCopyWith<_$DailyClosingItemDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ProfessionalSummaryDto _$ProfessionalSummaryDtoFromJson(
  Map<String, dynamic> json,
) {
  return _ProfessionalSummaryDto.fromJson(json);
}

/// @nodoc
mixin _$ProfessionalSummaryDto {
  @JsonKey(name: 'professional_id')
  int? get professionalId => throw _privateConstructorUsedError;
  @JsonKey(name: 'professional_name')
  String get professionalName => throw _privateConstructorUsedError;
  @JsonKey(name: 'ticket_count')
  int get ticketCount => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_price')
  double get totalPrice => throw _privateConstructorUsedError;
  double get commission => throw _privateConstructorUsedError;
  @JsonKey(name: 'commission_rate')
  double get commissionRate => throw _privateConstructorUsedError;

  /// Serializes this ProfessionalSummaryDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ProfessionalSummaryDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ProfessionalSummaryDtoCopyWith<ProfessionalSummaryDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ProfessionalSummaryDtoCopyWith<$Res> {
  factory $ProfessionalSummaryDtoCopyWith(
    ProfessionalSummaryDto value,
    $Res Function(ProfessionalSummaryDto) then,
  ) = _$ProfessionalSummaryDtoCopyWithImpl<$Res, ProfessionalSummaryDto>;
  @useResult
  $Res call({
    @JsonKey(name: 'professional_id') int? professionalId,
    @JsonKey(name: 'professional_name') String professionalName,
    @JsonKey(name: 'ticket_count') int ticketCount,
    @JsonKey(name: 'total_price') double totalPrice,
    double commission,
    @JsonKey(name: 'commission_rate') double commissionRate,
  });
}

/// @nodoc
class _$ProfessionalSummaryDtoCopyWithImpl<
  $Res,
  $Val extends ProfessionalSummaryDto
>
    implements $ProfessionalSummaryDtoCopyWith<$Res> {
  _$ProfessionalSummaryDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ProfessionalSummaryDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? professionalId = freezed,
    Object? professionalName = null,
    Object? ticketCount = null,
    Object? totalPrice = null,
    Object? commission = null,
    Object? commissionRate = null,
  }) {
    return _then(
      _value.copyWith(
            professionalId: freezed == professionalId
                ? _value.professionalId
                : professionalId // ignore: cast_nullable_to_non_nullable
                      as int?,
            professionalName: null == professionalName
                ? _value.professionalName
                : professionalName // ignore: cast_nullable_to_non_nullable
                      as String,
            ticketCount: null == ticketCount
                ? _value.ticketCount
                : ticketCount // ignore: cast_nullable_to_non_nullable
                      as int,
            totalPrice: null == totalPrice
                ? _value.totalPrice
                : totalPrice // ignore: cast_nullable_to_non_nullable
                      as double,
            commission: null == commission
                ? _value.commission
                : commission // ignore: cast_nullable_to_non_nullable
                      as double,
            commissionRate: null == commissionRate
                ? _value.commissionRate
                : commissionRate // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ProfessionalSummaryDtoImplCopyWith<$Res>
    implements $ProfessionalSummaryDtoCopyWith<$Res> {
  factory _$$ProfessionalSummaryDtoImplCopyWith(
    _$ProfessionalSummaryDtoImpl value,
    $Res Function(_$ProfessionalSummaryDtoImpl) then,
  ) = __$$ProfessionalSummaryDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'professional_id') int? professionalId,
    @JsonKey(name: 'professional_name') String professionalName,
    @JsonKey(name: 'ticket_count') int ticketCount,
    @JsonKey(name: 'total_price') double totalPrice,
    double commission,
    @JsonKey(name: 'commission_rate') double commissionRate,
  });
}

/// @nodoc
class __$$ProfessionalSummaryDtoImplCopyWithImpl<$Res>
    extends
        _$ProfessionalSummaryDtoCopyWithImpl<$Res, _$ProfessionalSummaryDtoImpl>
    implements _$$ProfessionalSummaryDtoImplCopyWith<$Res> {
  __$$ProfessionalSummaryDtoImplCopyWithImpl(
    _$ProfessionalSummaryDtoImpl _value,
    $Res Function(_$ProfessionalSummaryDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ProfessionalSummaryDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? professionalId = freezed,
    Object? professionalName = null,
    Object? ticketCount = null,
    Object? totalPrice = null,
    Object? commission = null,
    Object? commissionRate = null,
  }) {
    return _then(
      _$ProfessionalSummaryDtoImpl(
        professionalId: freezed == professionalId
            ? _value.professionalId
            : professionalId // ignore: cast_nullable_to_non_nullable
                  as int?,
        professionalName: null == professionalName
            ? _value.professionalName
            : professionalName // ignore: cast_nullable_to_non_nullable
                  as String,
        ticketCount: null == ticketCount
            ? _value.ticketCount
            : ticketCount // ignore: cast_nullable_to_non_nullable
                  as int,
        totalPrice: null == totalPrice
            ? _value.totalPrice
            : totalPrice // ignore: cast_nullable_to_non_nullable
                  as double,
        commission: null == commission
            ? _value.commission
            : commission // ignore: cast_nullable_to_non_nullable
                  as double,
        commissionRate: null == commissionRate
            ? _value.commissionRate
            : commissionRate // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ProfessionalSummaryDtoImpl implements _ProfessionalSummaryDto {
  const _$ProfessionalSummaryDtoImpl({
    @JsonKey(name: 'professional_id') this.professionalId,
    @JsonKey(name: 'professional_name') this.professionalName = '',
    @JsonKey(name: 'ticket_count') this.ticketCount = 0,
    @JsonKey(name: 'total_price') this.totalPrice = 0.0,
    this.commission = 0.0,
    @JsonKey(name: 'commission_rate') this.commissionRate = 0.0,
  });

  factory _$ProfessionalSummaryDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$ProfessionalSummaryDtoImplFromJson(json);

  @override
  @JsonKey(name: 'professional_id')
  final int? professionalId;
  @override
  @JsonKey(name: 'professional_name')
  final String professionalName;
  @override
  @JsonKey(name: 'ticket_count')
  final int ticketCount;
  @override
  @JsonKey(name: 'total_price')
  final double totalPrice;
  @override
  @JsonKey()
  final double commission;
  @override
  @JsonKey(name: 'commission_rate')
  final double commissionRate;

  @override
  String toString() {
    return 'ProfessionalSummaryDto(professionalId: $professionalId, professionalName: $professionalName, ticketCount: $ticketCount, totalPrice: $totalPrice, commission: $commission, commissionRate: $commissionRate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ProfessionalSummaryDtoImpl &&
            (identical(other.professionalId, professionalId) ||
                other.professionalId == professionalId) &&
            (identical(other.professionalName, professionalName) ||
                other.professionalName == professionalName) &&
            (identical(other.ticketCount, ticketCount) ||
                other.ticketCount == ticketCount) &&
            (identical(other.totalPrice, totalPrice) ||
                other.totalPrice == totalPrice) &&
            (identical(other.commission, commission) ||
                other.commission == commission) &&
            (identical(other.commissionRate, commissionRate) ||
                other.commissionRate == commissionRate));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    professionalId,
    professionalName,
    ticketCount,
    totalPrice,
    commission,
    commissionRate,
  );

  /// Create a copy of ProfessionalSummaryDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ProfessionalSummaryDtoImplCopyWith<_$ProfessionalSummaryDtoImpl>
  get copyWith =>
      __$$ProfessionalSummaryDtoImplCopyWithImpl<_$ProfessionalSummaryDtoImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$ProfessionalSummaryDtoImplToJson(this);
  }
}

abstract class _ProfessionalSummaryDto implements ProfessionalSummaryDto {
  const factory _ProfessionalSummaryDto({
    @JsonKey(name: 'professional_id') final int? professionalId,
    @JsonKey(name: 'professional_name') final String professionalName,
    @JsonKey(name: 'ticket_count') final int ticketCount,
    @JsonKey(name: 'total_price') final double totalPrice,
    final double commission,
    @JsonKey(name: 'commission_rate') final double commissionRate,
  }) = _$ProfessionalSummaryDtoImpl;

  factory _ProfessionalSummaryDto.fromJson(Map<String, dynamic> json) =
      _$ProfessionalSummaryDtoImpl.fromJson;

  @override
  @JsonKey(name: 'professional_id')
  int? get professionalId;
  @override
  @JsonKey(name: 'professional_name')
  String get professionalName;
  @override
  @JsonKey(name: 'ticket_count')
  int get ticketCount;
  @override
  @JsonKey(name: 'total_price')
  double get totalPrice;
  @override
  double get commission;
  @override
  @JsonKey(name: 'commission_rate')
  double get commissionRate;

  /// Create a copy of ProfessionalSummaryDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ProfessionalSummaryDtoImplCopyWith<_$ProfessionalSummaryDtoImpl>
  get copyWith => throw _privateConstructorUsedError;
}

DailyClosingResponseDto _$DailyClosingResponseDtoFromJson(
  Map<String, dynamic> json,
) {
  return _DailyClosingResponseDto.fromJson(json);
}

/// @nodoc
mixin _$DailyClosingResponseDto {
  String get date => throw _privateConstructorUsedError;
  List<DailyClosingItemDto> get items => throw _privateConstructorUsedError;
  @JsonKey(name: 'grand_total')
  double get grandTotal => throw _privateConstructorUsedError;
  @JsonKey(name: 'grand_commission')
  double get grandCommission => throw _privateConstructorUsedError;
  @JsonKey(name: 'summary_by_professional')
  List<ProfessionalSummaryDto> get summaryByProfessional =>
      throw _privateConstructorUsedError;

  /// Serializes this DailyClosingResponseDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DailyClosingResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DailyClosingResponseDtoCopyWith<DailyClosingResponseDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DailyClosingResponseDtoCopyWith<$Res> {
  factory $DailyClosingResponseDtoCopyWith(
    DailyClosingResponseDto value,
    $Res Function(DailyClosingResponseDto) then,
  ) = _$DailyClosingResponseDtoCopyWithImpl<$Res, DailyClosingResponseDto>;
  @useResult
  $Res call({
    String date,
    List<DailyClosingItemDto> items,
    @JsonKey(name: 'grand_total') double grandTotal,
    @JsonKey(name: 'grand_commission') double grandCommission,
    @JsonKey(name: 'summary_by_professional')
    List<ProfessionalSummaryDto> summaryByProfessional,
  });
}

/// @nodoc
class _$DailyClosingResponseDtoCopyWithImpl<
  $Res,
  $Val extends DailyClosingResponseDto
>
    implements $DailyClosingResponseDtoCopyWith<$Res> {
  _$DailyClosingResponseDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DailyClosingResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? date = null,
    Object? items = null,
    Object? grandTotal = null,
    Object? grandCommission = null,
    Object? summaryByProfessional = null,
  }) {
    return _then(
      _value.copyWith(
            date: null == date
                ? _value.date
                : date // ignore: cast_nullable_to_non_nullable
                      as String,
            items: null == items
                ? _value.items
                : items // ignore: cast_nullable_to_non_nullable
                      as List<DailyClosingItemDto>,
            grandTotal: null == grandTotal
                ? _value.grandTotal
                : grandTotal // ignore: cast_nullable_to_non_nullable
                      as double,
            grandCommission: null == grandCommission
                ? _value.grandCommission
                : grandCommission // ignore: cast_nullable_to_non_nullable
                      as double,
            summaryByProfessional: null == summaryByProfessional
                ? _value.summaryByProfessional
                : summaryByProfessional // ignore: cast_nullable_to_non_nullable
                      as List<ProfessionalSummaryDto>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$DailyClosingResponseDtoImplCopyWith<$Res>
    implements $DailyClosingResponseDtoCopyWith<$Res> {
  factory _$$DailyClosingResponseDtoImplCopyWith(
    _$DailyClosingResponseDtoImpl value,
    $Res Function(_$DailyClosingResponseDtoImpl) then,
  ) = __$$DailyClosingResponseDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String date,
    List<DailyClosingItemDto> items,
    @JsonKey(name: 'grand_total') double grandTotal,
    @JsonKey(name: 'grand_commission') double grandCommission,
    @JsonKey(name: 'summary_by_professional')
    List<ProfessionalSummaryDto> summaryByProfessional,
  });
}

/// @nodoc
class __$$DailyClosingResponseDtoImplCopyWithImpl<$Res>
    extends
        _$DailyClosingResponseDtoCopyWithImpl<
          $Res,
          _$DailyClosingResponseDtoImpl
        >
    implements _$$DailyClosingResponseDtoImplCopyWith<$Res> {
  __$$DailyClosingResponseDtoImplCopyWithImpl(
    _$DailyClosingResponseDtoImpl _value,
    $Res Function(_$DailyClosingResponseDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of DailyClosingResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? date = null,
    Object? items = null,
    Object? grandTotal = null,
    Object? grandCommission = null,
    Object? summaryByProfessional = null,
  }) {
    return _then(
      _$DailyClosingResponseDtoImpl(
        date: null == date
            ? _value.date
            : date // ignore: cast_nullable_to_non_nullable
                  as String,
        items: null == items
            ? _value._items
            : items // ignore: cast_nullable_to_non_nullable
                  as List<DailyClosingItemDto>,
        grandTotal: null == grandTotal
            ? _value.grandTotal
            : grandTotal // ignore: cast_nullable_to_non_nullable
                  as double,
        grandCommission: null == grandCommission
            ? _value.grandCommission
            : grandCommission // ignore: cast_nullable_to_non_nullable
                  as double,
        summaryByProfessional: null == summaryByProfessional
            ? _value._summaryByProfessional
            : summaryByProfessional // ignore: cast_nullable_to_non_nullable
                  as List<ProfessionalSummaryDto>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$DailyClosingResponseDtoImpl implements _DailyClosingResponseDto {
  const _$DailyClosingResponseDtoImpl({
    required this.date,
    final List<DailyClosingItemDto> items = const [],
    @JsonKey(name: 'grand_total') this.grandTotal = 0.0,
    @JsonKey(name: 'grand_commission') this.grandCommission = 0.0,
    @JsonKey(name: 'summary_by_professional')
    final List<ProfessionalSummaryDto> summaryByProfessional = const [],
  }) : _items = items,
       _summaryByProfessional = summaryByProfessional;

  factory _$DailyClosingResponseDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$DailyClosingResponseDtoImplFromJson(json);

  @override
  final String date;
  final List<DailyClosingItemDto> _items;
  @override
  @JsonKey()
  List<DailyClosingItemDto> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  @JsonKey(name: 'grand_total')
  final double grandTotal;
  @override
  @JsonKey(name: 'grand_commission')
  final double grandCommission;
  final List<ProfessionalSummaryDto> _summaryByProfessional;
  @override
  @JsonKey(name: 'summary_by_professional')
  List<ProfessionalSummaryDto> get summaryByProfessional {
    if (_summaryByProfessional is EqualUnmodifiableListView)
      return _summaryByProfessional;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_summaryByProfessional);
  }

  @override
  String toString() {
    return 'DailyClosingResponseDto(date: $date, items: $items, grandTotal: $grandTotal, grandCommission: $grandCommission, summaryByProfessional: $summaryByProfessional)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DailyClosingResponseDtoImpl &&
            (identical(other.date, date) || other.date == date) &&
            const DeepCollectionEquality().equals(other._items, _items) &&
            (identical(other.grandTotal, grandTotal) ||
                other.grandTotal == grandTotal) &&
            (identical(other.grandCommission, grandCommission) ||
                other.grandCommission == grandCommission) &&
            const DeepCollectionEquality().equals(
              other._summaryByProfessional,
              _summaryByProfessional,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    date,
    const DeepCollectionEquality().hash(_items),
    grandTotal,
    grandCommission,
    const DeepCollectionEquality().hash(_summaryByProfessional),
  );

  /// Create a copy of DailyClosingResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DailyClosingResponseDtoImplCopyWith<_$DailyClosingResponseDtoImpl>
  get copyWith =>
      __$$DailyClosingResponseDtoImplCopyWithImpl<
        _$DailyClosingResponseDtoImpl
      >(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DailyClosingResponseDtoImplToJson(this);
  }
}

abstract class _DailyClosingResponseDto implements DailyClosingResponseDto {
  const factory _DailyClosingResponseDto({
    required final String date,
    final List<DailyClosingItemDto> items,
    @JsonKey(name: 'grand_total') final double grandTotal,
    @JsonKey(name: 'grand_commission') final double grandCommission,
    @JsonKey(name: 'summary_by_professional')
    final List<ProfessionalSummaryDto> summaryByProfessional,
  }) = _$DailyClosingResponseDtoImpl;

  factory _DailyClosingResponseDto.fromJson(Map<String, dynamic> json) =
      _$DailyClosingResponseDtoImpl.fromJson;

  @override
  String get date;
  @override
  List<DailyClosingItemDto> get items;
  @override
  @JsonKey(name: 'grand_total')
  double get grandTotal;
  @override
  @JsonKey(name: 'grand_commission')
  double get grandCommission;
  @override
  @JsonKey(name: 'summary_by_professional')
  List<ProfessionalSummaryDto> get summaryByProfessional;

  /// Create a copy of DailyClosingResponseDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DailyClosingResponseDtoImplCopyWith<_$DailyClosingResponseDtoImpl>
  get copyWith => throw _privateConstructorUsedError;
}
