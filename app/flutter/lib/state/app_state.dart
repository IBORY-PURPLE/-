// 앱 상태 — 급수(level) · 방문 기록(visits) · 말벗 세션 관심(interests). shared_preferences 저장 · 복원, 실패 시 메모리 폴백(회귀 #7).
// 키는 목업(localStorage)과 동일: malgil.level · malgil.visits · malgil.interests
// ★ 세 키 모두 이 기기에만 남는다 — 서버 전송 · 이메일 수집 없음 (PRD F7 관심 등록 폼의 이메일 입력은 백엔드가 없어 넣지 않았다).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 체류 자기신고 요약 — 날짜가 1건 이상인 지역 수 · 날짜 합 (지도 「Your stays」)
typedef StayCount = ({int regions, int days});

class AppState extends ChangeNotifier {
  AppState({int? level, Map<String, List<String>>? visits, Map<String, List<String>>? interests, SharedPreferences? prefs})
      : _level = _validLevel(level),
        _visits = _copy(visits),
        _interests = _copy(interests),
        // 이름 있는 인자 `prefs` 는 공개, 필드는 비공개로 둔다
        // ignore: prefer_initializing_formals
        _prefs = prefs;

  static const String keyLevel = 'malgil.level';
  static const String keyVisits = 'malgil.visits';
  static const String keyInterests = 'malgil.interests';
  static const int minLevel = 2;
  static const int maxLevel = 5;

  int? _level;
  final Map<String, List<String>> _visits;
  final Map<String, List<String>> _interests;
  final SharedPreferences? _prefs;

  /// 사용자 급수 2(Lv1~2)·3·4·5. 미선택이면 null.
  int? get level => _level;

  /// 지역 code → 방문일(yyyy-mm-dd) 목록 (자기 신고).
  Map<String, List<String>> get visits => _view(_visits);

  /// 지역 code → 관심 표시한 말벗 세션 id 목록 (예: `{"27200": ["s2"]}`). 기기 저장만.
  Map<String, List<String>> get interests => _view(_interests);

  /// 체류 자기신고 요약 — 지역 수 · 날짜 합. 0건이면 (0, 0).
  StayCount get stayCount {
    var regions = 0;
    var days = 0;
    for (final l in _visits.values) {
      if (l.isEmpty) continue;
      regions++;
      days += l.length;
    }
    return (regions: regions, days: days);
  }

  bool hasInterest(String code, String sessionId) => _interests[code]?.contains(sessionId) ?? false;

  static int? _validLevel(int? v) => (v != null && v >= minLevel && v <= maxLevel) ? v : null;
  static Map<String, List<String>> _copy(Map<String, List<String>>? m) =>
      {for (final e in (m ?? const {}).entries) e.key: List<String>.from(e.value)};
  static Map<String, List<String>> _view(Map<String, List<String>> m) =>
      {for (final e in m.entries) e.key: List.unmodifiable(e.value)};

  /// 저장소에서 복원. 저장소가 없거나 깨져도 예외 없이 빈 상태로 시작한다. 키 하나가 깨져도 나머지는 살린다.
  static Future<AppState> restore() async {
    SharedPreferences? prefs;
    int? level;
    Map<String, List<String>>? visits;
    Map<String, List<String>>? interests;
    try {
      prefs = await SharedPreferences.getInstance();
      level = prefs.getInt(keyLevel);
      visits = _readLists(prefs, keyVisits);
      interests = _readLists(prefs, keyInterests);
    } catch (e) {
      debugPrint('AppState.restore: storage unavailable, memory fallback ($e)');
      prefs = null;
    }
    return AppState(level: level, visits: visits, interests: interests, prefs: prefs);
  }

  static Map<String, List<String>>? _readLists(SharedPreferences prefs, String key) {
    try {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      return decodeCodeLists(raw);
    } catch (e) {
      debugPrint('AppState.restore: $key unreadable, starting empty ($e)');
      return null;
    }
  }

  /// `{"27200":["2026-09-14"]}` 형식 (visits · interests 공통). 형식이 어긋난 항목은 버린다.
  static Map<String, List<String>> decodeCodeLists(String raw) {
    final out = <String, List<String>>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return out;
    decoded.forEach((k, v) {
      if (k is String && v is List) {
        out[k] = v.whereType<String>().toList();
      }
    });
    return out;
  }

  static Map<String, List<String>> decodeVisits(String raw) => decodeCodeLists(raw);
  static Map<String, List<String>> decodeInterests(String raw) => decodeCodeLists(raw);

  void setLevel(int n) {
    final v = _validLevel(n);
    if (v == null) throw ArgumentError.value(n, 'level', 'must be $minLevel..$maxLevel');
    if (_level == v) return;
    _level = v;
    notifyListeners();
    _persist(() => _prefs?.setInt(keyLevel, v));
  }

  void clearLevel() {
    if (_level == null) return;
    _level = null;
    notifyListeners();
    _persist(() => _prefs?.remove(keyLevel));
  }

  /// 방문 추가. 같은 날 같은 지역은 한 번만 남긴다.
  void addVisit(String code, String yyyyMmDd) {
    final list = _visits.putIfAbsent(code, () => <String>[]);
    if (list.contains(yyyyMmDd)) return;
    list.add(yyyyMmDd);
    notifyListeners();
    _persist(() => _prefs?.setString(keyVisits, jsonEncode(_visits)));
  }

  /// 말벗 세션 관심 토글 — 있으면 해제, 없으면 등록. 빈 지역은 키를 지운다. 기기 저장만.
  void toggleInterest(String code, String sessionId) {
    final list = _interests.putIfAbsent(code, () => <String>[]);
    if (list.contains(sessionId)) {
      list.remove(sessionId);
      if (list.isEmpty) _interests.remove(code);
    } else {
      list.add(sessionId);
    }
    notifyListeners();
    _persist(() => _prefs?.setString(keyInterests, jsonEncode(_interests)));
  }

  void _persist(Future<bool>? Function() write) {
    try {
      write()?.catchError((Object e) {
        debugPrint('AppState: persist failed, keeping memory value ($e)');
        return false;
      });
    } catch (e) {
      debugPrint('AppState: persist threw, keeping memory value ($e)');
    }
  }
}
