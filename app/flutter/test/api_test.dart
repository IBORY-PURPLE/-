// ④ ApiClient 응답 파서 — ok / quota / error 픽스처 (worker/README.md 형식)
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malgil/data/api.dart';

void main() {
  group('parseResponse', () {
    test('ok — items · totalCount · count · 헤더 보존', () {
      final body = jsonEncode({
        'ok': true,
        'fetchedAt': '2026-09-14T00:00:00Z',
        'remaining': 919,
        'totalCount': 142,
        'count': 106,
        'items': [
          {'contentid': '1', 'title': 'a'},
          {'contentid': '2', 'title': 'b'},
        ],
      });
      final r = ApiClient.parseResponse(200, {'X-Malgil-Remaining': '919', 'x-malgil-cache': 'hit'}, body);
      expect(r, isA<ApiOk>());
      final ok = r as ApiOk;
      expect(ok.items.length, 2);
      expect(ok.totalCount, 142);
      expect(ok.count, 106);
      expect(ok.fetchedAt, '2026-09-14T00:00:00Z');
      expect(ok.remaining, '919');
      expect(ok.cache, 'hit');
    });
    test('quota — 429 kind quota', () {
      final r = ApiClient.parseResponse(429, {'x-malgil-remaining': '0'}, jsonEncode({'ok': false, 'kind': 'quota', 'message': 'limit'}));
      expect(r, isA<ApiQuota>());
      expect((r as ApiQuota).isDailyQuota, true);
      expect(r.remaining, '0');
    });
    test('quota — 429 rate_limited 는 quota 분기 · isDailyQuota false', () {
      final r = ApiClient.parseResponse(429, {}, jsonEncode({'ok': false, 'kind': 'rate_limited', 'message': 'slow down'}));
      expect(r, isA<ApiQuota>());
      expect((r as ApiQuota).isDailyQuota, false);
    });
    test('error — 502 upstream · 404 not_found · 400 bad_request', () {
      for (final (status, kind) in [(502, 'upstream'), (404, 'not_found'), (400, 'bad_request')]) {
        final r = ApiClient.parseResponse(status, {}, jsonEncode({'ok': false, 'kind': kind, 'message': 'x'}));
        expect(r, isA<ApiError>(), reason: '$status');
        expect((r as ApiError).kind, kind);
        expect(r.status, status);
      }
    });
    test('error — 200 인데 ok:false (회귀 #1 평면 JSON 오류) · 비JSON', () {
      final r1 = ApiClient.parseResponse(200, {}, jsonEncode({'ok': false, 'kind': 'api_error', 'message': 'flat'}));
      expect(r1, isA<ApiError>());
      expect((r1 as ApiError).kind, 'api_error');
      final r2 = ApiClient.parseResponse(200, {}, '<html>oops</html>');
      expect(r2, isA<ApiError>());
      expect((r2 as ApiError).kind, 'malformed');
      final r3 = ApiClient.parseResponse(503, {}, '');
      expect((r3 as ApiError).kind, 'malformed');
    });
    test('ok — 빈 items (회귀 #2)', () {
      final r = ApiClient.parseResponse(200, {}, jsonEncode({'ok': true, 'totalCount': 0, 'items': []}));
      expect((r as ApiOk).items, isEmpty);
      expect(r.count, 0);
    });
  });

  group('ApiClient 경로 · 쿼리', () {
    test('baseUrl 있으면 절대 URL · 화이트리스트 파라미터만', () async {
      final seen = <Uri>[];
      final client = MockClient((req) async {
        seen.add(req.url);
        return http.Response(jsonEncode({'ok': true, 'items': []}), 200, headers: {'x-malgil-cache': 'miss'});
      });
      final api = ApiClient(baseUrl: 'http://127.0.0.1:8787/', client: client);
      await api.ldong();
      await api.ldong(regn: '30');
      await api.places('27200', type: '39');
      await api.place('1807489');
      await api.placeIntro('1807489', '39');
      expect(seen.map((u) => u.toString()), [
        'http://127.0.0.1:8787/api/ldong',
        'http://127.0.0.1:8787/api/ldong?regn=30',
        'http://127.0.0.1:8787/api/places?code=27200&type=39',
        'http://127.0.0.1:8787/api/place/1807489',
        'http://127.0.0.1:8787/api/place/1807489/intro?type=39',
      ]);
    });
    test('baseUrl 비면 상대경로 /api/…', () {
      final api = ApiClient(baseUrl: '', client: MockClient((_) async => http.Response('{}', 200)));
      expect(api.uri('/api/places', {'code': '27200'}).toString(), '/api/places?code=27200');
    });
    test('네트워크 예외 → ApiError(network)', () async {
      final api = ApiClient(baseUrl: 'http://x', client: MockClient((_) async => throw http.ClientException('down')));
      final r = await api.ldong();
      expect(r, isA<ApiError>());
      expect((r as ApiError).kind, 'network');
      expect(r.status, 0);
    });
  });
}
