import 'dart:math';

/// Planned strength session (phone-side; watch only receives set notifications).
class PlannedExercise {
  PlannedExercise({
    required this.exerciseId,
    required this.name,
    required this.sets,
    required this.targetKg,
    required this.targetReps,
    required this.restSec,
  });

  final String exerciseId;
  final String name;
  final int sets;
  final double targetKg;
  final int targetReps;
  final int restSec;

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'name': name,
        'sets': sets,
        'targetKg': targetKg,
        'targetReps': targetReps,
        'restSec': restSec,
      };

  factory PlannedExercise.fromJson(Map<String, dynamic> json) => PlannedExercise(
        exerciseId: json['exerciseId'] as String,
        name: json['name'] as String,
        sets: json['sets'] as int,
        targetKg: (json['targetKg'] as num).toDouble(),
        targetReps: json['targetReps'] as int,
        restSec: json['restSec'] as int,
      );
}

class PlannedSession {
  PlannedSession({
    required this.sessionId,
    required this.title,
    required this.plannedFor,
    required this.exercises,
    required this.source,
  });

  final String sessionId;
  final String title;
  final DateTime plannedFor;
  final List<PlannedExercise> exercises;
  final String source;

  static String newSessionId() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
    final rnd = Random();
    final tail = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'ps_${y}${m}${d}_$tail';
  }

  List<PlannedSet> expand() {
    final out = <PlannedSet>[];
    var global = 0;
    for (final ex in exercises) {
      for (var i = 1; i <= ex.sets; i++) {
        global += 1;
        out.add(
          PlannedSet(
            exerciseId: ex.exerciseId,
            name: ex.name,
            setIndex: i,
            globalIndex: global,
            plannedKg: ex.targetKg,
            plannedReps: ex.targetReps,
            restSec: ex.restSec,
          ),
        );
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'title': title,
        'plannedFor': plannedFor.toIso8601String(),
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'source': source,
      };

  factory PlannedSession.fromJson(Map<String, dynamic> json) => PlannedSession(
        sessionId: json['sessionId'] as String,
        title: json['title'] as String,
        plannedFor: DateTime.parse(json['plannedFor'] as String),
        exercises: (json['exercises'] as List)
            .map((e) => PlannedExercise.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        source: json['source'] as String,
      );
}

class PlannedSet {
  const PlannedSet({
    required this.exerciseId,
    required this.name,
    required this.setIndex,
    required this.globalIndex,
    required this.plannedKg,
    required this.plannedReps,
    required this.restSec,
  });

  final String exerciseId;
  final String name;
  final int setIndex;
  final int globalIndex;
  final double plannedKg;
  final int plannedReps;
  final int restSec;

  String notificationKey(String sessionId) => 'lift:$sessionId:$globalIndex';
}