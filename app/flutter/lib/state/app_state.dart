// 앱 상태 — 급수(level) · 방문 기록(visits). shared_preferences 저장 · 복원, 실패 시 메모리 폴백(회귀 #7).
// 키는 목업(localStorage)과 동일: malgil.level · malgil.visits
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  AppState({int? level, Map<String, List<String>>? visits, SharedPreferences? prefs})
      : _level = _validLevel(level),
        _visits = {for (final e in (visits ?? {}).entries) e.key: List<String>.from(e.value)},
        // 이름 있는 인자 `prefs` 는 공개, 필드는 비공개로 둔다
        // ignore: prefer_initializing_formals
        _prefs = prefs;

  static const String keyLevel = 'malgil.level';
  static const String keyVisits = 'malgil.visits';
  static const int minLevel = 2;
  static const int maxLevel = 5;

  int? _level;
  final Map<String, List<String>> _visits;
  final SharedPreferences? _prefs;

  /// 사용자 급수 2(Lv1~2)·3·4·5. 미선택이면 null.
  int? get level => _level;

  /// 지역 code → 방문일(yyyy-mm-dd) 목록 (자기 신고).
  Map<String, List<String>> get visits => {for (final e in _visits.entries) e.key: List.unmodifiable(e.value)};

  static int? _validLevel(int? v) => (v != null && v >= minLevel && v <= maxLevel) ? v : null;

  /// 저장소에서 복원. 저장소가 없거나 깨져도 예외 없이 빈 상태로 시작한다.
  static Future<AppState> restore() async {
    SharedPreferences? prefs;
    int? level;
    Map<String, List<String>>? visits;
    try {
      prefs = await SharedPreferences.getInstance();
      level = prefs.getInt(keyLevel);
      final raw = prefs.getString(keyVisits);
      if (raw != null && raw.isNotEmpty) visits = decodeVisits(raw);
    } catch (e) {
      debugPrint('AppState.restore: storage unavailable, memory fallback ($e)');
      prefs = null;
    }
    return AppState(level: level, visits: visits, prefs: prefs);
  }

  /// `{"27200":["2026-09-14"]}` 형식. 형식이 어긋난 항목은 버린다.
  static Map<String, List<String>> decodeVisits(String raw) {
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
