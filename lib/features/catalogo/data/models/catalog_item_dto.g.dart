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
      model3dUrl: json['model_3d_url'] as String?,
      tipoOjoCompatible: json['tipo_ojo_compatible'] as String?,
    );

Map<String, dynamic> _$$CatalogItemDtoImplToJson(
  _$CatalogItemDtoImpl instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'image': instance.image,
  'model_3d_url': instance.model3dUrl,
  'tipo_ojo_compatible': instance.tipoOjoCompatible,
};
