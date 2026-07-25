import 'dart:convert';

import 'package:fitness_os/features/workout_history/domain/offline_swim_reasoner.dart';
import 'package:fitness_os/features/workout_history/domain/swim_recommendations.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// On-device Qwen3 0.6B reasoner (LiteRT-LM).
class Qwen3SwimReasoner {
  static const modelFilename = 'qwen3_0_6b_mixed_int4.litertlm';
  static const modelUrl =
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3_0_6b_mixed_int4.litertlm';

  /// LiteRT `maxTokens` is the full context window (prompt + reply), not
  /// reply length. 1024 left ~100 tokens after our coach payload and the
  /// native CancelProcess truncated mid-JSON. 2048 matches model metadata.
  static const int contextTokens = 2048;

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

    final payload = buildOnDeviceReasonerPrompt(
      report: report,
      recommendations: recommendations,
      workoutNumber: workoutNumber,
    );

    InferenceModel? model;
    try {
      // Prefer CPU: LiteRT GPU/WebGPU (libLiteRtGpuAccelerator) SIGSEGVs on
      // Pixel 8a (Mali-G715) during litert_lm_engine_create. Native SEGV
      // bypasses Dart catch and the library's GPU→CPU fallback never runs.
      model = await FlutterGemma.getActiveModel(
        maxTokens: contextTokens,
        preferredBackend: PreferredBackend.cpu,
      );
      // isThinking:false appends /no_think for Qwen3. Cool sampling for JSON.
      final chat = await model.createChat(
        temperature: 0.2,
        topK: 1,
        topP: 0.9,
        systemInstruction:
            'Swim reasoner. Reply with one JSON object only. No <think> blocks.',
        isThinking: false,
      );
      final userText = jsonEncode(payload);
      debugPrint(
        'Qwen3SwimReasoner: promptChars=${userText.length} '
        '~tokens=${(userText.length / 4).ceil()} context=$contextTokens',
      );
      await chat.addQueryChunk(Message.text(text: userText, isUser: true));
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
      final jsonText = extractJsonObject(text);
      if (jsonText == null) {
        debugPrint(
          'Qwen3SwimReasoner: no JSON in response '
          '(${text.length} chars): ${_preview(text)}',
        );
        return SwimReasonerResult(
          ok: false,
          source: 'qwen3',
          error: 'Qwen3 returned no JSON object '
              '(got ${_preview(text)}).',
        );
      }
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

  static String _preview(String text, [int max = 160]) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= max) return oneLine;
    return '${oneLine.substring(0, max - 1)}…';
  }

  /// Strips complete and truncated Qwen3/DeepSeek think blocks.
  @visibleForTesting
  static String stripThinking(String text) {
    var cleaned =
        text.replaceAll(RegExp(r'<think>[\s\S]*?</think>', multiLine: true), '');
    // Truncated mid-think (common when cancelled / maxTokens hit).
    cleaned = cleaned.replaceAll(RegExp(r'<think>[\s\S]*$', multiLine: true), '');
    return cleaned.trim();
  }

  /// Returns the outermost JSON object, or null if none.
  @visibleForTesting
  static String? extractJsonObject(String text) {
    final cleaned = stripThinking(text);
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) return cleaned.substring(start, end + 1);
    return null;
  }
}
