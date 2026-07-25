import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/domain/swim_recommendations.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GeminiCoachResult {
  const GeminiCoachResult({
    required this.ok,
    this.summary,
    this.orderedRecIds = const [],
    this.notes,
    this.error,
  });

  final bool ok;
  final String? summary;
  final List<String> orderedRecIds;
  final String? notes;
  final String? error;
}

/// Device-local Gemini key + generateContent coach call.
class GeminiCoachClient {
  GeminiCoachClient({
    required SharedPreferences prefs,
    Dio? dio,
    this.model = 'gemini-2.0-flash',
  })  : _prefs = prefs,
        _dio = dio ?? Dio();

  final SharedPreferences _prefs;
  final Dio _dio;
  final String model;

  static const _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  String? get apiKey {
    final raw = _prefs.getString(GateAPrefs.geminiApiKey);
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool get hasApiKey => apiKey != null;

  Future<void> saveApiKey(String key) async {
    await _prefs.setString(GateAPrefs.geminiApiKey, key.trim());
  }

  Future<void> clearApiKey() async {
    await _prefs.remove(GateAPrefs.geminiApiKey);
  }

  /// Explain/prioritize only. Never invents recs outside [recommendations].
  Future<GeminiCoachResult> explain({
    required SwimDiagnosisReport report,
    required List<SwimRecommendation> recommendations,
    required int workoutNumber,
  }) async {
    final key = apiKey;
    if (key == null) {
      return const GeminiCoachResult(
        ok: false,
        error: 'No Gemini API key — add one in Coach settings.',
      );
    }
    if (recommendations.isEmpty) {
      return const GeminiCoachResult(
        ok: false,
        error: 'No allow-listed recommendations for this session.',
      );
    }

    final payload = buildCoachPromptPayload(
      report: report,
      recommendations: recommendations,
      workoutNumber: workoutNumber,
    );
    final prompt = jsonEncode(payload);

    try {
      final url = '$_base/$model:generateContent';
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        queryParameters: {'key': key},
        data: {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.2,
            'responseMimeType': 'application/json',
          },
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      final text = _extractText(response.data);
      if (text == null || text.isEmpty) {
        return const GeminiCoachResult(
          ok: false,
          error: 'Empty response from Gemini.',
        );
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return const GeminiCoachResult(
          ok: false,
          error: 'Coach returned non-JSON object.',
        );
      }
      final map = Map<String, dynamic>.from(decoded);
      final allowed = recommendations.map((r) => r.id).toSet();
      final ordered = filterCoachOrderedIds(
        map['orderedRecIds'] as List<dynamic>?,
        allowed,
      );
      // If model omitted order, keep catalog order.
      final finalOrder =
          ordered.isNotEmpty ? ordered : recommendations.map((r) => r.id).toList();

      return GeminiCoachResult(
        ok: true,
        summary: map['summary'] as String? ?? '',
        orderedRecIds: finalOrder,
        notes: map['notes'] as String?,
      );
    } on DioException catch (e) {
      final msg = e.response?.data?.toString() ?? e.message ?? 'Network error';
      return GeminiCoachResult(
        ok: false,
        error: 'Gemini call failed: $msg',
      );
    } catch (e) {
      return GeminiCoachResult(ok: false, error: 'Coach parse error: $e');
    }
  }

  String? _extractText(Map<String, dynamic>? data) {
    if (data == null) return null;
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;
    final first = candidates.first;
    if (first is! Map) return null;
    final content = first['content'];
    if (content is! Map) return null;
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) return null;
    final part = parts.first;
    if (part is! Map) return null;
    return part['text'] as String?;
  }
}
