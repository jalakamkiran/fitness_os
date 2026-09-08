import 'dart:convert';

/// Meal schedule configuration.
class FoodScheduleConfig {
  FoodScheduleConfig({
    this.breakfastTime = const TimeOfDayData(hour: 8, minute: 0),
    this.lunchTime = const TimeOfDayData(hour: 12, minute: 30),
    this.dinnerTime = const TimeOfDayData(hour: 19, minute: 0),
    this.snackTimes = const [],
    this.leadMinutes = 15,
    this.enabledSlots = const {'breakfast', 'lunch', 'dinner'},
  });

  final TimeOfDayData breakfastTime;
  final TimeOfDayData lunchTime;
  final TimeOfDayData dinnerTime;
  final List<TimeOfDayData> snackTimes;
  final int leadMinutes; // minutes before meal time to notify
  final Set<String> enabledSlots;

  Map<String, dynamic> toJson() => {
        'breakfastTime': breakfastTime.toJson(),
        'lunchTime': lunchTime.toJson(),
        'dinnerTime': dinnerTime.toJson(),
        'snackTimes': snackTimes.map((t) => t.toJson()).toList(),
        'leadMinutes': leadMinutes,
        'enabledSlots': enabledSlots.toList(),
      };

  factory FoodScheduleConfig.fromJson(Map<String, dynamic> json) {
    return FoodScheduleConfig(
      breakfastTime: TimeOfDayData.fromJson(json['breakfastTime'] as Map<String, dynamic>),
      lunchTime: TimeOfDayData.fromJson(json['lunchTime'] as Map<String, dynamic>),
      dinnerTime: TimeOfDayData.fromJson(json['dinnerTime'] as Map<String, dynamic>),
      snackTimes: (json['snackTimes'] as List?)
              ?.map((t) => TimeOfDayData.fromJson(t as Map<String, dynamic>))
              .toList() ??
          const [],
      leadMinutes: json['leadMinutes'] as int? ?? 15,
      enabledSlots: (json['enabledSlots'] as List?)?.cast<String>().toSet() ??
          const {'breakfast', 'lunch', 'dinner'},
    );
  }

  FoodScheduleConfig copyWith({
    TimeOfDayData? breakfastTime,
    TimeOfDayData? lunchTime,
    TimeOfDayData? dinnerTime,
    List<TimeOfDayData>? snackTimes,
    int? leadMinutes,
    Set<String>? enabledSlots,
  }) {
    return FoodScheduleConfig(
      breakfastTime: breakfastTime ?? this.breakfastTime,
      lunchTime: lunchTime ?? this.lunchTime,
      dinnerTime: dinnerTime ?? this.dinnerTime,
      snackTimes: snackTimes ?? this.snackTimes,
      leadMinutes: leadMinutes ?? this.leadMinutes,
      enabledSlots: enabledSlots ?? this.enabledSlots,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static FoodScheduleConfig fromJsonString(String json) =>
      FoodScheduleConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

/// Serializable TimeOfDay.
class TimeOfDayData {
  const TimeOfDayData({required this.hour, required this.minute});

  final int hour; // 0-23
  final int minute; // 0-59

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  factory TimeOfDayData.fromJson(Map<String, dynamic> json) =>
      TimeOfDayData(hour: json['hour'] as int, minute: json['minute'] as int);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeOfDayData &&
          runtimeType == other.runtimeType &&
          hour == other.hour &&
          minute == other.minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}
