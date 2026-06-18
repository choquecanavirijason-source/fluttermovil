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
  }) = _CatalogItemDto;

  factory CatalogItemDto.fromJson(Map<String, dynamic> json) =>
      _$CatalogItemDtoFromJson(json);
}
