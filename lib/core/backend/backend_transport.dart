import 'package:dio/dio.dart';
import 'package:fitness_os/core/backend/backend_config.dart';

class TransportResponse {
  const TransportResponse({required this.status, this.json});

  final int status;
  final Map<String, dynamic>? json;
}

abstract class BackendTransport {
  Future<TransportResponse> postSync({
    required List<int> bodyBytes,
    required Map<String, String> headers,
  });

  Future<TransportResponse> getManifest({required String fromDay});
}

class DioBackendTransport implements BackendTransport {
  DioBackendTransport(this._dio);

  final Dio _dio;

  @override
  Future<TransportResponse> postSync({
    required List<int> bodyBytes,
    required Map<String, String> headers,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/sync',
        data: bodyBytes,
        options: Options(
          contentType: 'application/json',
          headers: headers,
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
      final data = response.data;
      Map<String, dynamic>? json;
      if (data is Map) {
        json = Map<String, dynamic>.from(data);
      }
      return TransportResponse(
        status: response.statusCode ?? 0,
        json: json,
      );
    } on DioException {
      return const TransportResponse(status: 0);
    }
  }

  @override
  Future<TransportResponse> getManifest({required String fromDay}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/sync-manifest',
        queryParameters: {'from': fromDay},
        options: Options(
          validateStatus: (_) => true,
          responseType: ResponseType.json,
          headers: {
            'Authorization': 'Bearer ${BackendConfig.writeKey}',
          },
        ),
      );
      final data = response.data;
      Map<String, dynamic>? json;
      if (data is Map) {
        json = Map<String, dynamic>.from(data);
      }
      return TransportResponse(
        status: response.statusCode ?? 0,
        json: json,
      );
    } on DioException {
      return const TransportResponse(status: 0);
    }
  }
}