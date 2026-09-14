// 워커 API 클라이언트 — 앱은 자체 /api/* 만 호출한다 (공사 도메인 직접 호출 금지 · TSD §8-4).
// 응답 형식: worker/README.md — 성공 {ok:true, fetchedAt, remaining, totalCount, items[]} · 실패 {ok:false, kind, message}
// 헤더 x-malgil-remaining · x-malgil-cache 보존.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// 빌드 시 `--dart-define=API_BASE=http://127.0.0.1:8787`. 비우면 같은 오리진 상대경로.
const String apiBaseFromEnv = String.fromEnvironment('API_BASE', defaultValue: '');

/// 응답 3분기: ok / quota / error
sealed class ApiResult {
  const ApiResult({required this.status, this.remaining, this.cache});
  final int status; // HTTP 상태 (네트워크 실패면 0)
  final String? remaining; // x-malgil-remaining
  final String? cache; // x-malgil-cache: hit | miss
}

class ApiOk extends ApiResult {
  const ApiOk({
    required super.status,
    super.remaining,
    super.cache,
    required this.items,
    required this.totalCount,
    required this.count,
    required this.fetchedAt,
    required this.body,
  });
  final List<Map<String, dynamic>> items;
  final int totalCount; // 상류 전체 건수
  final int count; // 남긴 건수 (type 없는 /api/places 는 필터 후)
  final String? fetchedAt;
  final Map<String, dynamic> body;
}

/// 429 — 일일 한도(kind quota) 또는 워커 레이트리밋(kind rate_limited)
class ApiQuota extends ApiResult {
  const ApiQuota({required super.status, super.remaining, super.cache, required this.kind, required this.message});
  final String kind;
  final String message;
  bool get isDailyQuota => kind == 'quota';
}

/// 그 외 (400·404·502·형식 오류·네트워크·타임아웃)
class ApiError extends ApiResult {
  const ApiError({required super.status, super.remaining, super.cache, required this.kind, required this.message});
  final String kind; // upstream | param_error | api_error | bad_request | not_found | network | timeout | malformed | http_<n>
  final String message;
}

class ApiClient {
  ApiClient({String? baseUrl, http.Client? client, this.timeout = const Duration(seconds: 20)})
      : baseUrl = _normalize(baseUrl ?? apiBaseFromEnv),
        _client = client ?? http.Client();

  final String baseUrl; // '' 이면 같은 오리진
  final http.Client _client;
  final Duration timeout;

  static String _normalize(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  Uri uri(String path, [Map<String, String>? query]) {
    final q = (query == null || query.isEmpty) ? null : query;
    if (baseUrl.isEmpty) {
      final rel = Uri(path: path, queryParameters: q);
      return kIsWeb ? Uri.base.resolveUri(rel) : rel;
    }
    return Uri.parse('$baseUrl$path').replace(queryParameters: q);
  }

  /// 시군구 코드 목록. regn(시도 2자리) 없으면 시도 16건.
  Future<ApiResult> ldong({String? regn}) => get('/api/ldong', {'regn': ?regn});

  /// 시군구 장소 목록. type 12|14|15|39 (선택).
  Future<ApiResult> places(String code, {String? type}) => get('/api/places', {'code': code, 'type': ?type});

  /// 장소 공통 상세 (detailCommon2)
  Future<ApiResult> place(String id) => get('/api/place/$id');

  /// 장소 소개 (detailIntro2) — type 필수
  Future<ApiResult> placeIntro(String id, String type) => get('/api/place/$id/intro', {'type': type});

  Future<ApiResult> get(String path, [Map<String, String>? query]) async {
    final u = uri(path, query);
    http.Response res;
    try {
      res = await _client.get(u, headers: const {'accept': 'application/json'}).timeout(timeout);
    } on TimeoutException {
      return const ApiError(status: 0, kind: 'timeout', message: 'Request timed out');
    } catch (e) {
      return ApiError(status: 0, kind: 'network', message: e.toString());
    }
    return parseResponse(res.statusCode, res.headers, res.body);
  }

  /// 상태·헤더·본문 → ApiResult. 테스트에서 픽스처로 직접 호출한다.
  static ApiResult parseResponse(int status, Map<String, String> headers, String body) {
    final remaining = _header(headers, 'x-malgil-remaining');
    final cache = _header(headers, 'x-malgil-cache');
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) json = decoded.cast<String, dynamic>();
    } catch (_) {
      json = null;
    }
    final kind = json?['kind'] as String?;
    final message = (json?['message'] as String?) ?? '';

    if (status == 429 || kind == 'quota' || kind == 'rate_limited') {
      return ApiQuota(status: status, remaining: remaining, cache: cache, kind: kind ?? 'quota', message: message);
    }
    if (json == null) {
      return ApiError(status: status, remaining: remaining, cache: cache, kind: 'malformed', message: 'Non-JSON response');
    }
    if (status == 200 && json['ok'] == true) {
      final items = ((json['items'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
      return ApiOk(
        status: status,
        remaining: remaining,
        cache: cache,
        items: items,
        totalCount: (json['totalCount'] as num?)?.toInt() ?? items.length,
        count: (json['count'] as num?)?.toInt() ?? items.length,
        fetchedAt: json['fetchedAt'] as String?,
        body: json,
      );
    }
    return ApiError(status: status, remaining: remaining, cache: cache, kind: kind ?? 'http_$status', message: message);
  }

  static String? _header(Map<String, String> h, String name) {
    for (final e in h.entries) {
      if (e.key.toLowerCase() == name) return e.value;
    }
    return null;
  }

  void close() => _client.close();
}
