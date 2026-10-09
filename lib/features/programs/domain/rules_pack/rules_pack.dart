/// Fathom-owned Programs rules pack metadata.
///
/// Provenance and change notes: `docs/architecture/programs-rules-pack.md`.
library;

export 'package:fitness_os/features/programs/domain/rules_pack/formulas.dart';
export 'package:fitness_os/features/programs/domain/rules_pack/patterns.dart';

/// Semver stamped onto every generated [Program.rulesPackVersion].
const String rulesPackVersion = '1.0.0';

/// Short human label for UI / diagnostics.
const String rulesPackLabel = 'Fathom pool-swim Rules Pack v1';

/// Authoring note (not athlete-facing).
const String rulesPackAuthoredBy = 'Fathom Programs';
