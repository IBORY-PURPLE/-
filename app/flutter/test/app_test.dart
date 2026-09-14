// ?demo=1 → 급수 3 저장 + /map (회귀 #9) · AppState 메모리 폴백 (회귀 #7)
import 'package:flutter_test/flutter_test.dart';
import 'package:malgil/app.dart';
import 'package:malgil/state/app_state.dart';

void main() {
  group('demoRedirect', () {
    test('demo=1 이면 급수 3 저장 후 /map', () {
      final s = AppState();
      expect(demoRedirect(s, Uri.parse('/?demo=1')), '/map');
      expect(s.level, 3);
      expect(demoRedirect(AppState(level: 5), Uri.parse('/map?demo=1')), '/map');
    });
    test('demo 없으면 통과 · 기존 급수 유지', () {
      final s = AppState(level: 4);
      expect(demoRedirect(s, Uri.parse('/')), isNull);
      expect(demoRedirect(s, Uri.parse('/map')), isNull);
      expect(demoRedirect(s, Uri.parse('/?demo=0')), isNull);
      expect(s.level, 4);
    });
  });

  group('AppState (prefs 없음 = 메모리 폴백)', () {
    test('setLevel 범위 · notify · addVisit 중복 제거', () {
      final s = AppState();
      var n = 0;
      s.addListener(() => n++);
      expect(s.level, isNull);
      s.setLevel(3);
      expect(s.level, 3);
      expect(n, 1);
      s.setLevel(3); // 같은 값이면 알림 없음
      expect(n, 1);
      expect(() => s.setLevel(1), throwsArgumentError);
      expect(() => s.setLevel(6), throwsArgumentError);
      s.addVisit('27200', '2026-09-14');
      s.addVisit('27200', '2026-09-14');
      s.addVisit('27200', '2026-09-15');
      expect(s.visits['27200'], ['2026-09-14', '2026-09-15']);
      expect(n, 3);
    });
    test('복원값 검증 — 범위 밖 급수는 버림', () {
      expect(AppState(level: 9).level, isNull);
      expect(AppState(level: 2).level, 2);
      expect(AppState.decodeVisits('{"12730":["2026-09-01", 3], "x": "bad"}'), {'12730': ['2026-09-01']});
      expect(AppState.decodeVisits('[1,2]'), isEmpty);
    });
  });
}
