// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_item_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CatalogItemDtoImpl _$$CatalogItemDtoImplFromJson(Map<String, dynamic> json) =>
    _$CatalogItemDtoImpl(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      image: json['image'] as String?,
    );

Map<String, dynamic> _$$CatalogItemDtoImplToJson(
  _$CatalogItemDtoImpl instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'image': instance.image,
};
