import 'dart:convert';

import 'package:fitness_os/features/workout_history/domain/offline_swim_reasoner.dart';
import 'package:fitness_os/features/workout_history/domain/swim_recommendations.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// On-device Qwen3 0.6B reasoner (LiteRT-LM).
class Qwen3SwimReasoner {
  static const modelFilename = 'qwen3_0_6b_mixed_int4.litertlm';
  static const modelUrl =
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3_0_6b_mixed_int4.litertlm';

  double? downloadProgress;
  String? lastError;

  Future<bool> isInstalled() async {
    try {
      return await FlutterGemma.isModelInstalled(modelFilename);
    } catch (e) {
      lastError = '$e';
      return false;
    }
  }

  /// Download ~586MB model. [onProgress] 0–100.
  Future<bool> ensureInstalled({void Function(double progress)? onProgress}) async {
    try {
      if (await isInstalled()) return true;
      downloadProgress = 0;
      await FlutterGemma.installModel(
        modelType: ModelType.qwen3,
        fileType: ModelFileType.litertlm,
      )
          .fromNetwork(modelUrl, foreground: true)
          .withProgress((p) {
            downloadProgress = p.toDouble();
            onProgress?.call(p.toDouble());
          })
          .install();
      downloadProgress = 100;
      return await isInstalled();
    } catch (e) {
      lastError = '$e';
      return false;
    }
  }

  Future<SwimReasonerResult> reason({
    required SwimDiagnosisReport report,
    required List<SwimRecommendation> recommendations,
    required int workoutNumber,
  }) async {
    if (recommendations.isEmpty) {
      return const SwimReasonerResult(
        ok: false,
        source: 'qwen3',
        error: 'No allow-listed recommendations.',
      );
    }
    if (!await isInstalled()) {
      return const SwimReasonerResult(
        ok: false,
        source: 'qwen3',
        error: 'Qwen3 not installed — download in Reasoner settings.',
      );
    }

    final payload = buildCoachPromptPayload(
      report: report,
      recommendations: recommendations,
      workoutNumber: workoutNumber,
    );
    // Reasoning-focused instructions (not voice coach).
    payload['instructions'] =
        'You are a swim performance reasoner. Rank the given recommendations '
        'by what will most improve the athlete next session. '
        'Never invent metrics, diagnoses, or recommendation ids. '
        'Return JSON only: '
        '{"summary": string, "orderedRecIds": string[], '
        '"rationaleByRecId": {id: string}, "notes": string}. '
        'orderedRecIds MUST be a subset of allowedRecIds.';

    InferenceModel? model;
    try {
      model = await FlutterGemma.getActiveModel(
        maxTokens: 1024,
        preferredBackend: PreferredBackend.gpu,
      );
      final chat = await model.createChat(
        systemInstruction:
            'Reason about swimming training priorities. Output valid JSON only.',
        isThinking: true,
      );
      await chat.addQueryChunk(
        Message.text(text: jsonEncode(payload), isUser: true),
      );
      final response = await chat.generateChatResponse();
      final text = switch (response) {
        TextResponse(:final token) => token,
        ThinkingResponse(:final content) => content,
        _ => response.toString(),
      };
      if (text.trim().isEmpty) {
        return const SwimReasonerResult(
          ok: false,
          source: 'qwen3',
          error: 'Empty Qwen3 response.',
        );
      }
      final jsonText = _extractJsonObject(text);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        return const SwimReasonerResult(
          ok: false,
          source: 'qwen3',
          error: 'Qwen3 returned non-JSON object.',
        );
      }
      final map = Map<String, dynamic>.from(decoded);
      final allowed = recommendations.map((r) => r.id).toSet();
      final ordered = filterCoachOrderedIds(
        map['orderedRecIds'] as List<dynamic>?,
        allowed,
      );
      final finalOrder = ordered.isNotEmpty
          ? ordered
          : recommendations.map((r) => r.id).toList();

      final rationaleRaw = map['rationaleByRecId'];
      final rationale = <String, String>{};
      if (rationaleRaw is Map) {
        rationaleRaw.forEach((k, v) {
          if (k is String && allowed.contains(k) && v != null) {
            rationale[k] = '$v';
          }
        });
      }

      return SwimReasonerResult(
        ok: true,
        source: 'qwen3',
        summary: map['summary'] as String? ?? '',
        orderedRecIds: finalOrder,
        rationaleByRecId: rationale,
        notes: map['notes'] as String?,
      );
    } catch (e) {
      lastError = '$e';
      return SwimReasonerResult(
        ok: false,
        source: 'qwen3',
        error: 'Qwen3 reason failed: $e',
      );
    } finally {
      try {
        await model?.close();
      } catch (_) {}
    }
  }

  String _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) return text.substring(start, end + 1);
    return text;
  }
}
