import 'dart:convert';

import 'package:fitness_os/features/workout_history/data/qwen3_swim_reasoner.dart';
import 'package:fitness_os/features/workout_history/domain/swim_recommendations.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_analytics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildOnDeviceReasonerPrompt', () {
    test('stays compact vs full coach payload', () {
      const report = SwimDiagnosisReport(
        sessionDiagnoses: [
          SwimDiagnosis(
            id: 'efficiency_decline',
            title: 'Efficiency decline',
            summary:
                'SWOLF trending worse across sessions — emphasize easy technique '
                'and stroke count before chasing pace PRs.',
            confidence: SwimConfidence.high,
            metricIds: ['avgSwolf', 'swolfDelta'],
            evidence: 'avgSwolf up',
          ),
        ],
        trendDiagnoses: [
          SwimDiagnosis(
            id: 'trend_swolf_worse',
            title: 'SWOLF trend',
            summary: 'Worse across recent sessions.',
            confidence: SwimConfidence.high,
            metricIds: ['avgSwolf'],
            evidence: 'delta+',
          ),
        ],
        trends: SwimTrends(points: [], sessionCount: 2),
      );
      final recs = recommendationsForReport(report);
      final compact = jsonEncode(
        buildOnDeviceReasonerPrompt(
          report: report,
          recommendations: recs,
          workoutNumber: 1,
        ),
      );
      final full = jsonEncode(
        buildCoachPromptPayload(
          report: report,
          recommendations: recs,
          workoutNumber: 1,
        ),
      );
      expect(compact.length, lessThan(full.length));
      // Leave ample headroom inside a 2048-token context (~4 chars/token).
      expect(compact.length / 4, lessThan(600));
    });
  });

  group('Qwen3SwimReasoner.stripThinking', () {
    test('removes complete think blocks', () {
      const raw = '<think>\nrank by SWOLF\n</think>\n{"summary":"ok"}';
      expect(Qwen3SwimReasoner.stripThinking(raw), '{"summary":"ok"}');
    });

    test('removes truncated think blocks (no closing tag)', () {
      const raw = '<think>\nStill ranking recommendations…';
      expect(Qwen3SwimReasoner.stripThinking(raw), '');
    });
  });

  group('Qwen3SwimReasoner.extractJsonObject', () {
    test('extracts JSON after think block', () {
      const raw =
          '<think>plan</think>\n{"summary":"A","orderedRecIds":["r1"]}';
      expect(
        Qwen3SwimReasoner.extractJsonObject(raw),
        '{"summary":"A","orderedRecIds":["r1"]}',
      );
    });

    test('returns null when only truncated thinking remains', () {
      const raw = '<think>\nUnexpected character fodder';
      expect(Qwen3SwimReasoner.extractJsonObject(raw), isNull);
    });

    test('returns null when response has no JSON object', () {
      expect(Qwen3SwimReasoner.extractJsonObject('no braces here'), isNull);
    });
  });
}
