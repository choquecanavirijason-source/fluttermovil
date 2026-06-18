// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_closing_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DailyClosingItemDtoImpl _$$DailyClosingItemDtoImplFromJson(
  Map<String, dynamic> json,
) => _$DailyClosingItemDtoImpl(
  appointmentId: (json['appointment_id'] as num).toInt(),
  ticketCode: json['ticket_code'] as String?,
  clientName: json['client_name'] as String? ?? '',
  serviceNames:
      (json['service_names'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  professionalName: json['professional_name'] as String? ?? '',
  professionalId: (json['professional_id'] as num?)?.toInt(),
  startTime: json['start_time'] as String,
  status: json['status'] as String? ?? '',
  totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
  commissionRate: (json['commission_rate'] as num?)?.toDouble() ?? 0.0,
  commission: (json['commission'] as num?)?.toDouble() ?? 0.0,
  isPaid: json['is_paid'] as bool? ?? false,
);

Map<String, dynamic> _$$DailyClosingItemDtoImplToJson(
  _$DailyClosingItemDtoImpl instance,
) => <String, dynamic>{
  'appointment_id': instance.appointmentId,
  'ticket_code': instance.ticketCode,
  'client_name': instance.clientName,
  'service_names': instance.serviceNames,
  'professional_name': instance.professionalName,
  'professional_id': instance.professionalId,
  'start_time': instance.startTime,
  'status': instance.status,
  'total_price': instance.totalPrice,
  'commission_rate': instance.commissionRate,
  'commission': instance.commission,
  'is_paid': instance.isPaid,
};

_$ProfessionalSummaryDtoImpl _$$ProfessionalSummaryDtoImplFromJson(
  Map<String, dynamic> json,
) => _$ProfessionalSummaryDtoImpl(
  professionalId: (json['professional_id'] as num?)?.toInt(),
  professionalName: json['professional_name'] as String? ?? '',
  ticketCount: (json['ticket_count'] as num?)?.toInt() ?? 0,
  totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
  commission: (json['commission'] as num?)?.toDouble() ?? 0.0,
  commissionRate: (json['commission_rate'] as num?)?.toDouble() ?? 0.0,
);

Map<String, dynamic> _$$ProfessionalSummaryDtoImplToJson(
  _$ProfessionalSummaryDtoImpl instance,
) => <String, dynamic>{
  'professional_id': instance.professionalId,
  'professional_name': instance.professionalName,
  'ticket_count': instance.ticketCount,
  'total_price': instance.totalPrice,
  'commission': instance.commission,
  'commission_rate': instance.commissionRate,
};

_$DailyClosingResponseDtoImpl _$$DailyClosingResponseDtoImplFromJson(
  Map<String, dynamic> json,
) => _$DailyClosingResponseDtoImpl(
  date: json['date'] as String,
  items:
      (json['items'] as List<dynamic>?)
          ?.map((e) => DailyClosingItemDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
  grandCommission: (json['grand_commission'] as num?)?.toDouble() ?? 0.0,
  summaryByProfessional:
      (json['summary_by_professional'] as List<dynamic>?)
          ?.map(
            (e) => ProfessionalSummaryDto.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      const [],
);

Map<String, dynamic> _$$DailyClosingResponseDtoImplToJson(
  _$DailyClosingResponseDtoImpl instance,
) => <String, dynamic>{
  'date': instance.date,
  'items': instance.items,
  'grand_total': instance.grandTotal,
  'grand_commission': instance.grandCommission,
  'summary_by_professional': instance.summaryByProfessional,
};
