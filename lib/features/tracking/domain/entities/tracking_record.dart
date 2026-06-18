import '../../data/models/tracking_dto.dart';

/// Un registro de seguimiento (aplicación) de un cliente.
class TrackingRecord {
  const TrackingRecord({
    required this.id,
    this.date,
    this.eyeType,
    this.effect,
    this.volume,
    this.lashDesign,
    this.notes,
  });

  final int id;
  final DateTime? date;
  final String? eyeType;
  final String? effect;
  final String? volume;
  final String? lashDesign;
  final String? notes;

  static String? _name(NamedRefDto? r) {
    final n = r?.name.trim();
    return (n != null && n.isNotEmpty) ? n : null;
  }

  factory TrackingRecord.fromDto(TrackingDto d) {
    DateTime? date;
    if (d.lastApplicationDate != null) {
      date = DateTime.tryParse(d.lastApplicationDate!)?.toLocal();
    }
    final notes = d.designNotes?.trim();
    return TrackingRecord(
      id: d.id,
      date: date,
      eyeType: _name(d.eyeType),
      effect: _name(d.effect),
      volume: _name(d.volume),
      lashDesign: _name(d.lashDesign),
      notes: (notes != null && notes.isNotEmpty) ? notes : null,
    );
  }
}
