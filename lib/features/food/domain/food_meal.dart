import 'package:equatable/equatable.dart';

/// A single logged meal with metadata and photo path.
class FoodMeal extends Equatable {
  const FoodMeal({
    required this.id,
    required this.dayKey,
    required this.capturedAtMs,
    required this.photoPath,
    this.name,
    this.note,
    this.kcal,
    this.slot,
  });

  final String id;
  final String dayKey; // YYYY-MM-DD in local time
  final int capturedAtMs; // Unix milliseconds
  final String photoPath; // Relative to app-support: food/meals/{dayKey}/{id}.jpg
  final String? name;
  final String? note;
  final double? kcal; // Manual entry only in v0; null = not provided
  final String? slot; // Optional: "breakfast", "lunch", "dinner", "snack"

  FoodMeal copyWith({
    String? id,
    String? dayKey,
    int? capturedAtMs,
    String? photoPath,
    String? name,
    String? note,
    double? kcal,
    String? slot,
  }) {
    return FoodMeal(
      id: id ?? this.id,
      dayKey: dayKey ?? this.dayKey,
      capturedAtMs: capturedAtMs ?? this.capturedAtMs,
      photoPath: photoPath ?? this.photoPath,
      name: name ?? this.name,
      note: note ?? this.note,
      kcal: kcal ?? this.kcal,
      slot: slot ?? this.slot,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dayKey': dayKey,
      'capturedAtMs': capturedAtMs,
      'photoPath': photoPath,
      if (name != null) 'name': name,
      if (note != null) 'note': note,
      if (kcal != null) 'kcal': kcal,
      if (slot != null) 'slot': slot,
    };
  }

  factory FoodMeal.fromJson(Map<String, dynamic> json) {
    return FoodMeal(
      id: json['id'] as String,
      dayKey: json['dayKey'] as String,
      capturedAtMs: json['capturedAtMs'] as int,
      photoPath: json['photoPath'] as String,
      name: json['name'] as String?,
      note: json['note'] as String?,
      kcal: json['kcal'] as double?,
      slot: json['slot'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        dayKey,
        capturedAtMs,
        photoPath,
        name,
        note,
        kcal,
        slot,
      ];
}
