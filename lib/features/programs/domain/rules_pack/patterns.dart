import 'package:fitness_os/features/programs/domain/chore_session.dart';

/// Curated set pattern seed (Fathom notation — not vendor copy).
class SetPattern {
  const SetPattern({
    required this.id,
    required this.part,
    required this.label,
    required this.defaultRestSec,
    required this.effortBand,
    this.roles = const {},
  });

  final String id;

  /// `warmUp` | `main` | `coolDown` | `technique` | `pre`.
  final String part;
  final String label;
  final int defaultRestSec;
  final String effortBand;

  /// Session roles this pattern is preferred for (empty = any).
  final Set<ChoreRole> roles;
}

/// Minimum vocabulary for v1 session assembly (~pack §6.5 subset).
const List<SetPattern> rulesPackPatterns = [
  SetPattern(
    id: 'WU1',
    part: 'warmUp',
    label: 'Easy swim (free/choice)',
    defaultRestSec: 0,
    effortBand: 'E',
  ),
  SetPattern(
    id: 'WU3',
    part: 'warmUp',
    label: 'Build 100s',
    defaultRestSec: 15,
    effortBand: 'S',
    roles: {ChoreRole.quality, ChoreRole.proof},
  ),
  SetPattern(
    id: 'PRE1',
    part: 'pre',
    label: 'Activation 50s + build 25s',
    defaultRestSec: 20,
    effortBand: 'S',
    roles: {ChoreRole.proof, ChoreRole.guidedTest},
  ),
  SetPattern(
    id: 'AE2',
    part: 'main',
    label: 'Long-rep steady 300s (rest-shrink)',
    defaultRestSec: 15,
    effortBand: 'S',
    roles: {ChoreRole.endurance},
  ),
  SetPattern(
    id: 'AE3',
    part: 'main',
    label: 'Long-rep 400s steady→tempo',
    defaultRestSec: 20,
    effortBand: 'S',
    roles: {ChoreRole.endurance},
  ),
  SetPattern(
    id: 'AE6',
    part: 'main',
    label: 'Rest-shrink 100s ladder',
    defaultRestSec: 15,
    effortBand: 'S',
    roles: {ChoreRole.endurance, ChoreRole.proof},
  ),
  SetPattern(
    id: 'CS1',
    part: 'main',
    label: 'CSS / threshold 100s',
    defaultRestSec: 15,
    effortBand: 'C',
    roles: {ChoreRole.quality},
  ),
  SetPattern(
    id: 'CS3',
    part: 'main',
    label: 'Goal-pace broken reps',
    defaultRestSec: 20,
    effortBand: 'T',
    roles: {ChoreRole.quality},
  ),
  SetPattern(
    id: 'TK1',
    part: 'main',
    label: 'Drill/swim 50s (one cue)',
    defaultRestSec: 12,
    effortBand: 'E',
    roles: {ChoreRole.technique},
  ),
  SetPattern(
    id: 'TK2',
    part: 'main',
    label: 'Pull + swim rhythm',
    defaultRestSec: 15,
    effortBand: 'S',
    roles: {ChoreRole.technique, ChoreRole.easy},
  ),
  SetPattern(
    id: 'RC1',
    part: 'main',
    label: 'Easy continuous / 100s',
    defaultRestSec: 10,
    effortBand: 'E',
    roles: {ChoreRole.recovery, ChoreRole.easy},
  ),
  SetPattern(
    id: 'PRF1',
    part: 'main',
    label: 'Continuous capacity proof',
    defaultRestSec: 0,
    effortBand: 'S',
    roles: {ChoreRole.proof},
  ),
  SetPattern(
    id: 'CD1',
    part: 'coolDown',
    label: 'Easy any stroke',
    defaultRestSec: 0,
    effortBand: 'E',
  ),
];

SetPattern patternById(String id) {
  return rulesPackPatterns.firstWhere(
    (p) => p.id == id,
    orElse: () => rulesPackPatterns.first,
  );
}

/// Pick a main-set pattern for [role] (deterministic first match).
SetPattern mainPatternFor(ChoreRole role) {
  for (final p in rulesPackPatterns) {
    if (p.part != 'main') continue;
    if (p.roles.contains(role)) return p;
  }
  return patternById('AE2');
}

/// Warm-up pattern: quality/proof get build WU; others WU1.
SetPattern warmUpPatternFor(ChoreRole role) {
  if (role == ChoreRole.quality || role == ChoreRole.proof) {
    return patternById('WU3');
  }
  return patternById('WU1');
}
