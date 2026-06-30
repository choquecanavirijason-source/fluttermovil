// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog_item_dto.freezed.dart';
part 'catalog_item_dto.g.dart';

@freezed
class CatalogItemDto with _$CatalogItemDto {
  const factory CatalogItemDto({
    required int id,
    @Default('') String name,
    String? description,
    String? image,
    @JsonKey(name: 'model_3d_url') String? model3dUrl,
    @JsonKey(name: 'tipo_ojo_compatible') String? tipoOjoCompatible,
  }) = _CatalogItemDto;

  factory CatalogItemDto.fromJson(Map<String, dynamic> json) =>
      _$CatalogItemDtoFromJson(json);
}
